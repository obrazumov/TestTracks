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
    // Кэш boundingRect для каждой дороги для оптимизации отображения
    private var roadBoundingRects: [Int: MKMapRect] = [:]
    
    init(roads: [Road], isUsedRoadsOnly: Bool = false) {
        self.roads = roads
        self.isUsedRoadsOnly = isUsedRoadsOnly
        
        // Вычисляем общий boundingMapRect для всех дорог
        var minX = Double.infinity
        var minY = Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity
        
        // Предварительно рассчитываем boundingRect для каждой дороги
        for (index, road) in roads.enumerated() {
            // Пропускаем дороги, не используемые треком, если указан флаг isUsedRoadsOnly
            if isUsedRoadsOnly && !road.isUsedByTrack {
                continue
            }
            
            if road.coordinates.count >= 2 {
                var roadMinX = Double.infinity
                var roadMinY = Double.infinity
                var roadMaxX = -Double.infinity
                var roadMaxY = -Double.infinity
                
                for coordinate in road.coordinates {
                    let point = MKMapPoint(coordinate)
                    roadMinX = min(roadMinX, point.x)
                    roadMinY = min(roadMinY, point.y)
                    roadMaxX = max(roadMaxX, point.x)
                    roadMaxY = max(roadMaxY, point.y)
                    
                    // Также обновляем общие границы
                    minX = min(minX, point.x)
                    minY = min(minY, point.y)
                    maxX = max(maxX, point.x)
                    maxY = max(maxY, point.y)
                }
                
                // Сохраняем boundingRect для этой дороги в кэше
                let width = roadMaxX - roadMinX
                let height = roadMaxY - roadMinY
                roadBoundingRects[index] = MKMapRect(x: roadMinX, y: roadMinY, width: width, height: height)
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
    
    // Метод для получения boundingRect для дороги
    func getBoundingRect(forRoadAt index: Int) -> MKMapRect? {
        return roadBoundingRects[index]
    }
}

// Класс для рендеринга оверлея дорог
class RoadsOverlayRenderer: MKOverlayRenderer {
    var roads: [Road]
    var isUsedRoadsOnly: Bool
    // Добавляем опциональный массив сегментов дорог для отображения
    var roadSegments: [RoadSegment]?
    
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
        
        // Создаем расширенный прямоугольник с небольшим буфером вокруг видимой области
        // Это предотвратит внезапное появление/исчезновение дорог на границах экрана
        let bufferFactor: Double = 0.2 // 20% буфер
        let bufferWidth = mapRect.size.width * bufferFactor
        let bufferHeight = mapRect.size.height * bufferFactor
        let visibleMapRectWithBuffer = MKMapRect(
            x: mapRect.origin.x - bufferWidth / 2,
            y: mapRect.origin.y - bufferHeight / 2,
            width: mapRect.size.width + bufferWidth,
            height: mapRect.size.height + bufferHeight
        )
        
        var drawnRoads = 0
        var skippedRoads = 0
        var notVisibleRoads = 0
        
        // Получаем ссылку на оверлей для доступа к предварительно рассчитанным boundingRect
        let roadsOverlay = overlay as! RoadsOverlay
        
        // Рисуем только дороги, которые находятся в видимой области карты с буфером
        for (index, road) in roads.enumerated() {
            // Пропускаем дороги, не используемые треком, если указан флаг isUsedRoadsOnly
            if isUsedRoadsOnly && !road.isUsedByTrack {
                skippedRoads += 1
                continue
            }
            
            if road.coordinates.count < 2 {
                skippedRoads += 1
                continue
            }
            
            // Используем предварительно рассчитанный boundingRect из кэша
            if let roadMapRect = roadsOverlay.getBoundingRect(forRoadAt: index) {
                // Проверяем, пересекается ли дорога с видимой областью карты с буфером
                // Если нет, пропускаем её отрисовку
                if !visibleMapRectWithBuffer.intersects(roadMapRect) {
                    notVisibleRoads += 1
                    continue
                }
            } else {
                // Для дорог без предварительно рассчитанного boundingRect, рассчитываем на лету
                var roadMapRect = MKMapRect.null
                for coordinate in road.coordinates {
                    let point = MKMapPoint(coordinate)
                    if roadMapRect.isNull {
                        roadMapRect = MKMapRect(x: point.x, y: point.y, width: 0, height: 0)
                    } else {
                        roadMapRect = roadMapRect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
                    }
                }
                
                // Проверяем, пересекается ли дорога с видимой областью карты с буфером
                if !visibleMapRectWithBuffer.intersects(roadMapRect) {
                    notVisibleRoads += 1
                    continue
                }
            }
            
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
            var previousCoordinate: CLLocationCoordinate2D? = nil
            
            // Оптимизация: разбиваем дорогу на сегменты и рисуем только те, которые видны
            for i in 0..<(road.coordinates.count) {
                let coordinate = road.coordinates[i]
                
                // Проверяем, находится ли текущая точка внутри видимой области
                let mapPoint = MKMapPoint(coordinate)
                let isCurrentPointVisible = visibleMapRectWithBuffer.contains(mapPoint)
                
                // Проверяем, находится ли предыдущая точка внутри видимой области
                var isPreviousPointVisible = false
                if let prevCoord = previousCoordinate {
                    let prevMapPoint = MKMapPoint(prevCoord)
                    isPreviousPointVisible = visibleMapRectWithBuffer.contains(prevMapPoint)
                }
                
                // Рисуем сегмент, если хотя бы одна из точек видима или если 
                // сегмент пересекает видимую область
                if isCurrentPointVisible || isPreviousPointVisible || (previousCoordinate != nil && 
                    segmentIntersectsRect(start: previousCoordinate!, end: coordinate, rect: visibleMapRectWithBuffer)) {
                    
                    let point = self.point(for: mapPoint)
                    
                    if firstPoint || previousCoordinate == nil {
                        ctx.move(to: point)
                        firstPoint = false
                    } else {
                        ctx.addLine(to: point)
                    }
                } else if firstPoint && i > 0 {
                    // Если текущая точка не видна и это начало пути,
                    // перемещаемся к ней, но не рисуем линию
                    let point = self.point(for: mapPoint)
                    ctx.move(to: point)
                    firstPoint = false
                }
                
                previousCoordinate = coordinate
            }
            
            // Рисуем путь
            ctx.strokePath()
            drawnRoads += 1
        }
        
        // Теперь рисуем RoadSegment с фиолетовым цветом
        if let segments = roadSegments {
            // Настройки для отрисовки сегментов
           
            ctx.setLineWidth(lineWidth * 5) // Немного толще обычных дорог для выделения
            
            var drawnSegments = 0
            var skippedSegments = 0
            
            // Отрисовываем каждый сегмент
            for segment in segments {
                // Проверяем, находится ли сегмент в видимой области
                ctx.setStrokeColor(UIColor.random().withAlphaComponent(0.8).cgColor)
                let startPoint = MKMapPoint(segment.start)
                let endPoint = MKMapPoint(segment.end)
                
                let isStartVisible = visibleMapRectWithBuffer.contains(startPoint)
                let isEndVisible = visibleMapRectWithBuffer.contains(endPoint)
                
                // Если хотя бы одна из точек сегмента видима или сегмент пересекает видимую область
                if isStartVisible || isEndVisible || 
                   segmentIntersectsRect(start: segment.start, end: segment.end, rect: visibleMapRectWithBuffer) {
                    
                    ctx.beginPath()
                    
                    // Преобразуем координаты в точки экрана
                    let startScreenPoint = self.point(for: startPoint)
                    let endScreenPoint = self.point(for: endPoint)
                    
                    // Рисуем линию
                    ctx.move(to: startScreenPoint)
                    ctx.addLine(to: endScreenPoint)
                    ctx.strokePath()
                    
                    drawnSegments += 1
                } else {
                    skippedSegments += 1
                }
            }
            
            print("Отрисовано \(drawnSegments) сегментов дорог, пропущено \(skippedSegments) сегментов")
        }
        
        print("Фактически нарисовано дорог: \(drawnRoads), пропущено: \(skippedRoads), за пределами видимости: \(notVisibleRoads)")
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

// Вспомогательная функция для проверки пересечения сегмента с прямоугольником
func segmentIntersectsRect(start: CLLocationCoordinate2D, end: CLLocationCoordinate2D, rect: MKMapRect) -> Bool {
    let startPoint = MKMapPoint(start)
    let endPoint = MKMapPoint(end)
    
    // Проверяем пересечение сегмента с каждой из сторон прямоугольника
    // Верхняя граница
    if lineSegmentIntersection(ax: startPoint.x, ay: startPoint.y, bx: endPoint.x, by: endPoint.y,
                              cx: rect.minX, cy: rect.minY, dx: rect.maxX, dy: rect.minY) {
        return true
    }
    
    // Правая граница
    if lineSegmentIntersection(ax: startPoint.x, ay: startPoint.y, bx: endPoint.x, by: endPoint.y,
                              cx: rect.maxX, cy: rect.minY, dx: rect.maxX, dy: rect.maxY) {
        return true
    }
    
    // Нижняя граница
    if lineSegmentIntersection(ax: startPoint.x, ay: startPoint.y, bx: endPoint.x, by: endPoint.y,
                              cx: rect.minX, cy: rect.maxY, dx: rect.maxX, dy: rect.maxY) {
        return true
    }
    
    // Левая граница
    if lineSegmentIntersection(ax: startPoint.x, ay: startPoint.y, bx: endPoint.x, by: endPoint.y,
                              cx: rect.minX, cy: rect.minY, dx: rect.minX, dy: rect.maxY) {
        return true
    }
    
    return false
}

// Проверка пересечения двух отрезков
func lineSegmentIntersection(ax: Double, ay: Double, bx: Double, by: Double,
                            cx: Double, cy: Double, dx: Double, dy: Double) -> Bool {
    // Уравнение первого отрезка: P = A + t(B-A), где t ∈ [0,1]
    // Уравнение второго отрезка: Q = C + s(D-C), где s ∈ [0,1]
    // Пересечение есть, если найдутся такие t и s, что P = Q
    
    let abx = bx - ax
    let aby = by - ay
    let cdx = dx - cx
    let cdy = dy - cy
    
    // Определитель для проверки параллельности отрезков
    let det = abx * cdy - aby * cdx
    
    // Отрезки параллельны, пересечения нет
    if abs(det) < 1e-9 {
        return false
    }
    
    let acx = cx - ax
    let acy = cy - ay
    
    // Параметры пересечения
    let t = (acx * cdy - acy * cdx) / det
    let s = (acx * aby - acy * abx) / det
    
    // Пересечение есть, если оба параметра находятся в диапазоне [0,1]
    return (t >= 0 && t <= 1 && s >= 0 && s <= 1)
} 
