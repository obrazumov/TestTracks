//
//  MyMapMatcher.swift
//  TestTracks
//
//  Created by Dmitrii on 03.04.2025.
//

import Foundation
import MapKit

final class MyMapMatcher {
    
}

struct TestCandidat {
    let trackPoint: TrackPoint
    let newPoint: CLLocationCoordinate2D
    let candidates: [RoadSegment]
    var color: UIColor = {
        return UIColor(
            red: CGFloat.random(in: 0...1),
            green: CGFloat.random(in: 0...1),
            blue: CGFloat.random(in: 0...1),
            alpha: 1.0
        )
    }()
}

extension MyMapMatcher: MapMatching {
    func matchTrack(gpsTrack: [TrackPoint], roadSegments: [RoadSegment], index: Int) async -> [CLLocationCoordinate2D] {
        return await correctTrack(observations: gpsTrack.prefix(index).map { $0 }, roadSegments: roadSegments).map({ $0.coordinate })
    }
    
    func matchTrack(gpsTrack: [TrackPoint], roadSegments: [RoadSegment], maxDistance: Double, forceSnapToRoad: Bool, maxForceSnapDistance: Double, removeDuplicates: Bool, fillGaps: Bool, simplifyTrack: Bool) -> [CLLocationCoordinate2D] {
        return []//correctTrack(observations: gpsTrack, roadSegments: roadSegments).map({ $0.coordinate })
    }
    func matchTrackCandidat(gpsTrack: [TrackPoint], roadSegments: [RoadSegment], index: Int) async -> TestCandidat? {
        let point = gpsTrack[index].coordinate
        let previousLocation = index > 0 ? gpsTrack[index - 1].coordinate : nil
        let candidates = findClosestRoadSegments(for: point, previousLocation: previousLocation, roadSegments: roadSegments)
        
                
        // Для каждой наблюдаемой точки выбираем ближайшие дороги
        var stateProbabilities: [RoadSegment: Double] = [:]
        var newStateProbabilities: [RoadSegment: Double] = [:]
        
        for candidate in candidates {
            let obsProb = observationProbability(observed: point, road: candidate)
            
            if index == 0 {
                // Первая точка: просто берем наблюдение
                newStateProbabilities[candidate] = obsProb
            } else {
                // Выбираем наиболее вероятный предыдущий переход
                var maxProb = 0.0
                for prevState in stateProbabilities.keys {
                    let transProb = transitionProbability(from: prevState, to: candidate)
                    let prob = stateProbabilities[prevState]! * transProb * obsProb
                    if prob > maxProb {
                        maxProb = prob
                    }
                }
                newStateProbabilities[candidate] = maxProb
            }
        }
        
        // Обновляем вероятности
        stateProbabilities = newStateProbabilities
        
        // Выбираем наилучшую дорогу для текущей точки
        if let bestMatch = stateProbabilities.max(by: { $0.value < $1.value })?.key {
            let newCoordinate = projectPointOntoSegment(point: point, segmentStart: bestMatch.start, segmentEnd: bestMatch.end)
            return TestCandidat(trackPoint: gpsTrack[index], newPoint: newCoordinate, candidates: candidates)
        } else {
            return nil
        }
    }
}

private extension MyMapMatcher {
    // Функция поиска ближайших сегментов дороги к координате
    func findClosestRoadSegments(for location: CLLocationCoordinate2D,
                                 previousLocation: CLLocationCoordinate2D?,
                                 roadSegments: [RoadSegment]) -> [RoadSegment] {
        // Вычисляем heading только если есть предыдущая точка
        let locationHeading = previousLocation.map { calculateHeading(from: $0, to: location) } ?? 0.0

        let filterSegments =  roadSegments.filter {
                let angleDiff = abs($0.direction - locationHeading)
                return angleDiff < 30.0 || angleDiff > 330.0 // Учитываем циклический характер углов (0-360)
            }
        let sortedSegments = filterSegments.sorted {
            let projectionPoint1 = projectPointOntoSegment(point: location, segmentStart: $0.start, segmentEnd: $0.end)
            let projectionPoint2 = projectPointOntoSegment(point: location, segmentStart: $1.start, segmentEnd: $1.end)
            return distance(from: location, to: projectionPoint1) < distance(from: location, to: projectionPoint2)
            }
        return sortedSegments.prefix(2).map { $0 }
    }
    func calculateHeading(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let deltaX = to.longitude - from.longitude
        let deltaY = to.latitude - from.latitude
        return atan2(deltaX, deltaY) * 180.0 / .pi
    }
    // Функция расстояния между двумя точками
    func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let loc1 = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let loc2 = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return loc1.distance(from: loc2) // Возвращает расстояние в метрах
    }

    // Вероятность наблюдения точки на данном сегменте
    func observationProbability(observed: CLLocationCoordinate2D, road: RoadSegment) -> Double {
        let d = min(distance(from: observed, to: road.start), distance(from: observed, to: road.end))
        return exp(-d / 50.0) // Чем ближе к дороге, тем выше вероятность (50 м - стандартное отклонение)
    }
    
    // Вероятность перехода между дорогами (чем естественнее переход, тем выше вероятность)
    func transitionProbability(from: RoadSegment, to: RoadSegment) -> Double {
        return from.end.latitude == to.start.latitude && from.end.longitude == to.start.longitude ? 0.9 : 0.1
    }
    
    // Алгоритм Витерби для корректировки трека
    func testCorrectTrack(observations: [TrackPoint], roadSegments: [RoadSegment]) async -> [TrackPoint] {
        var newPoints: [TrackPoint] = []
        
        // Для каждой наблюдаемой точки выбираем ближайшие дороги
        var stateProbabilities: [RoadSegment: Double] = [:]
        
        for (index, observation) in observations.enumerated() {
            let previousLocation: CLLocationCoordinate2D = index > 0 ? observations[index - 1].coordinate : observation.coordinate
            let candidates = findClosestRoadSegments(for: observation.coordinate, previousLocation: previousLocation,  roadSegments: roadSegments)

            var newStateProbabilities: [RoadSegment: Double] = [:]
            
            for candidate in candidates {
                let obsProb = observationProbability(observed: observation.coordinate, road: candidate)
                
                if index == 0 {
                    // Первая точка: просто берем наблюдение
                    newStateProbabilities[candidate] = obsProb
                } else {
                    // Выбираем наиболее вероятный предыдущий переход
                    var maxProb = 0.0
                    for prevState in stateProbabilities.keys {
                        let transProb = transitionProbability(from: prevState, to: candidate)
                        let prob = stateProbabilities[prevState]! * transProb * obsProb
                        if prob > maxProb {
                            maxProb = prob
                        }
                    }
                    newStateProbabilities[candidate] = maxProb
                }
            }
            
            // Обновляем вероятности
            stateProbabilities = newStateProbabilities
            
            // Выбираем наилучшую дорогу для текущей точки
            if let bestMatch = stateProbabilities.max(by: { $0.value < $1.value })?.key {
                let newCoordinate = projectPointOntoSegment(point: observation.coordinate, segmentStart: bestMatch.start, segmentEnd: bestMatch.end)
                let newPoint = TrackPoint(coordinate: newCoordinate, timestamp: observation.timestamp)
                newPoints.append(newPoint)
            }
        }
        
        return newPoints
    }
    func correctTrack(observations: [TrackPoint], roadSegments: [RoadSegment]) async -> [TrackPoint] {
        var newPoints: [TrackPoint] = []
        
        // Для каждой наблюдаемой точки выбираем ближайшие дороги
        var stateProbabilities: [RoadSegment: Double] = [:]
        
        for (index, observation) in observations.enumerated() {
            let previousLocation: CLLocationCoordinate2D = index > 0 ? observations[index - 1].coordinate : observation.coordinate
            let candidates = findClosestRoadSegments(for: observation.coordinate, previousLocation: previousLocation,  roadSegments: roadSegments)

            var newStateProbabilities: [RoadSegment: Double] = [:]
            
            for candidate in candidates {
                let obsProb = observationProbability(observed: observation.coordinate, road: candidate)
                
                if index == 0 {
                    // Первая точка: просто берем наблюдение
                    newStateProbabilities[candidate] = obsProb
                } else {
                    // Выбираем наиболее вероятный предыдущий переход
                    var maxProb = 0.0
                    for prevState in stateProbabilities.keys {
                        let transProb = transitionProbability(from: prevState, to: candidate)
                        let prob = stateProbabilities[prevState]! * transProb * obsProb
                        if prob > maxProb {
                            maxProb = prob
                        }
                    }
                    newStateProbabilities[candidate] = maxProb
                }
            }
            
            // Обновляем вероятности
            stateProbabilities = newStateProbabilities
            
            // Выбираем наилучшую дорогу для текущей точки
            if let bestMatch = stateProbabilities.max(by: { $0.value < $1.value })?.key {
                let newCoordinate = projectPointOntoSegment(point: observation.coordinate, segmentStart: bestMatch.start, segmentEnd: bestMatch.end)
                let newPoint = TrackPoint(coordinate: newCoordinate, timestamp: observation.timestamp)
                newPoints.append(newPoint)
            }
        }
        
        return newPoints
    }
    func projectPointOntoSegment(point: CLLocationCoordinate2D, segmentStart: CLLocationCoordinate2D, segmentEnd: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let ax = segmentStart.longitude
        let ay = segmentStart.latitude
        let bx = segmentEnd.longitude
        let by = segmentEnd.latitude
        let px = point.longitude
        let py = point.latitude

        let abx = bx - ax
        let aby = by - ay
        let apx = px - ax
        let apy = py - ay

        let ab2 = abx * abx + aby * aby
        let ap_ab = apx * abx + apy * aby
        let t = max(0, min(1, ap_ab / ab2)) // Ограничиваем в пределах отрезка

        let x_new = ax + t * abx
        let y_new = ay + t * aby

        return CLLocationCoordinate2D(latitude: y_new, longitude: x_new)
    }
}
