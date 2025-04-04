import Foundation

/// Типы реализации алгоритма привязки трека к дорогам
enum MapMatcherType {
    /// Стандартный алгоритм с использованием HMM и топологии дорог
    case standard
    /// Пользовательская реализация алгоритма
    case custom(MapMatching)
}

/// Фабрика для создания различных реализаций алгоритма привязки трека к дорогам
class MapMatcherFactory {
    /// Создать реализацию алгоритма привязки трека к дорогам
    /// - Parameter type: Тип алгоритма
    /// - Returns: Реализация алгоритма привязки
    static func createMapMatcher(type: MapMatcherType) -> MapMatching {
        switch type {
        case .standard:
            return MapMatcher()
        case .custom(let matcher):
            return matcher
        }
    }
}
