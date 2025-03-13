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
        let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
        let startLocation = CLLocation(latitude: start.latitude, longitude: start.longitude)
        let endLocation = CLLocation(latitude: end.latitude, longitude: end.longitude)
        
        let lineLength = startLocation.distance(from: endLocation)
        if lineLength == 0 {
            return location.distance(from: startLocation)
        }
        
        var t = ((point.latitude - start.latitude) * (end.latitude - start.latitude) +
                (point.longitude - start.longitude) * (end.longitude - start.longitude)) / lineLength
        t = max(0, min(1, t))
        
        let nearestLat = start.latitude + t * (end.latitude - start.latitude)
        let nearestLon = start.longitude + t * (end.longitude - start.longitude)
        let nearestPoint = CLLocation(latitude: nearestLat, longitude: nearestLon)
        
        return location.distance(from: nearestPoint)
    }
    
    // Функция для нахождения ближайшей точки на сегменте
    private func findNearestPointOnSegment(_ point: CLLocationCoordinate2D,
                                          start: CLLocationCoordinate2D,
                                          end: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let lineLength = CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
        
        if lineLength == 0 {
            return start
        }
        
        var t = ((point.latitude - start.latitude) * (end.latitude - start.latitude) +
                (point.longitude - start.longitude) * (end.longitude - start.longitude)) / lineLength
        t = max(0, min(1, t))
        
        let matchedLat = start.latitude + t * (end.latitude - start.latitude)
        let matchedLon = start.longitude + t * (end.longitude - start.longitude)
        return CLLocationCoordinate2D(latitude: matchedLat, longitude: matchedLon)
    }
    
    // Основной алгоритм привязки с коррекцией погрешности
    func matchTrackWithErrorCorrection(gpsTrack: [TrackPoint], roadSegments: [RoadSegment], maxDistance: Double = 50.0) -> [CLLocationCoordinate2D] {
        var matchedTrack: [CLLocationCoordinate2D] = []
        var accumulatedOffset: (deltaLat: Double, deltaLon: Double) = (0.0, 0.0)
        
        for gpsPoint in gpsTrack {
            // Применяем накопленное смещение к текущей точке
            let correctedCoordinate = CLLocationCoordinate2D(
                latitude: gpsPoint.coordinate.latitude + accumulatedOffset.deltaLat,
                longitude: gpsPoint.coordinate.longitude + accumulatedOffset.deltaLon
            )
            
            var closestDistance = Double.infinity
            var closestPoint: CLLocationCoordinate2D?
            
            // Ищем ближайший дорожный сегмент
            for segment in roadSegments {
                let distance = distanceFromPoint(correctedCoordinate,
                                              toLineSegment: segment.start,
                                              end: segment.end)
                
                if distance < closestDistance && distance < maxDistance {
                    closestDistance = distance
                    closestPoint = findNearestPointOnSegment(correctedCoordinate,
                                                           start: segment.start,
                                                           end: segment.end)
                }
            }
            
            // Если нашли ближайшую точку на дороге
            if let matchedPoint = closestPoint {
                // Вычисляем погрешность (смещение) между скорректированной точкой и точкой на дороге
                let errorLat = matchedPoint.latitude - correctedCoordinate.latitude
                let errorLon = matchedPoint.longitude - correctedCoordinate.longitude
                
                // Обновляем накопленное смещение
                accumulatedOffset.deltaLat += errorLat
                accumulatedOffset.deltaLon += errorLon
                
                // Добавляем привязанную точку в трек
                matchedTrack.append(matchedPoint)
            } else {
                // Если точка слишком далеко от дороги, используем скорректированную точку
                matchedTrack.append(correctedCoordinate)
            }
        }
        
        return matchedTrack
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
}
