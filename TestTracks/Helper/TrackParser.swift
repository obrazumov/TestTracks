import Foundation
import CoreLocation

// Определяем уведомление для прогресса загрузки дорог
extension Notification.Name {
    static let roadLoadingProgress = Notification.Name("roadLoadingProgress")
}

class TrackParser {
    static func parseNMEAFile(_ url: URL) -> [NMEAData] {
        var trackData: [NMEAData] = []
        
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            if line.hasPrefix("$GNRMC") {
                let components = line.components(separatedBy: ",")
                if components.count >= 12,
                   components[0].contains("RMC") {
                    
                    // Время UTC
                        let utcTime = String(components[1])
                        // Статус данных (A = активный, V = недействительный)
                        let isValid = components[2] == "A"
                    // Широта (например, 5800.126343,N)
                        guard let latDegreesMinutes = Double(components[3]),
                              let latDirection = String?(components[4]) else { continue }
                        let latDegrees = floor(latDegreesMinutes / 100) // Целая часть - градусы
                        let latMinutes = latDegreesMinutes.truncatingRemainder(dividingBy: 100) // Остаток - минуты
                        var latitude = latDegrees + (latMinutes / 60) // Перевод в десятичные градусы
                        if latDirection == "S" { latitude = -latitude } // Южная широта - отрицательная
                        
                        // Долгота (например, 05617.759628,E)
                        guard let lonDegreesMinutes = Double(components[5]),
                              let lonDirection = String?(components[6]) else { continue }
                        let lonDegrees = floor(lonDegreesMinutes / 100)
                        let lonMinutes = lonDegreesMinutes.truncatingRemainder(dividingBy: 100)
                        var longitude = lonDegrees + (lonMinutes / 60)
                        if lonDirection == "W" { longitude = -longitude } // Западная долгота - отрицательная
                        
                        // Дата (например, 060325)
                        let date = String(components[9])
                    trackData.append(.init(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), timestamp: Date(timeIntervalSince1970: Double(components[1]) ?? 0), utcTime: utcTime, date: date, isValid: isValid))
                }
            }
        }
        
            return trackData
    }
    
    static func parseCSVFile(_ url: URL) -> [TrackData] {
        var trackData: [TrackData] = []
        
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let components = line.components(separatedBy: ",")
            if components.count == 4,
               let timestampMs = Int(components[0]),
               let latitude = Double(components[1]),
               let longitude = Double(components[2]),
               let headingTrueDegrees = Double(components[3]) {
                trackData.append(TrackData(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), timestampMs: timestampMs, headingTrueRad: headingTrueDegrees, headingEstRad: 0, dRmeters: 0))
            }
        }
        return trackData
    }
    
    private static func convertNMEACoordinate(_ value: Double, direction: String) -> Double {
        let degrees = floor(value / 100)
        let minutes = value - (degrees * 100)
        var decimal = degrees + (minutes / 60)
        
        if direction == "S" || direction == "W" {
            decimal = -decimal
        }
        
        return decimal
    }
    
    static func parseGeoJSONFile(_ url: URL) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        
        guard let data = try? Data(contentsOf: url) else {
            print("Не удалось прочитать GeoJSON файл")
            return []
        }
        
        do {
            guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let features = jsonObject["features"] as? [[String: Any]] else {
                print("Неверный формат GeoJSON")
                return []
            }
            
            // Ограничение количества обрабатываемых объектов для уменьшения нагрузки
            let processedFeatures = features.count > 1000 ? Array(features.prefix(1000)) : features
            print("Обработка \(processedFeatures.count) из \(features.count) объектов GeoJSON")
            
            for feature in processedFeatures {
                if let geometry = feature["geometry"] as? [String: Any],
                   let type = geometry["type"] as? String {
                    
                    var featureCoordinates: [CLLocationCoordinate2D] = []
                    
                    if type == "LineString" {
                        if let coordsArray = geometry["coordinates"] as? [[Double]] {
                            // Ограничиваем количество точек для одной линии
                            let maxPoints = min(coordsArray.count, 200)
                            let strideValue = coordsArray.count > maxPoints ? coordsArray.count / maxPoints : 1
                            
                            for i in stride(from: 0, to: coordsArray.count, by: strideValue) {
                                if let coord = coordsArray[safe: i], coord.count >= 2 {
                                    let longitude = coord[0]
                                    let latitude = coord[1]
                                    featureCoordinates.append(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
                                }
                            }
                        }
                    } else if type == "MultiLineString" {
                        if let multiLineArray = geometry["coordinates"] as? [[[Double]]] {
                            for lineArray in multiLineArray {
                                // Ограничиваем количество точек для одной линии
                                let maxPoints = min(lineArray.count, 200)
                                let strideValue = lineArray.count > maxPoints ? lineArray.count / maxPoints : 1
                                
                                for i in stride(from: 0, to: lineArray.count, by: strideValue) {
                                    if let coord = lineArray[safe: i], coord.count >= 2 {
                                        let longitude = coord[0]
                                        let latitude = coord[1]
                                        featureCoordinates.append(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
                                    }
                                }
                            }
                        }
                    }
                    
                    // Добавляем координаты этого объекта в общий массив
                    coordinates.append(contentsOf: featureCoordinates)
                }
            }
        } catch {
            print("Ошибка при парсинге GeoJSON: \(error)")
        }
        
        print("Загружено \(coordinates.count) координат из GeoJSON")
        return coordinates
    }
    
    // Метод для парсинга GeoJSON в массив отдельных дорог
    static func parseGeoJSONToRoads(_ url: URL) -> [Road] {
        var roads: [Road] = []
        
        guard let data = try? Data(contentsOf: url) else {
            print("Не удалось прочитать GeoJSON файл")
            return []
        }
        
        do {
            guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("Неверный формат GeoJSON")
                return []
            }
            
            // Обрабатываем как FeatureCollection
            if let features = jsonObject["features"] as? [[String: Any]] {
                print("Обработка FeatureCollection с \(features.count) объектами")
                
                // Обработка без ограничения по количеству объектов для полноты дорожной сети
                for feature in features {
                    if let geometry = feature["geometry"] as? [String: Any],
                       let type = geometry["type"] as? String {
                        
                        let roadCoordinates = extractCoordinatesFromGeometry(type: type, geometry: geometry)
                        if !roadCoordinates.isEmpty {
                            roads.append(Road(coordinates: roadCoordinates, isUsedByTrack: false))
                        }
                    }
                }
            } 
            // Обрабатываем как отдельную геометрию (например, LineString, MultiLineString)
            else if let type = jsonObject["type"] as? String, type != "FeatureCollection" {
                let roadCoordinates = extractCoordinatesFromGeometry(type: type, geometry: jsonObject)
                if !roadCoordinates.isEmpty {
                    roads.append(Road(coordinates: roadCoordinates, isUsedByTrack: false))
                }
            }
        } catch {
            print("Ошибка при парсинге GeoJSON: \(error)")
        }
        
        print("Загружено \(roads.count) дорог из GeoJSON")
        return roads
    }
    
    // Вспомогательный метод для извлечения координат из различных типов геометрии GeoJSON
    private static func extractCoordinatesFromGeometry(type: String, geometry: [String: Any]) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        
        switch type {
        case "Point":
            if let coordArray = geometry["coordinates"] as? [Double], coordArray.count >= 2 {
                let longitude: Double = coordArray[0]
                let latitude: Double = coordArray[1]
                coordinates.append(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
            }
            
        case "LineString":
            if let coordsArray = geometry["coordinates"] as? [[Double]] {
                // Используем все точки без прореживания
                for coord in coordsArray {
                    if coord.count >= 2 {
                        let longitude = coord[0]
                        let latitude = coord[1]
                        coordinates.append(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
                    }
                }
            }
            
        case "MultiLineString":
            if let multiLineArray = geometry["coordinates"] as? [[[Double]]] {
                // Объединяем все линии в одну дорогу без прореживания
                var lineCoordinates: [CLLocationCoordinate2D] = []
                
                for lineArray in multiLineArray {
                    // Используем все точки без прореживания
                    for coord in lineArray {
                        if coord.count >= 2 {
                            let longitude = coord[0]
                            let latitude = coord[1]
                            lineCoordinates.append(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
                        }
                    }
                }
                
                coordinates = lineCoordinates
            }
            
        case "Polygon":
            if let polygonArray = geometry["coordinates"] as? [[[Double]]], !polygonArray.isEmpty {
                // Берем только внешний контур полигона (первый массив координат) без прореживания
                let outerRing = polygonArray[0]
                
                // Используем все точки без прореживания
                for coord in outerRing {
                    if coord.count >= 2 {
                        let longitude = coord[0]
                        let latitude = coord[1]
                        coordinates.append(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
                    }
                }
            }
            
        case "MultiPolygon":
            if let multiPolygonArray = geometry["coordinates"] as? [[[[Double]]]] {
                // Объединяем все внешние контуры полигонов без прореживания
                var polygonCoordinates: [CLLocationCoordinate2D] = []
                
                for polygonArray in multiPolygonArray {
                    if !polygonArray.isEmpty {
                        // Берем только внешний контур каждого полигона
                        let outerRing = polygonArray[0]
                        
                        // Используем все точки без прореживания
                        for coord in outerRing {
                            if coord.count >= 2 {
                                let longitude = coord[0]
                                let latitude = coord[1]
                                polygonCoordinates.append(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
                            }
                        }
                    }
                }
                
                coordinates = polygonCoordinates
            }
            
        case "GeometryCollection":
            if let geometries = geometry["geometries"] as? [[String: Any]] {
                // Обрабатываем каждую геометрию в коллекции
                for subGeometry in geometries {
                    if let subType = subGeometry["type"] as? String {
                        let subCoordinates = extractCoordinatesFromGeometry(type: subType, geometry: subGeometry)
                        coordinates.append(contentsOf: subCoordinates)
                    }
                }
            }
            
        default:
            print("Неподдерживаемый тип геометрии: \(type)")
        }
        
        return coordinates
    }
    
    // Оптимизированный метод для ленивой загрузки только нужных дорог
    static func parseGeoJSONToRoadsLazy(_ url: URL, 
                                       boundingBox: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)? = nil,
                                       maxRoads: Int = 500) -> [Road] {
        var roads: [Road] = []
        let startTime = Date()
        
        // Проверяем кэш для файла
        let fileAttributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileDate = fileAttributes?[.modificationDate] as? Date ?? Date()
        let fileSize = fileAttributes?[.size] as? Int ?? 0
        
        let cacheKey = "\(url.lastPathComponent)_\(fileDate.timeIntervalSince1970)_\(fileSize)_\(maxRoads)"
        
        // Проверяем, есть ли файл в кэше и возвращаем его при наличии
        if let cachedRoads = CacheManager.shared.getCachedRoads(forKey: cacheKey) {
            print("Данные загружены из кэша: \(cachedRoads.count) дорог")
            // Отправляем уведомление о завершении
            notifyProgress("Данные загружены из кэша: \(cachedRoads.count) дорог", roads: cachedRoads)
            return cachedRoads
        }
        
        guard let data = try? Data(contentsOf: url) else {
            print("Не удалось прочитать GeoJSON файл")
            return []
        }
        
        // Уведомление о начале загрузки
        notifyProgress("Начинаю обработку GeoJSON файла размером \(String(format: "%.2f", Double(data.count) / 1024.0 / 1024.0)) MB", roads: [])
        
        // Специальная оптимизация для больших файлов - используем JSONSerialization вместо декодеров
        // для лучшей производительности и контроля памяти
        do {
            print("Файл GeoJSON размером \(data.count / 1024) KB")
            
            guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("Неверный формат GeoJSON")
                return []
            }
            
            // Пакетная обработка и прореживание для быстрой загрузки
            let processingInterval = 1 // Обрабатываем все объекты
            var currentRoadCount = 0
            var processedCount = 0
            var loadedCount = 0
            
            // Обрабатываем FeatureCollection
            if let features = jsonObject["features"] as? [[String: Any]] {
                let totalFeatures = features.count
                print("GeoJSON содержит \(totalFeatures) объектов")
                notifyProgress("GeoJSON содержит \(totalFeatures) объектов", roads: [])
                
                // Увеличиваем размер партии для более быстрой обработки
                let batchSize = 500 
                var currentBatch = 0
                
                var lastProgressUpdate = Date()
                let progressUpdateInterval: TimeInterval = 0.3 // обновляем прогресс не чаще, чем раз в 0.3 секунды
                
                while currentRoadCount < maxRoads && currentBatch * batchSize < features.count {
                    let startIdx = currentBatch * batchSize
                    let endIdx = min(startIdx + batchSize, features.count)
                    let batchFeatures = features[startIdx..<endIdx]
                    
                    // Обновляем прогресс
                    let now = Date()
                    if now.timeIntervalSince(lastProgressUpdate) > progressUpdateInterval {
                        let progress = Double(startIdx) / Double(totalFeatures)
                        let progressPercent = Int(progress * 100)
                        notifyProgress("Обработано \(startIdx)/\(totalFeatures) объектов (\(progressPercent)%)", roads: roads)
                        lastProgressUpdate = now
                    }
                    
                    // Обрабатываем пакет последовательно - это безопаснее и достаточно быстро для GeoJSON
                    for (index, feature) in batchFeatures.enumerated() {
                        // Пропускаем часть объектов для ускорения
                        if (startIdx + index) % processingInterval != 0 {
                            continue
                        }
                        
                        processedCount += 1
                        
                        if let geometry = feature["geometry"] as? [String: Any],
                           let type = geometry["type"] as? String {
                            
                            // Быстрая проверка на нахождение в заданной области
                            if boundingBox != nil, let featureBBox = getFeatureBoundingBox(geometry: geometry, type: type) {
                                // Изменяем логику: если нет пересечения, проверяем точки внутри области
                                if !isBoxIntersecting(box1: boundingBox!, box2: featureBBox) {
                                    // Дополнительная проверка для точек, которые могут быть внутри bbox,
                                    // даже если boundingBox всей дороги не пересекается с bbox трека
                                    let hasPointsInBoundingBox = checkPointsInBoundingBox(geometry: geometry, 
                                                                                           type: type, 
                                                                                           boundingBox: boundingBox!)
                                    if !hasPointsInBoundingBox {
                                        continue // Пропускаем, только если ни одна точка не попадает в bbox
                                    }
                                }
                            }
                            
                            loadedCount += 1
                            
                            let roadCoordinates = extractCoordinatesFromGeometry(type: type, geometry: geometry)
                            if !roadCoordinates.isEmpty {
                                // Создаем объект Road с предварительным вычислением boundingBox
                                let road = Road(coordinates: roadCoordinates, isUsedByTrack: false)
                                roads.append(road)
                                currentRoadCount += 1
                                
                                // Проверяем достижение лимита
                                if currentRoadCount >= maxRoads {
                                    break
                                }
                            }
                        }
                    }
                    
                    // Периодически обновляем UI с промежуточными данными
                    if currentBatch % 2 == 1 && roads.count > 0 {
                        notifyProgress("Промежуточное обновление: \(roads.count) дорог", roads: roads)
                    }
                    
                    currentBatch += 1
                }
            }
            // Обрабатываем отдельную геометрию
            else if let type = jsonObject["type"] as? String, type != "FeatureCollection" {
                let roadCoordinates = extractCoordinatesFromGeometry(type: type, geometry: jsonObject)
                if !roadCoordinates.isEmpty {
                    let road = Road(coordinates: roadCoordinates, isUsedByTrack: false)
                    roads.append(road)
                }
            }
            
            let endTime = Date()
            let elapsedTime = endTime.timeIntervalSince(startTime)
            let finishMessage = "Загрузка GeoJSON заняла \(String(format: "%.2f", elapsedTime)) сек. Обработано \(processedCount) объектов, загружено \(loadedCount) дорог."
            print(finishMessage)
            notifyProgress(finishMessage, roads: roads)
            
            // Сохраняем результат в кэш
            CacheManager.shared.cacheRoads(roads, forKey: cacheKey)
        } catch {
            print("Ошибка при парсинге GeoJSON: \(error)")
            notifyProgress("Ошибка при парсинге GeoJSON: \(error)", roads: [])
        }
        
        return roads
    }
    
    // Вспомогательный метод для определения примерной ограничивающей рамки для геометрии
    private static func getFeatureBoundingBox(geometry: [String: Any], type: String) -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)? {
        var minLat = Double.infinity
        var maxLat = -Double.infinity
        var minLon = Double.infinity
        var maxLon = -Double.infinity
        var hasCoordinates = false
        
        switch type {
        case "Point":
            if let coordArray = geometry["coordinates"] as? [Double], coordArray.count >= 2 {
                let longitude: Double = coordArray[0]
                let latitude: Double = coordArray[1]
                minLat = latitude
                maxLat = latitude
                minLon = longitude
                maxLon = longitude
                hasCoordinates = true
            }
            
        case "LineString":
            if let coordsArray = geometry["coordinates"] as? [[Double]] {
                // Для оптимизации проверяем только первую и последнюю точки
                if let firstCoord = coordsArray.first, let lastCoord = coordsArray.last,
                   firstCoord.count >= 2, lastCoord.count >= 2 {
                    minLat = min(firstCoord[1], lastCoord[1])
                    maxLat = max(firstCoord[1], lastCoord[1])
                    minLon = min(firstCoord[0], lastCoord[0])
                    maxLon = max(firstCoord[0], lastCoord[0])
                    hasCoordinates = true
                    
                    // Проверяем еще несколько точек для более точной оценки
                    if coordsArray.count > 2 {
                        let middleIndex = coordsArray.count / 2
                        if let middleCoord = coordsArray[safe: middleIndex], middleCoord.count >= 2 {
                            minLat = min(minLat, middleCoord[1])
                            maxLat = max(maxLat, middleCoord[1])
                            minLon = min(minLon, middleCoord[0])
                            maxLon = max(maxLon, middleCoord[0])
                        }
                    }
                }
            }
            
        case "MultiLineString":
            if let multiLineArray = geometry["coordinates"] as? [[[Double]]],
               !multiLineArray.isEmpty {
                // Проверяем первую и последнюю линии
                if let firstLine = multiLineArray.first, !firstLine.isEmpty,
                   let lastLine = multiLineArray.last, !lastLine.isEmpty {
                    // Проверяем крайние точки линий
                    if let firstCoord = firstLine.first, let lastCoord = lastLine.last,
                       firstCoord.count >= 2, lastCoord.count >= 2 {
                        minLat = min(firstCoord[1], lastCoord[1])
                        maxLat = max(firstCoord[1], lastCoord[1])
                        minLon = min(firstCoord[0], lastCoord[0])
                        maxLon = max(firstCoord[0], lastCoord[0])
                        hasCoordinates = true
                    }
                }
            }
            
        default:
            return nil // Для других типов используем более сложную логику или возвращаем nil
        }
        
        return hasCoordinates ? (minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon) : nil
    }
    
    // Проверка пересечения двух bounding box
    private static func isBoxIntersecting(
        box1: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double),
        box2: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)
    ) -> Bool {
        return !(box1.maxLat < box2.minLat || 
                box1.minLat > box2.maxLat || 
                box1.maxLon < box2.minLon || 
                box1.minLon > box2.maxLon)
    }
    
    // Вспомогательный метод для отправки уведомлений о прогрессе
    private static func notifyProgress(_ message: String, roads: [Road]) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .roadLoadingProgress, 
                object: nil, 
                userInfo: ["progress": message, "roads": roads]
            )
        }
    }
    
    // Вспомогательный метод для проверки, попадает ли хотя бы одна точка геометрии в заданную область
    private static func checkPointsInBoundingBox(geometry: [String: Any], 
                                                type: String, 
                                                boundingBox: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)) -> Bool {
        switch type {
        case "Point":
            if let coordArray = geometry["coordinates"] as? [Double], 
               coordArray.count >= 2 {
                let longitude = coordArray[0]
                let latitude = coordArray[1]
                
                return latitude >= boundingBox.minLat && latitude <= boundingBox.maxLat &&
                       longitude >= boundingBox.minLon && longitude <= boundingBox.maxLon
            }
            
        case "LineString":
            if let coordsArray = geometry["coordinates"] as? [[Double]] {
                // Проверяем все точки линии
                for coord in coordsArray {
                    if coord.count >= 2 {
                        let longitude = coord[0]
                        let latitude = coord[1]
                        
                        if latitude >= boundingBox.minLat && latitude <= boundingBox.maxLat &&
                           longitude >= boundingBox.minLon && longitude <= boundingBox.maxLon {
                            return true
                        }
                    }
                }
            }
            
        case "MultiLineString":
            if let multiLineArray = geometry["coordinates"] as? [[[Double]]] {
                // Проверяем точки всех линий
                for lineArray in multiLineArray {
                    for coord in lineArray {
                        if coord.count >= 2 {
                            let longitude = coord[0]
                            let latitude = coord[1]
                            
                            if latitude >= boundingBox.minLat && latitude <= boundingBox.maxLat &&
                               longitude >= boundingBox.minLon && longitude <= boundingBox.maxLon {
                                return true
                            }
                        }
                    }
                }
            }
            
        case "Polygon":
            if let polygonArray = geometry["coordinates"] as? [[[Double]]], 
               !polygonArray.isEmpty {
                // Проверяем только внешний контур полигона
                let outerRing = polygonArray[0]
                
                for coord in outerRing {
                    if coord.count >= 2 {
                        let longitude = coord[0]
                        let latitude = coord[1]
                        
                        if latitude >= boundingBox.minLat && latitude <= boundingBox.maxLat &&
                           longitude >= boundingBox.minLon && longitude <= boundingBox.maxLon {
                            return true
                        }
                    }
                }
            }
            
        case "MultiPolygon":
            if let multiPolygonArray = geometry["coordinates"] as? [[[[Double]]]] {
                // Проверяем внешние контуры всех полигонов
                for polygonArray in multiPolygonArray {
                    if !polygonArray.isEmpty {
                        let outerRing = polygonArray[0]
                        
                        for coord in outerRing {
                            if coord.count >= 2 {
                                let longitude = coord[0]
                                let latitude = coord[1]
                                
                                if latitude >= boundingBox.minLat && latitude <= boundingBox.maxLat &&
                                   longitude >= boundingBox.minLon && longitude <= boundingBox.maxLon {
                                    return true
                                }
                            }
                        }
                    }
                }
            }
            
        default:
            return false
        }
        
        return false
    }
}

// Безопасный доступ к элементам массива
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
} 
