//
//  RoadSegment.swift
//  TestTracks
//
//  Created by Dmitriy Obrazumov on 13/03/2025.
//


import CoreLocation

// Структура для дорожного сегмента (уже определена ранее)
struct RoadSegment: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    let id = UUID().uuidString
    let start: CLLocationCoordinate2D
    let end: CLLocationCoordinate2D
    
    // Информация о направлении дороги
    let isOneway: Bool
    let forwardDirection: Bool  // true если направление от start к end является разрешенным
    // Идентификатор дороги, сегменты из разных дорог не должны соединяться
    let roadId: String
    var direction: Double {
            let deltaX = end.longitude - start.longitude
            let deltaY = end.latitude - start.latitude
            return atan2(deltaX, deltaY) * 180.0 / .pi // Угол в градусах
        }
    
    // Инициализатор с дефолтными значениями для обратной совместимости
    init(start: CLLocationCoordinate2D, end: CLLocationCoordinate2D, 
         isOneway: Bool = true, forwardDirection: Bool = true, roadId: String = UUID().uuidString) {
        self.start = start
        self.end = end
        self.isOneway = isOneway
        self.forwardDirection = forwardDirection
        self.roadId = roadId
    }
}

// Класс для конвертации координат в сегменты
class CoordinateConverter {
    
    // Основная функция конвертации
    func convertToRoadSegments(coordinates: [CLLocationCoordinate2D]) -> [RoadSegment] {
        guard coordinates.count >= 2 else {
            return [] // Нужны минимум 2 точки для создания сегмента
        }
        
        var segments: [RoadSegment] = []
        // Создаем уникальный id для этой дороги
        let roadId = UUID().uuidString
        
        // Проходим по массиву координат и создаем сегменты
        for i in 0..<coordinates.count - 1 {
            let segment = RoadSegment(
                start: coordinates[i],
                end: coordinates[i + 1],
                roadId: roadId
            )
            segments.append(segment)
        }
        
        return segments
    }
    
    // Дополнительная функция с фильтрацией коротких сегментов
    func convertToRoadSegments(coordinates: [CLLocationCoordinate2D], 
                              minSegmentLength: Double = 1.0) -> [RoadSegment] {
        guard coordinates.count >= 2 else { return [] }
        
        var segments: [RoadSegment] = []
        // Создаем уникальный id для этой дороги
        let roadId = UUID().uuidString
        
        for i in 0..<coordinates.count - 1 {
            let startLocation = CLLocation(latitude: coordinates[i].latitude, 
                                         longitude: coordinates[i].longitude)
            let endLocation = CLLocation(latitude: coordinates[i + 1].latitude, 
                                       longitude: coordinates[i + 1].longitude)
            
            let distance = startLocation.distance(from: endLocation)
            
            // Добавляем сегмент только если он длиннее минимальной длины
            if distance >= minSegmentLength {
                let segment = RoadSegment(
                    start: coordinates[i],
                    end: coordinates[i + 1],
                    roadId: roadId
                )
                segments.append(segment)
            }
        }
        
        return segments
    }
    
    // Функция для упрощения трека перед конвертацией (алгоритм Дугласа-Пекера)
    func simplifyTrack(coordinates: [CLLocationCoordinate2D], 
                      tolerance: Double = 5.0) -> [CLLocationCoordinate2D] {
        guard coordinates.count > 2 else { return coordinates }
        
        var simplified: [CLLocationCoordinate2D] = []
        var stack: [(Int, Int)] = [(0, coordinates.count - 1)]
        
        while !stack.isEmpty {
            let (start, end) = stack.removeLast()
            
            if end - start <= 1 {
                if simplified.last != coordinates[start] {
                    simplified.append(coordinates[start])
                }
                continue
            }
            
            var maxDistance = 0.0
            var index = start
            
            let startLoc = CLLocation(latitude: coordinates[start].latitude, 
                                    longitude: coordinates[start].longitude)
            let endLoc = CLLocation(latitude: coordinates[end].latitude, 
                                  longitude: coordinates[end].longitude)
            
            for i in (start + 1)..<end {
                let currentLoc = CLLocation(latitude: coordinates[i].latitude, 
                                          longitude: coordinates[i].longitude)
                let distance = distanceFromPointToLine(point: coordinates[i],
                                                     start: coordinates[start],
                                                     end: coordinates[end])
                
                if distance > maxDistance {
                    maxDistance = distance
                    index = i
                }
            }
            
            if maxDistance > tolerance {
                stack.append((start, index))
                stack.append((index, end))
            } else {
                if simplified.last != coordinates[start] {
                    simplified.append(coordinates[start])
                }
            }
        }
        
        if simplified.last != coordinates.last {
            simplified.append(coordinates.last!)
        }
        
        return simplified
    }
    
    // Вспомогательная функция для вычисления расстояния до линии
    private func distanceFromPointToLine(point: CLLocationCoordinate2D,
                                       start: CLLocationCoordinate2D,
                                       end: CLLocationCoordinate2D) -> Double {
        let pointLoc = CLLocation(latitude: point.latitude, longitude: point.longitude)
        let startLoc = CLLocation(latitude: start.latitude, longitude: start.longitude)
        let endLoc = CLLocation(latitude: end.latitude, longitude: end.longitude)
        
        let lineLength = startLoc.distance(from: endLoc)
        if lineLength == 0 {
            return pointLoc.distance(from: startLoc)
        }
        
        var t = ((point.latitude - start.latitude) * (end.latitude - start.latitude) + 
                (point.longitude - start.longitude) * (end.longitude - start.longitude)) / lineLength
        t = max(0, min(1, t))
        
        let nearestLat = start.latitude + t * (end.latitude - start.latitude)
        let nearestLon = start.longitude + t * (end.longitude - start.longitude)
        let nearestPoint = CLLocation(latitude: nearestLat, longitude: nearestLon)
        
        return pointLoc.distance(from: nearestPoint)
    }
    
    // Метод для создания дорожных сегментов из GeoJSON данных
    func convertFromGeoJSON(feature: [String: Any]) -> [RoadSegment] {
        guard let geometry = feature["geometry"] as? [String: Any],
              let type = geometry["type"] as? String,
              type == "LineString",
              let coordinates = geometry["coordinates"] as? [[Double]] else {
            return []
        }
        
        // Извлечение свойств дороги
        let properties = feature["properties"] as? [String: Any]
        let isOneway = extractOnewayStatus(from: properties)
        let forwardDirection = extractDirection(from: properties)
        
        // Создаем уникальный идентификатор для этой дороги
        let roadId = UUID().uuidString
        
        var roadSegments: [RoadSegment] = []
        
        // Создаем сегменты из координат
        for i in 0..<(coordinates.count - 1) {
            guard coordinates[i].count >= 2, coordinates[i+1].count >= 2 else { continue }
            
            // GeoJSON использует формат [долгота, широта], нужно конвертировать
            let startCoord = CLLocationCoordinate2D(
                latitude: coordinates[i][1],
                longitude: coordinates[i][0]
            )
            
            let endCoord = CLLocationCoordinate2D(
                latitude: coordinates[i+1][1],
                longitude: coordinates[i+1][0]
            )
            
            let segment = RoadSegment(
                start: startCoord,
                end: endCoord,
                isOneway: isOneway,
                forwardDirection: forwardDirection,
                roadId: roadId
            )
            
            roadSegments.append(segment)
        }
        
        return roadSegments
    }
    
    // Метод для считывания статуса односторонней дороги
    private func extractOnewayStatus(from properties: [String: Any]?) -> Bool {
        guard let properties = properties else { return false }
        
        // Разные форматы GeoJSON могут использовать разные ключи
        if let oneway = properties["oneway"] as? Bool {
            return oneway
        }
        
        if let onewayStr = properties["oneway"] as? String,
           onewayStr.lowercased() == "yes" || onewayStr == "1" || onewayStr.lowercased() == "true" {
            return true
        }
        
        // OSM использует тэг для одностороннего движения
        if let highway = properties["highway"] as? String,
           let oneWay = properties["oneway"] as? String, 
           oneWay.lowercased() == "yes" {
            return true
        }
        
        return false
    }
    
    // Метод для считывания направления дороги
    private func extractDirection(from properties: [String: Any]?) -> Bool {
        guard let properties = properties else { return true }
        
        // По умолчанию направление - от начала к концу линии
        var forwardDirection = true
        
        // Проверяем различные форматы указания направления
        if let direction = properties["direction"] as? String {
            if direction.lowercased() == "backward" || direction == "-1" || direction.lowercased() == "reverse" {
                forwardDirection = false
            }
        }
        
        // Проверяем OSM-специфичный тэг
        if let oneWay = properties["oneway"] as? String, oneWay == "-1" {
            forwardDirection = false
        }
        
        return forwardDirection
    }
    
    // Загрузка дорожных сегментов из GeoJSON файла
    func loadRoadSegmentsFromGeoJSON(fileURL: URL) -> [RoadSegment] {
        var allRoadSegments: [RoadSegment] = []
        
        do {
            let data = try Data(contentsOf: fileURL)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let features = json["features"] as? [[String: Any]] else {
                print("Ошибка чтения формата GeoJSON: неверная структура")
                return []
            }
            
            for feature in features {
                // Каждый feature - это отдельная дорога, создаем для нее отдельные сегменты
                let segments = convertFromGeoJSON(feature: feature)
                if !segments.isEmpty {
                    // Добавляем сегменты этой дороги в общий массив
                    allRoadSegments.append(contentsOf: segments)
                }
            }
            
            print("Загружено \(allRoadSegments.count) дорожных сегментов из GeoJSON")
        } catch {
            print("Ошибка чтения GeoJSON файла: \(error.localizedDescription)")
        }
        
        return allRoadSegments
    }
}

extension CLLocationCoordinate2D: Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}
