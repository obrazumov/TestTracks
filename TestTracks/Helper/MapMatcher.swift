//
//  MapMatcher.swift
//  TestTracks
//
//  Created by Dmitriy Obrazumov on 13/03/2025.
//
import Foundation
import CoreLocation

// Протокол для реализации алгоритма привязки трека к дорогам
protocol MapMatching {
    /// Привязка GPS-трека к дорожной сети
    /// - Parameters:
    ///   - gpsTrack: Исходные GPS-точки трека
    ///   - roadSegments: Сегменты дорожной сети
    ///   - maxDistance: Максимальное расстояние для поиска кандидатов привязки
    ///   - forceSnapToRoad: Принудительная привязка точек к дороге
    ///   - maxForceSnapDistance: Максимальное расстояние для принудительной привязки
    ///   - removeDuplicates: Удалять ли дубликаты точек
    ///   - fillGaps: Заполнять ли пробелы между точками
    ///   - simplifyTrack: Применять ли упрощение трека
    /// - Returns: Последовательность координат привязанного трека
    func matchTrack(
        gpsTrack: [TrackPoint],
        roadSegments: [RoadSegment],
        maxDistance: Double,
        forceSnapToRoad: Bool,
        maxForceSnapDistance: Double,
        removeDuplicates: Bool,
        fillGaps: Bool,
        simplifyTrack: Bool
    ) -> [CLLocationCoordinate2D]
    func matchTrackCandidat(gpsTrack: [TrackPoint], roadSegments: [RoadSegment], index: Int) async -> TestCandidat?
}

// Структура для точки трека
struct TrackPoint {
    let coordinate: CLLocationCoordinate2D
    let timestamp: Date
}

class MapMatcher: MapMatching {
    // Константы для HMM алгоритма
    private let sigmaZ: Double = 15.0     // Увеличенное значение для ошибки акселерометра (было 4.07)
    private let beta: Double = 3.0        // Параметр экспоненциального распределения для перехода
    
    // Основной алгоритм привязки с учетом направления движения и улучшенной привязкой на поворотах
    func matchTrack(
        gpsTrack: [TrackPoint],
        roadSegments: [RoadSegment],
        maxDistance: Double = 30.0,
        forceSnapToRoad: Bool = true,
        maxForceSnapDistance: Double = 50.0,
        removeDuplicates: Bool = true,
        fillGaps: Bool = true,
        simplifyTrack: Bool = true
    ) -> [CLLocationCoordinate2D] {
        return matchTrackWithErrorCorrection(
            gpsTrack: gpsTrack,
            roadSegments: roadSegments,
            maxDistance: maxDistance,
            forceSnapToRoad: forceSnapToRoad,
            maxForceSnapDistance: maxForceSnapDistance,
            removeDuplicates: removeDuplicates,
            fillGaps: fillGaps,
            simplifyTrack: simplifyTrack
        )
    }
    func matchTrackCandidat(gpsTrack: [TrackPoint], roadSegments: [RoadSegment], index: Int) async -> TestCandidat? {
        nil
    }
    
    // Для обратной совместимости оставляем оригинальный метод
    func matchTrackWithErrorCorrection(
        gpsTrack: [TrackPoint],
        roadSegments: [RoadSegment],
        maxDistance: Double = 30.0,
        forceSnapToRoad: Bool = true,
        maxForceSnapDistance: Double = 50.0,
        removeDuplicates: Bool = true,
        fillGaps: Bool = true,
        simplifyTrack: Bool = true
    ) -> [CLLocationCoordinate2D] {
        []
    }
}

