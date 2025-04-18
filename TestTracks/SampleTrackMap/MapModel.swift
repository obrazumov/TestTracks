//
//  MapModel.swift
//  TestTracks
//
//  Created by Dmitriy Obrazumov on 13/03/2025.
//

import Foundation
import _MapKit_SwiftUI

enum TrackType: CaseIterable {
    case road
    case route
    
    var fileName: String {
        switch self {
        case .road:
            return "export.geojson"
        case .route:
            return "output_track 2.nmea"//"raw_track 3.nmea"
        }
    }
}

final class MapModel: ObservableObject {
    let coordinateConverter: CoordinateConverter = .init()
    let mapMatcher: MapMatching = MapMatcherFactory.createMapMatcher(type: .custom(MyMapMatcher()))
    @Published var tracks: [Track] = []
    @Published var roads: [Road] = []
    @Published var roadsOverlay: RoadsOverlay? = nil
    @Published var usedRoadsOverlay: RoadsOverlay? = nil
    @Published var candidates: [TestCandidat] = []
    @Published var isLoading: Bool = false
    @Published var loadingProgress: String = "Начало загрузки..."
    @Published var processingProgress: Float = 0.0 // Прогресс обработки (0.0 - 1.0)
    @Published var isProcessing: Bool = false // Флаг, указывающий на выполнение длительной операции
    @Published var trackPointCount: Int = 0 // Количество точек в треке
    @Published var position: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    ))
    var roadSegmentsForDisplay: [RoadSegment] = []
    // Расстояние для определения близости дороги к треку (в метрах)
    private let proximityDistance: Double = 200.0 // Увеличено с 100 до 200 метров
    // Шаг для проверки точек трека (проверяем каждую n-ю точку)
    private let trackPointCheckStride = 3
    private var trackPoints: [TrackPoint] = []
    private var originalTrack: Track? = nil
    private var currentIndex = 0
    // Флаг для отмены операции обработки
    private var isCancelled = false
    private var originalRoadSegments: [RoadSegment] = [] // Для хранения оригинальных сегментов
    
    func loadTracks() async {
        // Устанавливаем флаг загрузки
        await MainActor.run {
            isLoading = true
            loadingProgress = "Начало загрузки..."
        }
        
        // ЭТАП 1: Загрузка трека
        let trackCoordinates = await loadCoordinates()
        
        // ЭТАП 2: Загрузка дорог - с существенными оптимизациями
        await loadRoads(trackCoordinates: trackCoordinates)
        // Завершаем загрузку
        await updateProgress("Загрузка завершена")
        await MainActor.run {
            self.isLoading = false
            // Обновляем счетчик точек
            self.trackPointCount = trackPoints.count
        }
    }
    func next() async {
        guard currentIndex < trackPoints.count && !originalRoadSegments.isEmpty else { return }
        
        // Отмечаем начало обработки одной точки
        await MainActor.run {
            self.isProcessing = true
            self.processingProgress = 0.5 // Устанавливаем 50% для одиночной операции
        }
        
        // Получаем bbox для текущей точки трека и фильтруем roadSegments
        let bbox = self.getTrackBoundingBox([trackPoints[currentIndex].coordinate], expandBy: 0.01).expanded
        
        // Используем общий метод фильтрации
        let filteredRoadSegments = filterRoadSegmentsByBBox(segments: originalRoadSegments, bbox: bbox)
        
        print("Для точки \(currentIndex) отфильтровано \(filteredRoadSegments.count) из \(originalRoadSegments.count) сегментов дорог")
        
        if let candidate = await mapMatcher.matchTrackCandidat(gpsTrack: trackPoints, roadSegments: filteredRoadSegments, index: currentIndex) {
            await MainActor.run {
                self.candidates = [candidate]
                self.processingProgress = 1.0
                // Небольшая задержка перед скрытием индикатора для лучшего UX
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.isProcessing = false
                }
            }
        } else {
            await MainActor.run {
                self.isProcessing = false
            }
        }
        
        currentIndex += 1
        if currentIndex >= trackPoints.count {
            currentIndex = 0
        }
    }
    func all() async {
        guard !trackPoints.isEmpty && !originalRoadSegments.isEmpty else { return }
        
        // Отмечаем начало обработки и сбрасываем флаг отмены
        isCancelled = false
        await MainActor.run {
            self.isProcessing = true
            self.processingProgress = 0.0
        }
        
        // Получаем bbox для trackpoints
        let bbox = self.getTrackBoundingBox(trackPoints.map { $0.coordinate }, expandBy: 0.01).expanded
        
        // Фильтруем roadSegments по bbox используя наш новый метод
        let filteredRoadSegments = filterRoadSegmentsByBBox(segments: originalRoadSegments, bbox: bbox)
        
        print("Отфильтровано \(filteredRoadSegments.count) из \(originalRoadSegments.count) сегментов дорог в пределах bbox")
        
        let totalPoints = trackPoints.count
        
        // Используем TaskGroup для параллельной обработки
        var allCandidates = [Int: TestCandidat]() // Для сохранения порядка
        
        // Разбиваем на группы для обработки
        let batchSize = 5 // Размер пакета для обработки
        let numBatches = (totalPoints + batchSize - 1) / batchSize // Округление вверх
        
        for batchIndex in 0..<numBatches {
            // Проверяем флаг отмены перед каждой партией
            if isCancelled {
                await MainActor.run {
                    self.isProcessing = false
                }
                return
            }
            
            // Вычисляем диапазон индексов для текущей партии
            let startIdx = batchIndex * batchSize
            let endIdx = min(startIdx + batchSize, totalPoints)
            
            // Создаем TaskGroup для параллельной обработки внутри партии
            var batchResults = [Int: TestCandidat]()
            
            try? await withThrowingTaskGroup(of: (Int, TestCandidat?).self) { group in
                // Добавляем задачи в группу
                for i in startIdx..<endIdx {
                    group.addTask {
                        // Проверка на отмену внутри задачи
                        if self.isCancelled {
                            return (i, nil)
                        }
                        let candidate = await self.mapMatcher.matchTrackCandidat(
                            gpsTrack: self.trackPoints, 
                            roadSegments: filteredRoadSegments, 
                            index: i
                        )
                        return (i, candidate)
                    }
                }
                
                // Собираем результаты
                for try await (index, candidate) in group {
                    if let candidate = candidate {
                        batchResults[index] = candidate
                    }
                }
            }
            
            // Если операция отменена, выходим
            if isCancelled {
                await MainActor.run {
                    self.isProcessing = false
                }
                return
            }
            
            // Добавляем результаты партии в общий массив
            for (index, candidate) in batchResults {
                allCandidates[index] = candidate
            }
            
            // Обновляем прогресс после каждой партии
            let currentProgress = Float(endIdx) / Float(totalPoints)
            await MainActor.run {
                self.processingProgress = currentProgress
                currentIndex = endIdx - 1
            }
        }
        
        // Подготавливаем финальный массив в правильном порядке
        if !isCancelled {
            let finalCandidates = (0..<totalPoints).compactMap { allCandidates[$0] }
            
            await MainActor.run {
                self.candidates = finalCandidates
                self.isProcessing = false
                self.processingProgress = 1.0
            }
        }
    }
    // Метод для отмены текущей операции обработки
    func cancelProcessing() {
        isCancelled = true
    }
    // Метод для визуализации отфильтрованных дорожных сегментов
    func visualizeFilteredRoadSegments() {
        guard !trackPoints.isEmpty && !originalRoadSegments.isEmpty else { return }
        
        // Получаем bbox для всех trackpoints
        let bbox = self.getTrackBoundingBox(trackPoints.map { $0.coordinate }, expandBy: 0.01).expanded
        
        // Фильтруем roadSegments по bbox используя наш новый метод
        let filteredRoadSegments = filterRoadSegmentsByBBox(segments: originalRoadSegments, bbox: bbox)
        
        print("Для визуализации отфильтровано \(filteredRoadSegments.count) из \(originalRoadSegments.count) сегментов дорог в пределах bbox")
        
        // Обновляем модель для отображения только отфильтрованных сегментов
        Task { @MainActor in
            // Устанавливаем отфильтрованные сегменты для отображения
            self.roadSegmentsForDisplay = filteredRoadSegments
            
            // Уведомляем об изменении для обновления отображения
            self.objectWillChange.send()
        }
    }
    func resetRoadSegments() {
        self.roadSegmentsForDisplay = []
    }
}

private extension MapModel {
    func loadCoordinates() async -> [CLLocationCoordinate2D] {
        await updateProgress("Загрузка GPS трека...")
        var trackCoordinates: [CLLocationCoordinate2D] = []
        
        if let filePath = Bundle.main.path(forResource: TrackType.route.fileName, ofType: nil) {
            let fileURL = URL(fileURLWithPath: filePath)
            if fileURL.pathExtension.lowercased() == "nmea" {
                let data = TrackParser.parseNMEAFile(fileURL)
                let trackPoints = data.map({ TrackPoint(coordinate: $0.coordinate, timestamp: $0.timestamp)})
                trackCoordinates = trackPoints.map({ $0.coordinate })
                
                if !trackCoordinates.isEmpty {
                    // Создаем оригинальный трек
                    self.originalTrack = Track(
                        name: fileURL.deletingPathExtension().lastPathComponent,
                        coordinates: trackCoordinates,
                        color: .red
                    )
                    let center = trackCoordinates[0]
                    // Обновляем UI с оригинальным треком
                    await MainActor.run {
                        self.tracks = [self.originalTrack!]
                        // Устанавливаем область карты на трек
                        self.position = .region(MKCoordinateRegion(
                            center: center,
                            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)))
                    }
                    
                    // Сохраняем trackPoints для последующего использования
                    self.trackPoints = trackPoints
                }
            }
        }
        return trackCoordinates
    }
    func loadRoadSegment() async -> [RoadSegment] {
        await updateProgress("Загрузка дорожных сегментов...")
        
        if let filePath = Bundle.main.path(forResource: TrackType.road.fileName, ofType: nil) {
            let fileURL = URL(fileURLWithPath: filePath)
            if fileURL.pathExtension.lowercased() == "geojson" {
                let startTime = Date()
                let roadSegments = coordinateConverter.loadRoadSegmentsFromGeoJSON(fileURL: fileURL)
                let endTime = Date()
                let loadTime = endTime.timeIntervalSince(startTime)
                
                await updateProgress("Загружено \(roadSegments.count) дорожных сегментов за \(String(format: "%.2f", loadTime)) сек")
                
                return roadSegments
            } else {
                await updateProgress("Файл \(TrackType.road.fileName) не является GeoJSON файлом")
                return []
            }
        } else {
            await updateProgress("Не удалось найти файл \(TrackType.road.fileName)")
            return []
        }
    }
    func loadRoads(trackCoordinates: [CLLocationCoordinate2D]) async {
        await updateProgress("Загрузка дорог из GeoJSON...")
        if let filePath = Bundle.main.path(forResource: TrackType.road.fileName, ofType: nil) {
            let fileURL = URL(fileURLWithPath: filePath)
            if fileURL.pathExtension.lowercased() == "geojson" {
                // Проверяем, есть ли трек, без которого невозможно определить bbox
                guard !trackCoordinates.isEmpty else {
                    await updateProgress("Не удалось загрузить трек для определения области отображения дорог")
                    await MainActor.run {
                        self.isLoading = false
                    }
                    return
                }
                
                // Вычисляем ограничивающий прямоугольник трека для оптимизации
                // Явно используем bbox для фильтрации дорог
                let bbox = self.getTrackBoundingBox(trackCoordinates, expandBy: 0.05)
                print("BBox трека: оригинальный = (\(bbox.original.minLat), \(bbox.original.maxLat), \(bbox.original.minLon), \(bbox.original.maxLon))")
                print("BBox трека: расширенный = (\(bbox.expanded.minLat), \(bbox.expanded.maxLat), \(bbox.expanded.minLon), \(bbox.expanded.maxLon))")
                
                // Увеличиваем максимальное количество дорог
                let maxRoads = 150000 // Увеличено с 10000 до 15000 для отображения большего количества дорог
                
                await updateProgress("Чтение GeoJSON файла с фильтрацией по области трека...")
                
                // Создаем наблюдателя прогресса
                let progressObserver = NotificationCenter.default.addObserver(
                    forName: .roadLoadingProgress,
                    object: nil,
                    queue: .main) { [weak self] notification in
                        if let progress = notification.userInfo?["progress"] as? String {
                            Task { @MainActor in
                                self?.loadingProgress = progress
                                print("Прогресс: \(progress)")
                            }
                            
                            // Если есть временные дороги, обновляем их
                            if let temporaryRoads = notification.userInfo?["roads"] as? [Road],
                               !temporaryRoads.isEmpty {
                                Task { @MainActor in
                                    // Обновляем дороги по мере их загрузки для интерактивности
                                    self?.roads = temporaryRoads
                                }
                            }
                        }
                    }
                
                // ВАЖНО: Явно передаем bbox для фильтрации, используя расширенный bbox
                let allRoads = TrackParser.parseGeoJSONToRoadsLazy(
                    fileURL,
                    boundingBox: bbox.expanded, // Явно используем расширенный bbox
                    maxRoads: maxRoads
                )
                
                // Удаляем наблюдателя
                NotificationCenter.default.removeObserver(progressObserver)
                
                print("Загружено всего \(allRoads.count) дорог из GeoJSON (ограничено до \(maxRoads))")
                print("Статистика дорог:")
                print("- Дороги с 1 точкой: \(allRoads.filter { $0.coordinates.count == 1 }.count)")
                print("- Дороги с 2 точками: \(allRoads.filter { $0.coordinates.count == 2 }.count)")
                print("- Дороги с 3+ точками: \(allRoads.filter { $0.coordinates.count > 2 }.count)")
                
                await updateProgress("Фильтрация дорог по области трека (\(allRoads.count) загружено)...")
                
                // Дополнительная фильтрация дорог по bbox
                // Проверяем только те дороги, которые имеют хотя бы одну точку в расширенном bbox трека
                let filteredRoads = self.filterRoadsByBBox(roads: allRoads, bbox: bbox.expanded)
                print("После дополнительной фильтрации осталось \(filteredRoads.count) дорог")
                
                // Определяем дороги, используемые треком
                await updateProgress("Определение дорог, используемых треком (\(filteredRoads.count) дорог)...")
                let usedRoads = self.markUsedRoads(roads: filteredRoads, trackCoordinates: trackCoordinates)
                
                // ВАЖНО: Проверяем, что у нас есть дороги для отображения
                if usedRoads.isEmpty {
                    print("ОШИБКА: Не найдено дорог для отображения")
                    await updateProgress("Не найдено дорог в указанной области")
                } else {
                    print("Инициализация оверлеев с \(usedRoads.count) дорогами")
                    
                    let usedRoadsCount = usedRoads.filter { $0.isUsedByTrack }.count
                    print("Из них используется треком: \(usedRoadsCount)")
                }
                
                // Обновляем UI с дорогами сразу, не дожидаясь доп. обработки
                await MainActor.run {
                    self.roads = usedRoads
                    
                    // Создаем оверлеи дорог для более эффективной отрисовки
                    // Один оверлей для всех дорог
                    self.roadsOverlay = RoadsOverlay(roads: usedRoads, isUsedRoadsOnly: false)
                    
                    // Дополнительный оверлей только для дорог, используемых треком
                    self.usedRoadsOverlay = RoadsOverlay(roads: usedRoads, isUsedRoadsOnly: true)
                    
                    print("Оверлеи созданы: all roads(\(usedRoads.count)), used roads(\(usedRoads.filter { $0.isUsedByTrack }.count))")
                    
                    // Уведомляем UI об обновлении оверлеев
                    self.objectWillChange.send()
                }
                
                // ОПТИМИЗАЦИЯ: Используем только подмножество дорог для map matching
                await updateProgress("Подготовка дорожных сегментов для сопоставления...")
                
                // Добавляем отладочную информацию
                let usedRoadsCount = usedRoads.filter { $0.isUsedByTrack }.count
                let allRoadsCount = usedRoads.count
                print("Всего дорог: \(allRoadsCount), используемых треком: \(usedRoadsCount)")
                await updateProgress("Найдено \(usedRoadsCount) дорог, используемых треком из \(allRoadsCount) общего количества")
                
                // ОПТИМИЗАЦИЯ: Используем только дороги, которые помечены как используемые треком
                let roadsForMapping = usedRoads.filter { $0.isUsedByTrack }
                
                // Если дорог для маппинга мало, добавляем некоторые неиспользуемые дороги
                var finalRoadsForMapping = roadsForMapping
                if roadsForMapping.count < 50 {
                    print("Мало дорог для маппинга (\(roadsForMapping.count)), добавляем часть неиспользуемых")
                    let unusedRoads = usedRoads.filter { !$0.isUsedByTrack }
                    let additionalRoads = unusedRoads.count > 100 ? Array(unusedRoads.prefix(100)) : unusedRoads
                    finalRoadsForMapping = roadsForMapping + additionalRoads
                }
                
                print("Использую \(finalRoadsForMapping.count) дорог для маппинга")
                
                // Извлекаем координаты для маппинга
                let roadCoordinates = self.extractCoordinatesForMapMatching(roads: finalRoadsForMapping)
                self.originalRoadSegments = await loadRoadSegment()
                print("Извлечено \(roadCoordinates.count) координат для маппинга")
                
                if !roadCoordinates.isEmpty {
                    print("Создано \(self.originalRoadSegments.count) дорожных сегментов")
                    
                    // Если у нас есть трек и дорожные сегменты, делаем map matching
                    if !trackCoordinates.isEmpty && !self.originalRoadSegments.isEmpty {
                        await updateProgress("Сопоставление трека с дорогами (\(self.originalRoadSegments.count) сегментов)...")
                        // Создаем скорректированный трек
                        let correctedCoordinates = self.mapMatcher.matchTrack(gpsTrack: self.trackPoints, roadSegments: self.originalRoadSegments, maxDistance: 15, forceSnapToRoad: true, maxForceSnapDistance: 30, removeDuplicates: true, fillGaps: true, simplifyTrack: false)
                        
                        let correctedTrack = Track(
                            name: "\(fileURL.deletingPathExtension().lastPathComponent)_corrected",
                            coordinates: correctedCoordinates,
                            color: .green
                        )
                        
                        // Обновляем UI с обоими треками
                        await MainActor.run {
                            if let originalTrack = self.originalTrack {
                                self.tracks = [originalTrack, correctedTrack]
                            }
                        }
                    }
                }
            }
        }
        
    }
    // Метод для обновления прогресса загрузки
    func updateProgress(_ message: String) async {
        await MainActor.run {
            self.loadingProgress = message
            print("Прогресс: \(message)")
        }
    }
    
    // Вычисляет ограничивающий прямоугольник трека и его расширенную версию
    func getTrackBoundingBox(_ coordinates: [CLLocationCoordinate2D], expandBy: Double) -> (
        original: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double),
        expanded: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)
    ) {
        var minLat = Double.infinity
        var maxLat = -Double.infinity
        var minLon = Double.infinity
        var maxLon = -Double.infinity
        
        for coord in coordinates {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }
        
        // Расширяем область для поиска ближайших дорог
        let original = (minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon)
        let expanded = (
            minLat: minLat - expandBy,
            maxLat: maxLat + expandBy,
            minLon: minLon - expandBy,
            maxLon: maxLon + expandBy
        )
        
        return (original, expanded)
    }
    
    // Проверяет, находится ли точка рядом с дорогой
    func isPointNearRoad(point: CLLocationCoordinate2D, road: Road, maxDistance: Double) -> Bool {
        let pointLocation = CLLocation(latitude: point.latitude, longitude: point.longitude)
        
        // Проверяем расстояние до каждого сегмента дороги
        for i in 0..<road.coordinates.count - 1 {
            let start = road.coordinates[i]
            let end = road.coordinates[i + 1]
            
            let startLocation = CLLocation(latitude: start.latitude, longitude: start.longitude)
            let endLocation = CLLocation(latitude: end.latitude, longitude: end.longitude)
            
            let distance = self.distanceFromPoint(point, toLineSegment: start, end: end)
            
            if distance <= maxDistance {
                return true
            }
        }
        
        return false
    }
    
    // Функция вычисления расстояния между точкой и линией (в метрах)
    func distanceFromPoint(_ point: CLLocationCoordinate2D,
                           toLineSegment start: CLLocationCoordinate2D,
                           end: CLLocationCoordinate2D) -> Double {
        let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
        let startLocation = CLLocation(latitude: start.latitude, longitude: start.longitude)
        let endLocation = CLLocation(latitude: end.latitude, longitude: end.longitude)
        
        let lineLength = startLocation.distance(from: endLocation)
        if lineLength == 0 {
            return location.distance(from: startLocation)
        }
        
        var t = ((point.latitude - start.latitude) * (end.latitude - start.latitude) +
                 (point.longitude - start.longitude) * (end.longitude - start.longitude)) / (lineLength * lineLength)
        t = max(0, min(1, t))
        
        let nearestLat = start.latitude + t * (end.latitude - start.latitude)
        let nearestLon = start.longitude + t * (end.longitude - start.longitude)
        let nearestPoint = CLLocation(latitude: nearestLat, longitude: nearestLon)
        
        return location.distance(from: nearestPoint)
    }
    
    // Проверяет, соединяются ли две дороги (имеют близкие конечные точки)
    func areRoadsConnected(road1: Road, road2: Road, maxDistance: Double) -> Bool {
        guard !road1.coordinates.isEmpty && !road2.coordinates.isEmpty else { return false }
        
        // Получаем начальные и конечные точки обеих дорог
        let road1Start = road1.coordinates.first!
        let road1End = road1.coordinates.last!
        let road2Start = road2.coordinates.first!
        let road2End = road2.coordinates.last!
        
        // Проверяем все возможные комбинации соединения
        let startStartDistance = calculateDistance(coord1: road1Start, coord2: road2Start)
        let startEndDistance = calculateDistance(coord1: road1Start, coord2: road2End)
        let endStartDistance = calculateDistance(coord1: road1End, coord2: road2Start)
        let endEndDistance = calculateDistance(coord1: road1End, coord2: road2End)
        
        // Если любая пара конечных точек достаточно близка, считаем дороги соединенными
        return min(min(startStartDistance, startEndDistance), min(endStartDistance, endEndDistance)) <= maxDistance
    }
    
    // Вычисляет расстояние между двумя координатами в метрах
    func calculateDistance(coord1: CLLocationCoordinate2D, coord2: CLLocationCoordinate2D) -> Double {
        let location1 = CLLocation(latitude: coord1.latitude, longitude: coord1.longitude)
        let location2 = CLLocation(latitude: coord2.latitude, longitude: coord2.longitude)
        return location1.distance(from: location2)
    }
    
    // Новый метод для фильтрации дорог по bbox
    func filterRoadsByBBox(roads: [Road], bbox: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)) -> [Road] {
        print("\nФильтрация дорог по bbox:")
        print("- Всего дорог до фильтрации: \(roads.count)")
        print("- Bbox: \(bbox)")
        
        let filteredRoads = roads.filter { road in
            // Проверяем, что хотя бы одна точка дороги находится в bbox
            road.coordinates.contains { coord in
                coord.latitude >= bbox.minLat && coord.latitude <= bbox.maxLat &&
                coord.longitude >= bbox.minLon && coord.longitude <= bbox.maxLon
            }
        }
        
        print("- Дорог после фильтрации: \(filteredRoads.count)")
        print("- Отфильтровано: \(roads.count - filteredRoads.count)")
        
        // Статистика по отфильтрованным дорогам
        let filteredStats = filteredRoads.reduce(into: [Int: Int]()) { counts, road in
            counts[road.coordinates.count, default: 0] += 1
        }
        print("\nСтатистика отфильтрованных дорог:")
        for (pointCount, count) in filteredStats.sorted(by: { $0.key < $1.key }) {
            print("- Дороги с \(pointCount) точками: \(count)")
        }
        
        return filteredRoads
    }
    
    // Оптимизированный метод для маркировки дорог, используемых треком
    func markUsedRoads(roads: [Road], trackCoordinates: [CLLocationCoordinate2D]) -> [Road] {
        guard !trackCoordinates.isEmpty else { return roads }
        
        let startTime = Date()
        
        // Создаем упрощенный трек с меньшей толерантностью для более точного определения используемых дорог
        let simplifiedTrack = coordinateConverter.simplifyTrack(
            coordinates: trackCoordinates,
            tolerance: 5.0 // Уменьшено с 15.0 до 5.0 для сохранения более детального трека
        )
        
        print("Трек упрощен с \(trackCoordinates.count) до \(simplifiedTrack.count) точек")
        
        // Получаем bbox трека для быстрой фильтрации
        let trackBBox = getTrackBoundingBox(trackCoordinates, expandBy: 0.01).original // Используем оригинальный bbox без большого расширения
        
        // Создаем прямоугольники для каждого сегмента трека для быстрой проверки
        var trackSegmentBounds: [(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double, start: CLLocationCoordinate2D, end: CLLocationCoordinate2D)] = []
        
        for i in 0..<simplifiedTrack.count - 1 {
            let start = simplifiedTrack[i]
            let end = simplifiedTrack[i + 1]
            let minLat = min(start.latitude, end.latitude) - 0.001 // ~100м буфер
            let maxLat = max(start.latitude, end.latitude) + 0.001
            let minLon = min(start.longitude, end.longitude) - 0.001
            let maxLon = max(start.longitude, end.longitude) + 0.001
            
            trackSegmentBounds.append((minLat, maxLat, minLon, maxLon, start, end))
        }
        
        // Параллельная обработка для ускорения
        // Разбиваем дороги на части для параллельной обработки
        let chunkSize = max(1, roads.count / 4) // 4 части для параллельной обработки
        let chunks = stride(from: 0, to: roads.count, by: chunkSize).map { i in
            let end = min(i + chunkSize, roads.count)
            return Array(roads[i..<end])
        }
        
        let processingGroup = DispatchGroup()
        var processedChunks: [[Road]] = Array(repeating: [], count: chunks.count)
        
        for (index, chunk) in chunks.enumerated() {
            let processingQueue = DispatchQueue(label: "com.app.roadprocessing.\(index)", qos: .userInitiated)
            
            processingGroup.enter()
            processingQueue.async {
                let processedRoads = chunk.map { road -> Road in
                    // Флаг для отметки дороги как используемой треком
                    var isUsed = false
                    
                    // Дорога уже гарантированно в bbox трека (отфильтрована ранее)
                    // Для оптимизации используем уже вычисленный boundingBox дороги
                    let roadBBox = road.boundingBox
                    
                    // Быстрая проверка: есть ли хоть один сегмент трека, который пересекается с дорогой
                    for segment in trackSegmentBounds {
                        // Проверяем пересечение ограничивающих прямоугольников
                        if !(roadBBox.maxLat < segment.minLat ||
                             roadBBox.minLat > segment.maxLat ||
                             roadBBox.maxLon < segment.minLon ||
                             roadBBox.minLon > segment.maxLon) {
                            
                            // Более детальная проверка только для потенциально пересекающихся
                            let distance = self.approximateDistanceFromRoadToSegment(
                                road: road,
                                segmentStart: segment.start,
                                segmentEnd: segment.end
                            )
                            
                            if distance < self.proximityDistance {
                                isUsed = true
                                break
                            }
                        }
                    }
                    
                    return Road(coordinates: road.coordinates, isUsedByTrack: isUsed)
                }
                
                processedChunks[index] = processedRoads
                processingGroup.leave()
            }
        }
        
        // Ожидаем завершения обработки всех дорог
        processingGroup.wait()
        
        // Объединяем результаты
        let result = processedChunks.flatMap { $0 }
        
        let endTime = Date()
        let elapsedTime = endTime.timeIntervalSince(startTime)
        print("Маркировка дорог заняла \(String(format: "%.2f", elapsedTime)) секунд")
        
        let usedCount = result.filter { $0.isUsedByTrack }.count
        print("Маркировано \(usedCount) используемых дорог из \(result.count)")
        
        return result
    }
    
    // Оптимизированный метод для быстрой приблизительной проверки расстояния между дорогой и сегментом трека
    func approximateDistanceFromRoadToSegment(road: Road, segmentStart: CLLocationCoordinate2D, segmentEnd: CLLocationCoordinate2D) -> Double {
        guard !road.coordinates.isEmpty else { return Double.infinity }
        
        // Для скорости проверяем только начало и конец дороги
        let roadStart = road.coordinates.first!
        let roadEnd = road.coordinates.last!
        
        let distanceStart = self.distanceFromPoint(roadStart, toLineSegment: segmentStart, end: segmentEnd)
        let distanceEnd = self.distanceFromPoint(roadEnd, toLineSegment: segmentStart, end: segmentEnd)
        
        // Также проверяем расстояние от трека до дороги
        let distanceTrackStart = self.distanceFromPoint(segmentStart, toLineSegment: roadStart, end: roadEnd)
        let distanceTrackEnd = self.distanceFromPoint(segmentEnd, toLineSegment: roadStart, end: roadEnd)
        
        return min(min(distanceStart, distanceEnd), min(distanceTrackStart, distanceTrackEnd))
    }
    
    // Метод для извлечения координат только для map matching (для оптимизации)
    func extractCoordinatesForMapMatching(roads: [Road]) -> [CLLocationCoordinate2D] {
        // Берем только используемые дороги и строго ограничиваем их количество
        let usedRoads = roads.filter { $0.isUsedByTrack }
        
        // Если используемых дорог нет или очень мало, берем часть всех дорог
        let roadsToProcess: [Road]
        if usedRoads.count < 50 {
            print("Мало используемых дорог (\(usedRoads.count)), добавляем из общего пула")
            let unusedRoads = roads.filter { !$0.isUsedByTrack }
            let additionalRoads = unusedRoads.count > 150 ? Array(unusedRoads.prefix(150)) : unusedRoads
            roadsToProcess = usedRoads + additionalRoads
        } else {
            // Строго ограничиваем количество используемых дорог
            roadsToProcess = usedRoads.count > 200 ? Array(usedRoads.prefix(200)) : usedRoads
        }
        
        print("Обрабатываем \(roadsToProcess.count) дорог для извлечения координат")
        
        // Получаем все координаты без прореживания
        var coordinates: [CLLocationCoordinate2D] = []
        for road in roadsToProcess {
            // Используем все точки дороги без прореживания
            coordinates.append(contentsOf: road.coordinates)
        }
        
        print("Собрано \(coordinates.count) координат из \(roadsToProcess.count) дорог")
        
        // Ограничиваем общее количество точек только для map matching, не для отображения
        if coordinates.count > 5000 {  // Увеличено с 2000 до 5000
            let strideValue = max(1, coordinates.count / 5000)
            var reducedCoordinates: [CLLocationCoordinate2D] = []
            for i in stride(from: 0, to: coordinates.count, by: strideValue) {
                reducedCoordinates.append(coordinates[i])
            }
            print("Финальное количество координат для map matching: \(reducedCoordinates.count)")
            return reducedCoordinates
        }
        
        print("Финальное количество координат: \(coordinates.count)")
        return coordinates
    }
    
    // Метод для фильтрации roadSegments по bbox
    func filterRoadSegmentsByBBox(segments: [RoadSegment], bbox: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)) -> [RoadSegment] {
        let filteredSegments = segments.filter { segment in
            let startInBBox = segment.start.latitude >= bbox.minLat && 
                               segment.start.latitude <= bbox.maxLat &&
                               segment.start.longitude >= bbox.minLon &&
                               segment.start.longitude <= bbox.maxLon
            
            let endInBBox = segment.end.latitude >= bbox.minLat && 
                             segment.end.latitude <= bbox.maxLat &&
                             segment.end.longitude >= bbox.minLon &&
                             segment.end.longitude <= bbox.maxLon
            
            // Также проверяем пересечение сегмента с границами bbox
            if !startInBBox && !endInBBox {
                // Проверка пересечения с границами
                return segmentIntersectsBBox(segment: segment, bbox: bbox)
            }
            
            return startInBBox || endInBBox
        }
        
        return filteredSegments
    }
    
    // Проверка пересечения сегмента с bbox
    func segmentIntersectsBBox(segment: RoadSegment, bbox: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)) -> Bool {
        // Создаем координаты углов bbox
        let topLeft = CLLocationCoordinate2D(latitude: bbox.maxLat, longitude: bbox.minLon)
        let topRight = CLLocationCoordinate2D(latitude: bbox.maxLat, longitude: bbox.maxLon)
        let bottomLeft = CLLocationCoordinate2D(latitude: bbox.minLat, longitude: bbox.minLon)
        let bottomRight = CLLocationCoordinate2D(latitude: bbox.minLat, longitude: bbox.maxLon)
        
        // Проверяем пересечение с каждой стороной bbox
        // Верхняя граница
        if segmentIntersectsLineSegment(a: segment.start, b: segment.end, c: topLeft, d: topRight) {
            return true
        }
        
        // Правая граница
        if segmentIntersectsLineSegment(a: segment.start, b: segment.end, c: topRight, d: bottomRight) {
            return true
        }
        
        // Нижняя граница
        if segmentIntersectsLineSegment(a: segment.start, b: segment.end, c: bottomLeft, d: bottomRight) {
            return true
        }
        
        // Левая граница
        if segmentIntersectsLineSegment(a: segment.start, b: segment.end, c: topLeft, d: bottomLeft) {
            return true
        }
        
        return false
    }
    
    // Проверка пересечения двух отрезков
    func segmentIntersectsLineSegment(a: CLLocationCoordinate2D, b: CLLocationCoordinate2D, 
                                     c: CLLocationCoordinate2D, d: CLLocationCoordinate2D) -> Bool {
        // Вычисляем ориентации
        func orientation(p: CLLocationCoordinate2D, q: CLLocationCoordinate2D, r: CLLocationCoordinate2D) -> Int {
            let val = (q.longitude - p.longitude) * (r.latitude - q.latitude) - 
                      (q.latitude - p.latitude) * (r.longitude - q.longitude)
            
            if abs(val) < 1e-9 { return 0 } // коллинеарны
            return val > 0 ? 1 : 2 // по часовой или против часовой стрелки
        }
        
        let o1 = orientation(p: a, q: b, r: c)
        let o2 = orientation(p: a, q: b, r: d)
        let o3 = orientation(p: c, q: d, r: a)
        let o4 = orientation(p: c, q: d, r: b)
        
        // Общий случай пересечения
        if o1 != o2 && o3 != o4 { return true }
        
        // Специальные случаи (коллинеарность)
        if o1 == 0 && onSegment(p: a, q: c, r: b) { return true }
        if o2 == 0 && onSegment(p: a, q: d, r: b) { return true }
        if o3 == 0 && onSegment(p: c, q: a, r: d) { return true }
        if o4 == 0 && onSegment(p: c, q: b, r: d) { return true }
        
        return false
    }
    
    // Проверка, лежит ли точка q на отрезке pr
    func onSegment(p: CLLocationCoordinate2D, q: CLLocationCoordinate2D, r: CLLocationCoordinate2D) -> Bool {
        return q.longitude <= max(p.longitude, r.longitude) && 
               q.longitude >= min(p.longitude, r.longitude) &&
               q.latitude <= max(p.latitude, r.latitude) && 
               q.latitude >= min(p.latitude, r.latitude)
    }
}
