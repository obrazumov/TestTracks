import Foundation
import CoreLocation

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
} 
