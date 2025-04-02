//
//  MapMatcher.swift
//  TestTracks
//
//  Created by Dmitriy Obrazumov on 13/03/2025.
//
import Foundation
import CoreLocation

// Структура для точки трека
struct TrackPoint {
    let coordinate: CLLocationCoordinate2D
    let timestamp: Date
}

class MapMatcher {
    
    // Функция вычисления расстояния между точкой и линией (в метрах)
    private func distanceFromPoint(_ point: CLLocationCoordinate2D,
                                 toLineSegment start: CLLocationCoordinate2D,
                                 end: CLLocationCoordinate2D) -> Double {
        // Создаем объекты CLLocation для точных геодезических вычислений
        let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
        let startLocation = CLLocation(latitude: start.latitude, longitude: start.longitude)
        let endLocation = CLLocation(latitude: end.latitude, longitude: end.longitude)
        
        // Вычисляем длину отрезка
        let lineLength = startLocation.distance(from: endLocation)
        
        // Если отрезок вырожден в точку, возвращаем расстояние до этой точки
        if lineLength < 0.1 { // Порог 10 см для исключения ошибок округления
            return location.distance(from: startLocation)
        }
        
        // Вычисляем параметр t - положение проекции точки на прямую
        // t = 0 соответствует проекции в начальной точке отрезка
        // t = 1 соответствует проекции в конечной точке отрезка
        // t = 0.5 соответствует проекции посередине отрезка
        var t = ((point.latitude - start.latitude) * (end.latitude - start.latitude) +
                (point.longitude - start.longitude) * (end.longitude - start.longitude)) / 
                ((end.latitude - start.latitude) * (end.latitude - start.latitude) + 
                 (end.longitude - start.longitude) * (end.longitude - start.longitude))
        
        // Ограничиваем t значениями от 0 до 1, чтобы проекция была строго на отрезке
        t = max(0, min(1, t))
        
        // Вычисляем координаты проекции точки на отрезок
        let nearestLat = start.latitude + t * (end.latitude - start.latitude)
        let nearestLon = start.longitude + t * (end.longitude - start.longitude)
        
        // Создаем объект местоположения для точки проекции
        let nearestPoint = CLLocation(latitude: nearestLat, longitude: nearestLon)
        
        // Возвращаем расстояние от исходной точки до ее проекции на отрезок
        return location.distance(from: nearestPoint)
    }
    
    // Находит ближайшую точку на отрезке дороги
    private func findNearestPointOnSegment(point: TrackPoint, segment: [CLLocationCoordinate2D], maxDistance: Double) -> (CLLocationCoordinate2D, Double)? {
        var minDistance = Double.infinity
        var nearestPoint: CLLocationCoordinate2D? = nil
        var bestSegmentIndex: Int? = nil
        
        // Проверяем каждый отрезок дороги
        for i in 0..<(segment.count - 1) {
            let start = segment[i]
            let end = segment[i + 1]
            
            // Вычисляем длину отрезка
            let segmentLength = calculateDistance(coord1: start, coord2: end)
            if segmentLength < 0.1 { // Пропускаем слишком короткие отрезки
                continue
            }
            
            // Вычисляем расстояние от точки до отрезка
            let distance = distanceFromPoint(point.coordinate, toLineSegment: start, end: end)
            if distance > maxDistance {
                continue
            }
            
            // Вычисляем вектор отрезка
            let dx = end.longitude - start.longitude
            let dy = end.latitude - start.latitude
            
            // Вычисляем вектор от начала отрезка к точке
            let px = point.coordinate.longitude - start.longitude
            let py = point.coordinate.latitude - start.latitude
            
            // Вычисляем проекцию точки на отрезок
            let t = (px * dx + py * dy) / (dx * dx + dy * dy)
            
            // Ограничиваем проекцию отрезком
            let clampedT = max(0, min(1, t))
            
            // Вычисляем координаты проекции
            let projectedX = start.longitude + clampedT * dx
            let projectedY = start.latitude + clampedT * dy
            
            let projectedPoint = CLLocationCoordinate2D(latitude: projectedY, longitude: projectedX)
            
            // Проверяем, что точка действительно лежит на отрезке
            let distToStart = calculateDistance(coord1: projectedPoint, coord2: start)
            let distToEnd = calculateDistance(coord1: projectedPoint, coord2: end)
            
            // Точка должна лежать на отрезке (с учетом погрешности вычислений)
            if distToStart + distToEnd <= segmentLength * 1.001 {
                if distance < minDistance {
                    minDistance = distance
                    nearestPoint = projectedPoint
                    bestSegmentIndex = i
                }
            }
        }
        
        if let nearestPoint = nearestPoint, let segmentIndex = bestSegmentIndex {
            // Если точка ближе к концу отрезка, возвращаем конец отрезка
            let distToEnd = calculateDistance(coord1: nearestPoint, coord2: segment[segmentIndex + 1])
            if distToEnd < 5.0 { // Если ближе 5 метров к концу отрезка
                return (segment[segmentIndex + 1], minDistance)
            }
            
            // Если точка ближе к началу отрезка, возвращаем начало отрезка
            let distToStart = calculateDistance(coord1: nearestPoint, coord2: segment[segmentIndex])
            if distToStart < 5.0 { // Если ближе 5 метров к началу отрезка
                return (segment[segmentIndex], minDistance)
            }
            
            // Иначе возвращаем проекцию
            return (nearestPoint, minDistance)
        }
        
        return nil
    }
    
    // Проверяет, находится ли точка на отрезке
    private func isPointOnSegment(
        point: CLLocationCoordinate2D,
        segmentStart: CLLocationCoordinate2D,
        segmentEnd: CLLocationCoordinate2D
    ) -> Bool {
        // Вычисляем длины отрезков
        let segmentLength = calculateDistance(coord1: segmentStart, coord2: segmentEnd)
        let distToStart = calculateDistance(coord1: point, coord2: segmentStart)
        let distToEnd = calculateDistance(coord1: point, coord2: segmentEnd)
        
        // Точка лежит на отрезке, если сумма расстояний до концов равна длине отрезка
        // (с учетом погрешности вычислений)
        return abs(distToStart + distToEnd - segmentLength) <= 0.1
    }
    
    // Структура для хранения накопленной ошибки
    private struct AccumulatedError {
        var latitude: Double = 0
        var longitude: Double = 0
        var count: Int = 0
        
        var average: (latitude: Double, longitude: Double) {
            guard count > 0 else { return (0, 0) }
            return (latitude / Double(count), longitude / Double(count))
        }
        
        mutating func add(_ error: (latitude: Double, longitude: Double)) {
            latitude += error.latitude
            longitude += error.longitude
            count += 1
        }
        
        mutating func apply(to point: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
            let avg = average
            return CLLocationCoordinate2D(
                latitude: point.latitude + avg.latitude,
                longitude: point.longitude + avg.longitude
            )
        }
    }
    
    // Основной алгоритм привязки с учетом направления движения и улучшенной привязкой на поворотах
    func matchTrackWithErrorCorrection(
        gpsTrack: [TrackPoint],
        roadSegments: [RoadSegment],
        maxDistance: Double = 30.0,
        forceSnapToRoad: Bool = true,
        maxForceSnapDistance: Double = 50.0,
        removeDuplicates: Bool = true,
        fillGaps: Bool = true
    ) -> [CLLocationCoordinate2D] {
        guard !gpsTrack.isEmpty else { return [] }
        guard !roadSegments.isEmpty else {
            print("Нет дорожных сегментов для сопоставления")
            return gpsTrack.map { $0.coordinate }
        }
        
        print("Начинаем новый алгоритм сопоставления трека с накоплением ошибки")
        let startTime = Date()
        
        // Создаем пространственный индекс для быстрого поиска
        let gridSize: Double = 0.001 // примерно 100 метров
        var spatialIndex: [String: [Int]] = [:]
        
        for (index, segment) in roadSegments.enumerated() {
            let minLat = min(segment.start.latitude, segment.end.latitude)
            let maxLat = max(segment.start.latitude, segment.end.latitude)
            let minLon = min(segment.start.longitude, segment.end.longitude)
            let maxLon = max(segment.start.longitude, segment.end.longitude)
            
            let minLatGrid = floor(minLat / gridSize) * gridSize
            let maxLatGrid = ceil(maxLat / gridSize) * gridSize
            let minLonGrid = floor(minLon / gridSize) * gridSize
            let maxLonGrid = ceil(maxLon / gridSize) * gridSize
            
            for latGrid in stride(from: minLatGrid, through: maxLatGrid, by: gridSize) {
                for lonGrid in stride(from: minLonGrid, through: maxLonGrid, by: gridSize) {
                    let key = "\(latGrid):\(lonGrid)"
                    if spatialIndex[key] == nil {
                        spatialIndex[key] = []
                    }
                    spatialIndex[key]?.append(index)
                }
            }
        }
        
        var matchedPoints: [CLLocationCoordinate2D] = []
        var lastMatchedSegmentIndex: Int? = nil
        var currentRoadSegment: [CLLocationCoordinate2D]? = nil
        var currentSegmentIndex: Int = 0
        var accumulatedError = AccumulatedError()
        var errorWindow: [(latitude: Double, longitude: Double)] = []
        let errorWindowSize = 10 // Размер окна для скользящего среднего ошибки
        
        // Обработка каждой точки трека
        for i in 0..<gpsTrack.count {
            var point = gpsTrack[i].coordinate
            
            // Применяем накопленную ошибку к текущей точке
            point = accumulatedError.apply(to: point)
            
            // Определяем направление движения
            var direction: (Double, Double) = (0, 0)
            if i > 0 {
                let prevPoint = matchedPoints.isEmpty ? gpsTrack[i-1].coordinate : matchedPoints.last!
                direction = getDirectionVector(from: prevPoint, to: point)
            }
            
            // Получаем ближайшие сегменты через пространственный индекс
            let latGrid = floor(point.latitude / gridSize) * gridSize
            let lonGrid = floor(point.longitude / gridSize) * gridSize
            var nearbySegmentIndices = Set<Int>()
            
            // Расширяем поиск на поворотах
            let searchRadius = i > 0 && i < gpsTrack.count - 1 ? 2 : 3
            for dLat in -searchRadius...searchRadius {
                for dLon in -searchRadius...searchRadius {
                    let key = "\(latGrid + Double(dLat) * gridSize):\(lonGrid + Double(dLon) * gridSize)"
                    if let segments = spatialIndex[key] {
                        nearbySegmentIndices.formUnion(segments)
                    }
                }
            }
            
            // Если у нас есть текущий сегмент дороги, проверяем его первым
            if let currentSegment = currentRoadSegment {
                // Проверяем, можем ли мы продолжить движение по текущему сегменту
                if currentSegmentIndex < currentSegment.count - 1 {
                    let nextPoint = currentSegment[currentSegmentIndex + 1]
                    let distance = calculateDistance(coord1: point, coord2: nextPoint)
                    
                    if distance <= maxDistance {
                        // Продолжаем движение по текущему сегменту
                        matchedPoints.append(nextPoint)
                        currentSegmentIndex += 1
                        continue
                    }
                }
            }
            
            // Ищем новый сегмент дороги
            var bestSegmentIndex: Int? = nil
            var bestDistance = maxDistance
            var bestProjectedPoint = point
            var bestSegment: [CLLocationCoordinate2D]? = nil
            var bestSegmentStartIndex = 0
            
            for segmentIndex in nearbySegmentIndices {
                let segment = roadSegments[segmentIndex]
                let segmentPoints = [segment.start, segment.end]
                
                // Проверяем расстояние до сегмента
                let distance = distanceFromPoint(point, toLineSegment: segment.start, end: segment.end)
                if distance > maxDistance {
                    continue
                }
                
                // Находим точку проекции
                guard let projectedPoint = findNearestPointOnSegment(point: gpsTrack[i], segment: segmentPoints, maxDistance: maxDistance) else { continue }
                
                // Проверяем направление движения
                let segmentDirection = getSegmentDirection(segment)
                let directionMatch = dotProduct(direction, segmentDirection)
                
                // Проверяем разрешенное направление для односторонних дорог
                if segment.isOneway {
                    let isForwardDirection = directionMatch > 0
                    if segment.forwardDirection != isForwardDirection {
                        continue
                    }
                }
                
                if distance < bestDistance && directionMatch > 0.5 {
                    bestSegmentIndex = segmentIndex
                    bestDistance = distance
                    bestProjectedPoint = projectedPoint.0
                    bestSegment = segmentPoints
                    bestSegmentStartIndex = 0
                }
            }
            
            // Если нашли подходящий сегмент
            if let segmentIndex = bestSegmentIndex, let segment = bestSegment {
                matchedPoints.append(bestProjectedPoint)
                currentRoadSegment = segment
                currentSegmentIndex = bestSegmentStartIndex
                lastMatchedSegmentIndex = segmentIndex
                
                // Вычисляем и накапливаем ошибку
                let error = (
                    latitude: bestProjectedPoint.latitude - gpsTrack[i].coordinate.latitude,
                    longitude: bestProjectedPoint.longitude - gpsTrack[i].coordinate.longitude
                )
                
                // Добавляем ошибку в окно
                errorWindow.append(error)
                if errorWindow.count > errorWindowSize {
                    errorWindow.removeFirst()
                }
                
                // Вычисляем среднюю ошибку по окну
                let avgError = errorWindow.reduce((0.0, 0.0)) { result, error in
                    (result.0 + error.latitude, result.1 + error.longitude)
                }
                let windowCount = Double(errorWindow.count)
                let smoothedError = (
                    latitude: avgError.0 / windowCount,
                    longitude: avgError.1 / windowCount
                )
                
                // Обновляем накопленную ошибку
                accumulatedError.add(smoothedError)
                
                // Ограничиваем максимальную накопленную ошибку
                let maxError = 10.0 // Максимальная ошибка в метрах
                let currentError = sqrt(
                    accumulatedError.average.latitude * accumulatedError.average.latitude +
                    accumulatedError.average.longitude * accumulatedError.average.longitude
                )
                if currentError > maxError {
                    let scale = maxError / currentError
                    accumulatedError.latitude *= scale
                    accumulatedError.longitude *= scale
                }
            } else {
                matchedPoints.append(point)
                currentRoadSegment = nil
                currentSegmentIndex = 0
                lastMatchedSegmentIndex = nil
            }
        }
        
        // Постобработка
        var result = matchedPoints
        
        if removeDuplicates {
            result = removeDuplicatePoints(result)
        }
        
        if fillGaps {
            result = fillTrackGaps(result)
        }
        
        let endTime = Date()
        let totalTime = endTime.timeIntervalSince(startTime)
        print("Сопоставление завершено за \(String(format: "%.2f", totalTime)) секунд")
        print("Накопленная ошибка: \(String(format: "%.2f", accumulatedError.average.latitude)), \(String(format: "%.2f", accumulatedError.average.longitude))")
        
        return result
    }
    
    func analyzeTurns(in track: [TrackPoint], sampleDistance: Int = 3) -> (turnRatio: Double, turnIndices: [Int]) {
        guard track.count > 2 * sampleDistance else { 
            return (0.0, []) 
        }
        
        var directionChanges = 0
        var turnIndices: [Int] = []
        var sharpTurnIndices: [Int] = [] // Для отслеживания особенно острых поворотов
        
        // Анализируем изменения направления на протяжении всего трека
        for i in sampleDistance..<track.count-sampleDistance {
            let p1 = track[i - sampleDistance].coordinate
            let p2 = track[i].coordinate
            let p3 = track[i + sampleDistance].coordinate
            
            let dir1 = getDirectionVector(from: p1, to: p2)
            let dir2 = getDirectionVector(from: p2, to: p3)
            
            // Вычисляем косинус угла между векторами направления
            let dotProduct = dir1.0 * dir2.0 + dir1.1 * dir2.1
            
            // Если косинус меньше 0.7, это поворот примерно от 45 градусов и больше
            if dotProduct < 0.7 {
                directionChanges += 1
                turnIndices.append(i)
                
                // Отслеживаем особенно резкие повороты для дополнительного анализа
                if dotProduct < 0 {
                    // Поворот более 90 градусов
                    sharpTurnIndices.append(i)
                    
                    // Добавляем дополнительные точки до и после резкого поворота
                    // для более точного сопоставления
                    if !turnIndices.contains(i-1) && i > 0 {
                        turnIndices.append(i-1)
                    }
                    if !turnIndices.contains(i+1) && i < track.count-1 {
                        turnIndices.append(i+1)
                    }
                    
                    // Печатаем информацию о резком повороте для отладки
                    print("⚠️ Обнаружен резкий поворот на индексе \(i) (косинус: \(String(format: "%.2f", dotProduct)))")
                }
            }
        }
        
        // Вычисляем соотношение поворотов
        let turnRatio = Double(directionChanges) / Double(track.count - 2 * sampleDistance)
        
        // Выводим детальную информацию о поворотах
        print("🔄 Анализ трека: общее число поворотов: \(directionChanges), резких поворотов: \(sharpTurnIndices.count)")
        print("🔄 Соотношение поворотов к длине: \(String(format: "%.3f", turnRatio))")
        
        // Если слишком много поворотов, выводим предупреждение
        if turnRatio > 0.4 {
            print("⚠️ Внимание! Очень извилистый трек (turnRatio=\(String(format: "%.2f", turnRatio)))")
        }
        
        return (turnRatio, turnIndices)
    }
}

// MARK: - Track Analysis Extensions
extension MapMatcher {
    // Находит сегменты, соединенные с указанным
    private func getConnectedSegments(segmentIndex: Int, roadSegments: [RoadSegment], maxDistance: Double = 50.0) -> [Int] {
        let segment = roadSegments[segmentIndex]
        var connectedIndices: [Int] = []
        
        // Проверяем все остальные сегменты
        for (index, otherSegment) in roadSegments.enumerated() {
            if index == segmentIndex {
                continue // Пропускаем сам сегмент
            }
            
            // Проверяем расстояния между концами сегментов
            let startToStart = calculateDistance(coord1: segment.start, coord2: otherSegment.start)
            let startToEnd = calculateDistance(coord1: segment.start, coord2: otherSegment.end)
            let endToStart = calculateDistance(coord1: segment.end, coord2: otherSegment.start)
            let endToEnd = calculateDistance(coord1: segment.end, coord2: otherSegment.end)
            
            // Если хотя бы одно расстояние меньше максимального, сегменты связаны
            if min(min(startToStart, startToEnd), min(endToStart, endToEnd)) <= maxDistance {
                connectedIndices.append(index)
            }
        }
        
        return connectedIndices
    }
    
    // Проверяет, разрешено ли движение в текущем направлении для данного сегмента
    private func checkDirectionAllowed(_ segment: RoadSegment, _ directionMatch: Double) -> Bool {
        // Если дорога не односторонняя, движение разрешено в обоих направлениях
        if !segment.isOneway {
            return true
        }
        
        // Определяем, двигаемся ли мы в направлении сегмента или против него
        let movingForward = directionMatch > 0
        
        // Для односторонней дороги:
        // - Если forwardDirection = true, разрешено движение от start к end (movingForward = true)
        // - Если forwardDirection = false, разрешено движение от end к start (movingForward = false)
        return segment.forwardDirection == movingForward
    }
    
    // Вычисляет направление сегмента
    private func getSegmentDirection(_ segment: RoadSegment) -> (Double, Double) {
        let deltaLat = segment.end.latitude - segment.start.latitude
        let deltaLon = segment.end.longitude - segment.start.longitude
        
        // Нормализуем направление
        let length = sqrt(deltaLat * deltaLat + deltaLon * deltaLon)
        if length > 0 {
            return (deltaLat / length, deltaLon / length)
        }
        
        return (0, 0)
    }
    
    // Вычисляет скалярное произведение двух векторов (косинус угла между ними)
    private func dotProduct(_ v1: (Double, Double), 
                           _ v2: (Double, Double)) -> Double {
        return v1.0 * v2.0 + v1.1 * v2.1
    }
    
    // Вычисляет расстояние между двумя координатами
    private func calculateDistance(coord1: CLLocationCoordinate2D, coord2: CLLocationCoordinate2D) -> Double {
        let location1 = CLLocation(latitude: coord1.latitude, longitude: coord1.longitude)
        let location2 = CLLocation(latitude: coord2.latitude, longitude: coord2.longitude)
        return location1.distance(from: location2)
    }
    
    // Функция сглаживания трека
    func smoothTrack(_ track: [CLLocationCoordinate2D], windowSize: Int = 5) -> [CLLocationCoordinate2D] {
        guard track.count >= windowSize else { return track }
        
        var smoothedTrack: [CLLocationCoordinate2D] = []
        
        for i in 0..<track.count {
            let start = max(0, i - windowSize/2)
            let end = min(track.count - 1, i + windowSize/2)
            
            var latSum: Double = 0
            var lonSum: Double = 0
            let count = Double(end - start + 1)
            
            for j in start...end {
                latSum += track[j].latitude
                lonSum += track[j].longitude
            }
            
            let smoothedPoint = CLLocationCoordinate2D(
                latitude: latSum / count,
                longitude: lonSum / count
            )
            smoothedTrack.append(smoothedPoint)
        }
        
        return smoothedTrack
    }
    
    // Удаляет дублирующиеся последовательные точки из трека
    private func removeDuplicatePoints(_ track: [CLLocationCoordinate2D], 
                                      minDistanceThreshold: Double = 0.1) -> [CLLocationCoordinate2D] {
        guard track.count > 1 else { return track }
        
        var result: [CLLocationCoordinate2D] = [track[0]]
        
        for i in 1..<track.count {
            let prevPoint = result.last!
            let currentPoint = track[i]
            
            // Вычисляем расстояние между точками
            let distance = calculateDistance(coord1: prevPoint, coord2: currentPoint)
            
            // Добавляем точку только если она достаточно отличается от предыдущей
            if distance > minDistanceThreshold {
                result.append(currentPoint)
            }
        }
        
        return result
    }
    
    // Заполняет пропуски в треке, добавляя промежуточные точки
    private func fillTrackGaps(_ track: [CLLocationCoordinate2D], 
                             maxGapDistance: Double = 50.0,
                             maxPointsToAdd: Int = 5) -> [CLLocationCoordinate2D] {
        guard track.count > 1 else { return track }
        
        var filledTrack: [CLLocationCoordinate2D] = []
        var gapsFound = 0
        var pointsAdded = 0
        
        // Добавляем первую точку
        filledTrack.append(track[0])
        
        for i in 1..<track.count {
            let prevPoint = track[i-1]
            let currentPoint = track[i]
            
            // Вычисляем расстояние между точками
            let distance = calculateDistance(coord1: prevPoint, coord2: currentPoint)
            
            // Если расстояние больше порога, добавляем промежуточные точки
            if distance > maxGapDistance {
                gapsFound += 1
                
                // Вычисляем направление движения между точками
                let direction = getDirectionVector(from: prevPoint, to: currentPoint)
                
                // Определяем количество точек для добавления (не больше maxPointsToAdd)
                // и адаптивно зависит от расстояния
                let numPointsToAdd = min(maxPointsToAdd, max(1, Int(distance / maxGapDistance)))
                
                // Добавляем промежуточные точки, равномерно распределенные по прямой
                for j in 1...numPointsToAdd {
                    let fraction = Double(j) / Double(numPointsToAdd + 1)
                    
                    // Интерполяция между предыдущей и текущей точками
                    let interpolatedLat = prevPoint.latitude + fraction * (currentPoint.latitude - prevPoint.latitude)
                    let interpolatedLon = prevPoint.longitude + fraction * (currentPoint.longitude - prevPoint.longitude)
                    
                    let interpolatedPoint = CLLocationCoordinate2D(
                        latitude: interpolatedLat,
                        longitude: interpolatedLon
                    )
                    
                    filledTrack.append(interpolatedPoint)
                    pointsAdded += 1
                }
            }
            
            // Добавляем текущую точку
            filledTrack.append(currentPoint)
        }
        
        if gapsFound > 0 {
            print("Найдено \(gapsFound) пропусков в треке, добавлено \(pointsAdded) промежуточных точек")
        }
        
        return filledTrack
    }
    
    // Вычисляет вектор направления между двумя точками
    private func getDirectionVector(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> (Double, Double) {
        let deltaLat = end.latitude - start.latitude
        let deltaLon = end.longitude - start.longitude
        
        // Нормализуем вектор
        let length = sqrt(deltaLat * deltaLat + deltaLon * deltaLon)
        if length > 0 {
            return (deltaLat / length, deltaLon / length)
        }
        
        return (0, 0)
    }
    
    // Определяет оптимальное расстояние для предварительного анализа точек
    private func determineLookAheadDistance(for track: [TrackPoint]) -> Int {
        // Оценка сложности трека
        let (turnRatio, _) = analyzeTurns(in: track)
        
        // Вычисляем среднее расстояние между точками
        var totalDistance: Double = 0
        for i in 1..<track.count {
            let previousPoint = track[i-1].coordinate
            let currentPoint = track[i].coordinate
            totalDistance += calculateDistance(coord1: previousPoint, coord2: currentPoint)
        }
        let averageDistance = track.count > 1 ? totalDistance / Double(track.count - 1) : 0
        
        // Адаптивное определение расстояния в зависимости от сложности трека
        // и среднего расстояния между точками
        if turnRatio > 0.3 {
            // Очень извилистый трек - смотрим меньше вперёд
            print("Извилистый трек (turnRatio=\(turnRatio)), используем малое lookAheadDistance")
            return max(2, min(5, Int(10.0 / max(1, averageDistance))))
        } else if turnRatio > 0.15 {
            // Средне извилистый трек
            return max(3, min(8, Int(20.0 / max(1, averageDistance))))
        } else {
            // Относительно прямой трек - можем смотреть дальше вперёд
            return max(5, min(15, Int(30.0 / max(1, averageDistance))))
        }
    }
    
    // Оценивает сложность сегмента трека
    func evaluateSegmentComplexity(for trackSegment: [TrackPoint]) -> Double {
        guard trackSegment.count > 2 else { return 0.0 }
        
        let (turnRatio, turnIndices) = analyzeTurns(in: trackSegment)
        
        // Вычисляем общее расстояние сегмента
        var totalDistance: Double = 0
        for i in 1..<trackSegment.count {
            let previousPoint = trackSegment[i-1].coordinate
            let currentPoint = trackSegment[i].coordinate
            totalDistance += calculateDistance(coord1: previousPoint, coord2: currentPoint)
        }
        
        // Вычисляем плотность точек
        let pointDensity = totalDistance > 0 ? Double(trackSegment.count) / totalDistance : 0
        
        // Комбинируем метрики сложности
        let complexity = turnRatio * 0.7 + min(1.0, pointDensity * 50) * 0.3
        
        return complexity
    }
    
    // Находит лучший сегмент для точки с учетом направления и других критериев
    private func findBestSegment(
        point: CLLocationCoordinate2D,
        direction: (Double, Double),
        lookAheadDirection: (Double, Double),
        roadSegments: [RoadSegment],
        nearbySegmentIndices: Set<Int>,
        lastMatchedSegmentIndex: Int?,
        connectedToLastSegment: [Int],
        maxDistance: Double
    ) -> (segmentIndex: Int?, distance: Double, projectedPoint: CLLocationCoordinate2D) {
        
        var bestScore: Double = -Double.infinity
        var bestSegmentIndex: Int = -1
        var bestDistance: Double = Double.infinity
        var bestProjectedPoint: CLLocationCoordinate2D = point
        
        // Проверяем все ближайшие сегменты
        for segmentIndex in nearbySegmentIndices {
            let segment = roadSegments[segmentIndex]
            
            // Вычисляем расстояние от точки до сегмента
            let distance = distanceFromPoint(point, 
                                           toLineSegment: segment.start, 
                                           end: segment.end)
            
            // Если расстояние слишком большое, пропускаем сегмент
            if distance > maxDistance {
                continue
            }
            
            // Находим точку проекции на сегмент
            guard let projectedPoint = findNearestPointOnSegment(point: TrackPoint(coordinate: point, timestamp: Date()), segment: [segment.start, segment.end], maxDistance: maxDistance) else { continue }
            
            // Вычисляем направление сегмента
            let segmentDirection = getSegmentDirection(segment)
            
            // Вычисляем соответствие направления сегмента и направления движения
            // (косинус угла между векторами)
            let directionMatch = dotProduct(direction, segmentDirection)
            
            // Проверяем, разрешено ли движение в данном направлении
            let directionAllowed = checkDirectionAllowed(segment, directionMatch)
            
            // Если направление запрещено, пропускаем сегмент (для односторонних дорог)
            if !directionAllowed && segment.isOneway {
                continue
            }
            
            // Учитываем также будущее направление (для улучшения прохождения поворотов)
            let futureDirectionMatch = dotProduct(lookAheadDirection, segmentDirection)
            
            // Вычисляем базовый вес для сегмента
            var score = 1.0 / (distance + 1.0) // Чем меньше расстояние, тем выше вес
            
            // Усиливаем вес для близких сегментов
            if distance < maxDistance * 0.5 {
                score *= 2.0
            }
            
            // Добавляем бонус за совпадение направления (усилен)
            score += max(0, directionMatch) * 3.0
            
            // Добавляем бонус за совпадение будущего направления (усилен)
            score += max(0, futureDirectionMatch) * 2.0
            
            // Добавляем бонус для связанных сегментов (непрерывность дороги)
            if let lastSegmentIndex = lastMatchedSegmentIndex {
                // Бонус для сегмента, который совпадает с предыдущим 
                // (продолжение того же участка дороги)
                if segmentIndex == lastSegmentIndex {
                    score += 5.0 // Увеличен бонус
                }
                // Бонус для сегментов, связанных с предыдущим (переход на соседний участок)
                else if connectedToLastSegment.contains(segmentIndex) {
                    score += 3.0 // Увеличен бонус
                }
            }
            
            // Если у нас есть лучший результат, обновляем его
            if score > bestScore {
                bestScore = score
                bestSegmentIndex = segmentIndex
                bestDistance = distance
                bestProjectedPoint = projectedPoint.0
            }
        }
        
        return (bestSegmentIndex >= 0 ? bestSegmentIndex : nil, bestDistance, bestProjectedPoint)
    }
}

