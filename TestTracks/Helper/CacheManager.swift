import Foundation
import CoreLocation

// Класс для управления кэшированием дорог, чтобы ускорить загрузку при повторных запусках
class CacheManager {
    static let shared = CacheManager()
    
    private let cacheDirectory: URL
    private let fileManager = FileManager.default
    
    private init() {
        // Получаем директорию кэша приложения
        if let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let appCacheDir = cacheDir.appendingPathComponent("RoadCache")
            
            // Создаем директорию, если она не существует
            if !fileManager.fileExists(atPath: appCacheDir.path) {
                try? fileManager.createDirectory(at: appCacheDir, withIntermediateDirectories: true)
            }
            
            cacheDirectory = appCacheDir
        } else {
            // Если не можем получить директорию кэша, используем временную директорию
            cacheDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("RoadCache")
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
        
        print("Кэш инициализирован: \(cacheDirectory.path)")
    }
    
    // Сохраняет дороги в кэш
    func cacheRoads(_ roads: [Road], forKey key: String) {
        // Создаем простое представление дороги для сериализации
        let roadData = roads.map { road -> [String: Any] in
            let coordinates = road.coordinates.map { coord -> [String: Double] in
                return ["lat": coord.latitude, "lon": coord.longitude]
            }
            return ["coordinates": coordinates, "isUsedByTrack": road.isUsedByTrack]
        }
        
        // Сохраняем в файл
        let cacheFile = cacheDirectory.appendingPathComponent("\(key).json")
        
        do {
            let data = try JSONSerialization.data(withJSONObject: roadData)
            try data.write(to: cacheFile)
            print("Дороги успешно кэшированы: \(roads.count)")
        } catch {
            print("Ошибка при кэшировании дорог: \(error)")
        }
    }
    
    // Получает дороги из кэша
    func getCachedRoads(forKey key: String) -> [Road]? {
        let cacheFile = cacheDirectory.appendingPathComponent("\(key).json")
        
        // Проверяем, существует ли файл кэша
        guard fileManager.fileExists(atPath: cacheFile.path),
              let data = try? Data(contentsOf: cacheFile) else {
            return nil
        }
        
        do {
            guard let roadData = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return nil
            }
            
            // Преобразуем данные обратно в Roads
            let roads = roadData.compactMap { roadDict -> Road? in
                guard let coordsData = roadDict["coordinates"] as? [[String: Double]],
                      let isUsedByTrack = roadDict["isUsedByTrack"] as? Bool else {
                    return nil
                }
                
                let coordinates = coordsData.compactMap { coordDict -> CLLocationCoordinate2D? in
                    guard let lat = coordDict["lat"], let lon = coordDict["lon"] else {
                        return nil
                    }
                    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
                }
                
                if !coordinates.isEmpty {
                    return Road(coordinates: coordinates, isUsedByTrack: isUsedByTrack)
                }
                return nil
            }
            
            return roads
        } catch {
            print("Ошибка при чтении кэша дорог: \(error)")
            return nil
        }
    }
    
    // Очищает кэш
    func clearCache() {
        do {
            let cacheContents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for file in cacheContents {
                try fileManager.removeItem(at: file)
            }
            print("Кэш очищен")
        } catch {
            print("Ошибка при очистке кэша: \(error)")
        }
    }
} 