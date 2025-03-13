//
//  RoadSegment.swift
//  TestTracks
//
//  Created by Dmitriy Obrazumov on 13/03/2025.
//


import CoreLocation

// Структура для дорожного сегмента (уже определена ранее)
struct RoadSegment {
    let start: CLLocationCoordinate2D
    let end: CLLocationCoordinate2D
}

// Класс для конвертации координат в сегменты
class CoordinateConverter {
    
    // Основная функция конвертации
    func convertToRoadSegments(coordinates: [CLLocationCoordinate2D]) -> [RoadSegment] {
        guard coordinates.count >= 2 else {
            return [] // Нужны минимум 2 точки для создания сегмента
        }
        
        var segments: [RoadSegment] = []
        
        // Проходим по массиву координат и создаем сегменты
        for i in 0..<coordinates.count - 1 {
            let segment = RoadSegment(
                start: coordinates[i],
                end: coordinates[i + 1]
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
                    end: coordinates[i + 1]
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
}

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}
