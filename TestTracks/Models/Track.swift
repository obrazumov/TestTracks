import Foundation
import CoreLocation
import SwiftUI
import MapKit

struct Track: Identifiable {
    let id = UUID()
    let name: String
    let coordinates: [CLLocationCoordinate2D]
    let color: Color
    
    static let colors: [Color] = [.red, .blue]
}

// Структура для хранения отдельных дорог
struct Road: Identifiable {
    let id = UUID()
    let coordinates: [CLLocationCoordinate2D]
    let isUsedByTrack: Bool // флаг, указывающий используется ли дорога треком
    
    // Вычисляем ограничивающий прямоугольник дороги для фильтрации
    var boundingBox: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        var minLat = Double.infinity
        var maxLat = -Double.infinity
        var minLon = Double.infinity
        var maxLon = -Double.infinity
        
        for coord in coordinates {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }
        
        return (minLat, maxLat, minLon, maxLon)
    }
}

// Класс для создания единого оверлея всех дорог
class RoadsOverlay: NSObject, MKOverlay {
    var roads: [Road]
    var boundingMapRect: MKMapRect
    var coordinate: CLLocationCoordinate2D
    var isUsedRoadsOnly: Bool
    
    init(roads: [Road], isUsedRoadsOnly: Bool = false) {
        self.roads = roads
        self.isUsedRoadsOnly = isUsedRoadsOnly
        
        // Вычисляем общий boundingMapRect для всех дорог
        var minX = Double.infinity
        var minY = Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity
        
        for road in roads {
            // Пропускаем дороги, не используемые треком, если указан флаг isUsedRoadsOnly
            if isUsedRoadsOnly && !road.isUsedByTrack {
                continue
            }
            
            for coordinate in road.coordinates {
                let point = MKMapPoint(coordinate)
                minX = min(minX, point.x)
                minY = min(minY, point.y)
                maxX = max(maxX, point.x)
                maxY = max(maxY, point.y)
            }
        }
        
        // Если не нашли координаты (что маловероятно), используем значения по умолчанию
        if minX == Double.infinity {
            minX = 0
            minY = 0
            maxX = 1
            maxY = 1
        }
        
        let width = maxX - minX
        let height = maxY - minY
        self.boundingMapRect = MKMapRect(x: minX, y: minY, width: width, height: height)
        
        // Устанавливаем центральную координату
        let centerX = minX + width / 2
        let centerY = minY + height / 2
        self.coordinate = MKMapPoint(x: centerX, y: centerY).coordinate
        
        super.init()
    }
}

// Класс для рендеринга оверлея дорог
class RoadsOverlayRenderer: MKOverlayRenderer {
    var roads: [Road]
    var isUsedRoadsOnly: Bool
    
    init(overlay: RoadsOverlay) {
        self.roads = overlay.roads
        self.isUsedRoadsOnly = overlay.isUsedRoadsOnly
        super.init(overlay: overlay)
    }
    
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in ctx: CGContext) {
        // Определяем толщину линии в зависимости от масштаба
        let lineWidth = MKRoadWidthAtZoomScale(zoomScale)
        
        // Настраиваем контекст для рисования
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        
        // Добавляем логирование для отладки
        print("Рисуем оверлей дорог. Всего дорог: \(roads.count), isUsedRoadsOnly: \(isUsedRoadsOnly)")
        print("Видимая область карты: \(mapRect)")
        print("Масштаб: \(zoomScale), линия: \(lineWidth)")
        
        var drawnRoads = 0
        var skippedRoads = 0
        
        // Рисуем все дороги, фильтруя их по isUsedByTrack если нужно
        for road in roads {
            // Пропускаем дороги, не используемые треком, если указан флаг isUsedRoadsOnly
            if isUsedRoadsOnly && !road.isUsedByTrack {
                skippedRoads += 1
                continue
            }
            
            if road.coordinates.count < 2 {
                skippedRoads += 1
                continue
            }
            
            // Создаем boundingMapRect для дороги для логгирования
            var roadMapRect = MKMapRect.null
            for coordinate in road.coordinates {
                let point = MKMapPoint(coordinate)
                if roadMapRect.isNull {
                    roadMapRect = MKMapRect(x: point.x, y: point.y, width: 0, height: 0)
                } else {
                    roadMapRect = roadMapRect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
                }
            }
            
            // Отрисовываем дорогу даже если она не пересекается с видимой областью карты
            // Это позволит гарантированно отобразить все дороги, входящие в bbox трека
            
            // Задаем цвет и толщину в зависимости от того, используется ли дорога треком
            if road.isUsedByTrack {
                // Увеличиваем яркость синего цвета для лучшей видимости
                ctx.setStrokeColor(UIColor.blue.withAlphaComponent(1.0).cgColor)
                ctx.setLineWidth(lineWidth * 2.0) // Увеличиваем для лучшей видимости
            } else {
                // Делаем серые дороги более заметными
                ctx.setStrokeColor(UIColor.darkGray.withAlphaComponent(0.7).cgColor)
                ctx.setLineWidth(lineWidth * 1.2)
            }
            
            // Создаем путь для рисования дороги
            ctx.beginPath()
            
            // Преобразуем координаты в точки на экране
            var firstPoint = true
            for coordinate in road.coordinates {
                let point = self.point(for: MKMapPoint(coordinate))
                
                if firstPoint {
                    ctx.move(to: point)
                    firstPoint = false
                } else {
                    ctx.addLine(to: point)
                }
            }
            
            // Рисуем путь
            ctx.strokePath()
            drawnRoads += 1
        }
        
        print("Фактически нарисовано дорог: \(drawnRoads), пропущено: \(skippedRoads)")
    }
}

// Вспомогательная функция для определения ширины дороги в зависимости от масштаба
func MKRoadWidthAtZoomScale(_ zoomScale: MKZoomScale) -> CGFloat {
    // Базовая ширина дороги (увеличиваем для лучшей видимости)
    let baseWidth: CGFloat = 2.5
    
    // Регулируем ширину в зависимости от масштаба
    // Чем меньше zoomScale, тем больше масштабирование (отдаление)
    if zoomScale > 0.2 {
        // Близкое приближение - тонкие линии для деталей
        return baseWidth
    } else if zoomScale > 0.1 {
        // Среднее приближение - немного толще
        return baseWidth * 1.5
    } else if zoomScale > 0.05 {
        // Дальнее приближение - еще толще
        return baseWidth * 2.0
    } else {
        // Очень дальнее приближение - максимальная толщина для видимости
        return baseWidth * 3.0
    }
} 
