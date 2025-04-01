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
        // Создаем объекты CLLocation для точных геодезических вычислений
        let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
        let startLocation = CLLocation(latitude: start.latitude, longitude: start.longitude)
        let endLocation = CLLocation(latitude: end.latitude, longitude: end.longitude)
        
        // Вычисляем длину отрезка
        let lineLength = startLocation.distance(from: endLocation)
        
        // Если отрезок вырожден в точку, возвращаем расстояние до этой точки
        if lineLength < 0.1 { // Порог 10 см для исключения ошибок округления
            return location.distance(from: startLocation)
        }
        
        // Вычисляем параметр t - положение проекции точки на прямую
        // t = 0 соответствует проекции в начальной точке отрезка
        // t = 1 соответствует проекции в конечной точке отрезка
        // t = 0.5 соответствует проекции посередине отрезка
        var t = ((point.latitude - start.latitude) * (end.latitude - start.latitude) +
                (point.longitude - start.longitude) * (end.longitude - start.longitude)) / 
                ((end.latitude - start.latitude) * (end.latitude - start.latitude) + 
                 (end.longitude - start.longitude) * (end.longitude - start.longitude))
        
        // Ограничиваем t значениями от 0 до 1, чтобы проекция была строго на отрезке
        t = max(0, min(1, t))
        
        // Вычисляем координаты проекции точки на отрезок
        let nearestLat = start.latitude + t * (end.latitude - start.latitude)
        let nearestLon = start.longitude + t * (end.longitude - start.longitude)
        
        // Создаем объект местоположения для точки проекции
        let nearestPoint = CLLocation(latitude: nearestLat, longitude: nearestLon)
        
        // Возвращаем расстояние от исходной точки до ее проекции на отрезок
        return location.distance(from: nearestPoint)
    }
    
    // Функция для нахождения ближайшей точки на сегменте
    private func findNearestPointOnSegment(_ point: CLLocationCoordinate2D,
                                          start: CLLocationCoordinate2D,
                                          end: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        // Вычисляем длину отрезка дороги в метрах
        let startLocation = CLLocation(latitude: start.latitude, longitude: start.longitude)
        let endLocation = CLLocation(latitude: end.latitude, longitude: end.longitude)
        let lineLength = startLocation.distance(from: endLocation)
        
        // Если отрезок имеет нулевую длину, возвращаем его начальную точку
        if lineLength <= 0.1 { // Минимальный порог 10 см для исключения ошибок вычислений
            return start
        }
        
        // Вычисляем параметр проекции t (от 0 до 1), где:
        // t = 0 соответствует начальной точке отрезка (start)
        // t = 1 соответствует конечной точке отрезка (end)
        // t = 0.5 соответствует середине отрезка
        // Проекция вычисляется через скалярное произведение векторов
        var t = ((point.latitude - start.latitude) * (end.latitude - start.latitude) +
                (point.longitude - start.longitude) * (end.longitude - start.longitude)) / 
                ((end.latitude - start.latitude) * (end.latitude - start.latitude) + 
                 (end.longitude - start.longitude) * (end.longitude - start.longitude))
        
        // Ограничиваем t значениями от 0 до 1, чтобы проекция лежала строго на отрезке
        t = max(0, min(1, t))
        
        // Вычисляем координаты проекции через линейную интерполяцию
        let projectedLat = start.latitude + t * (end.latitude - start.latitude)
        let projectedLon = start.longitude + t * (end.longitude - start.longitude)
        
        // Удостоверяемся, что проекция действительно лежит на отрезке
        // Расстояние от проекции до начальной и конечной точек не должно превышать длину отрезка
        let projectedPoint = CLLocationCoordinate2D(latitude: projectedLat, longitude: projectedLon)
        let projectedLocation = CLLocation(latitude: projectedLat, longitude: projectedLon)
        
        let distToStart = projectedLocation.distance(from: startLocation)
        let distToEnd = projectedLocation.distance(from: endLocation)
        
        // Проверка корректности проекции (точка должна лежать на отрезке)
        if distToStart + distToEnd <= lineLength * 1.001 { // Допускаем небольшую погрешность вычислений
            return projectedPoint
        } else {
            // Если проекция некорректна, выбираем ближайшую конечную точку отрезка
            return (distToStart <= distToEnd) ? start : end
        }
    }
    
    // Основной алгоритм привязки с учетом направления движения и улучшенной привязкой на поворотах
    func matchTrackWithErrorCorrection(gpsTrack: [TrackPoint], roadSegments: [RoadSegment], 
                                      maxDistance: Double = 50.0, 
                                      forceSnapToRoad: Bool = true,
                                      maxForceSnapDistance: Double = 200.0,
                                      removeDuplicates: Bool = true,
                                      fillGaps: Bool = true) -> [CLLocationCoordinate2D] {
        guard !gpsTrack.isEmpty else { return [] }
        guard !roadSegments.isEmpty else {
            print("Нет дорожных сегментов для сопоставления")
            return gpsTrack.map { $0.coordinate }
        }
        
        print("Начинаем сопоставление трека (\(gpsTrack.count) точек) с дорогами (\(roadSegments.count) сегментов)")
        print("Параметры: maxDistance=\(maxDistance)м, forceSnapToRoad=\(forceSnapToRoad), maxForceSnapDistance=\(maxForceSnapDistance)м, removeDuplicates=\(removeDuplicates), fillGaps=\(fillGaps)")
        let startTime = Date()
        
        // Ограничиваем количество точек трека для предотвращения зависаний
        let effectiveGpsTrack: [TrackPoint]
        if gpsTrack.count > 5000 {
            print("Слишком много точек GPS (\(gpsTrack.count)), ограничиваем до 5000")
            let strideValue = max(1, gpsTrack.count / 5000)
            var reducedTrack: [TrackPoint] = []
            for i in stride(from: 0, to: gpsTrack.count, by: strideValue) {
                reducedTrack.append(gpsTrack[i])
            }
            effectiveGpsTrack = reducedTrack
            print("Трек сокращен до \(effectiveGpsTrack.count) точек")
        } else {
            effectiveGpsTrack = gpsTrack
        }
        
        var matchedTrack: [CLLocationCoordinate2D] = []
        
        // Накопленные погрешности для каждой точки - ключевой элемент для правильного притягивания
        var cumulativeOffsets: [(Double, Double)] = []
        
        // Направление движения для оценки потенциальных дорог
        var lastDirection: (Double, Double) = (0.0, 0.0)
        
        // Индекс последнего сегмента для обеспечения непрерывности
        var lastMatchedSegmentIndex: Int? = nil
        
        // Прогресс-логирование для длинных треков
        let reportInterval = max(1, effectiveGpsTrack.count / 10)
        
        // Создаем индекс для быстрого поиска ближайших сегментов
        // Группируем сегменты по сетке для быстрого поиска
        print("Создаем пространственный индекс для \(roadSegments.count) сегментов")
        let gridSize: Double = 0.001 // примерно 100 метров
        var spatialIndex: [String: [Int]] = [:]
        
        for (index, segment) in roadSegments.enumerated() {
            let minLat = min(segment.start.latitude, segment.end.latitude)
            let maxLat = max(segment.start.latitude, segment.end.latitude)
            let minLon = min(segment.start.longitude, segment.end.longitude)
            let maxLon = max(segment.start.longitude, segment.end.longitude)
            
            // Округляем до сетки
            let minLatGrid = floor(minLat / gridSize) * gridSize
            let maxLatGrid = ceil(maxLat / gridSize) * gridSize
            let minLonGrid = floor(minLon / gridSize) * gridSize
            let maxLonGrid = ceil(maxLon / gridSize) * gridSize
            
            // Добавляем сегмент во все ячейки сетки, которые он пересекает
            for latGrid in stride(from: minLatGrid, through: maxLatGrid, by: gridSize) {
                for lonGrid in stride(from: minLonGrid, through: maxLonGrid, by: gridSize) {
                    let key = "\(latGrid):\(lonGrid)"
                    if spatialIndex[key] == nil {
                        spatialIndex[key] = []
                    }
                    spatialIndex[key]?.append(index)
                }
            }
        }
        
        // Предварительная обработка - вычисляем примерное направление трека
        let lookAheadDistance = min(5, effectiveGpsTrack.count / 10 + 1) // Смотрим на несколько точек вперед
        
        // Инициализируем массив накопленных погрешностей для всех точек
        cumulativeOffsets = Array(repeating: (0.0, 0.0), count: effectiveGpsTrack.count)
        
        // Обработка каждой точки трека
        for i in 0..<effectiveGpsTrack.count {
            // Проверка превышения времени выполнения
            if i % reportInterval == 0 {
                let currentTime = Date()
                let elapsedTime = currentTime.timeIntervalSince(startTime)
                print("Обработано \(i)/\(effectiveGpsTrack.count) точек за \(String(format: "%.2f", elapsedTime)) секунд")
                
                // Проверка на длительное время выполнения
                if elapsedTime > 20.0 && i < effectiveGpsTrack.count / 2 {
                    print("Предупреждение: сопоставление слишком долгое, пропускаем оставшиеся точки")
                    
                    // Применяем накопленную погрешность к оставшимся точкам без сопоставления
                    let lastOffset = i > 0 ? cumulativeOffsets[i-1] : (0.0, 0.0)
                    
                    for j in i..<effectiveGpsTrack.count {
                        let adjustedCoord = CLLocationCoordinate2D(
                            latitude: effectiveGpsTrack[j].coordinate.latitude + lastOffset.0,
                            longitude: effectiveGpsTrack[j].coordinate.longitude + lastOffset.1
                        )
                        matchedTrack.append(adjustedCoord)
                    }
                    break
                }
            }
            
            // Получаем накопленную погрешность до текущего момента
            let previousOffset = i > 0 ? cumulativeOffsets[i-1] : (0.0, 0.0)
            
            // Применяем накопленную погрешность к текущей точке
            let correctedCoordinate = CLLocationCoordinate2D(
                latitude: effectiveGpsTrack[i].coordinate.latitude + previousOffset.0,
                longitude: effectiveGpsTrack[i].coordinate.longitude + previousOffset.1
            )
            
            // Если есть предыдущие точки, вычисляем направление движения
            var direction: (Double, Double) = lastDirection
            
            if i > 0 {
                // Используем исходные координаты (без погрешности) для определения направления
                let prevPoint = effectiveGpsTrack[i-1].coordinate
                let currentPoint = effectiveGpsTrack[i].coordinate
                
                direction.0 = currentPoint.latitude - prevPoint.latitude
                direction.1 = currentPoint.longitude - prevPoint.longitude
                
                // Нормализуем направление
                let length = sqrt(direction.0 * direction.0 + direction.1 * direction.1)
                if length > 0 {
                    direction.0 /= length
                    direction.1 /= length
                    lastDirection = direction
                }
            }
            
            // Смотрим вперед для определения поворотов и будущего направления
            var lookAheadDirection: (Double, Double) = (0, 0)
            if i + lookAheadDistance < effectiveGpsTrack.count {
                // Используем исходные координаты для прогноза направления
                let futurePoint = effectiveGpsTrack[i + lookAheadDistance].coordinate
                let currentPoint = effectiveGpsTrack[i].coordinate
                
                lookAheadDirection.0 = futurePoint.latitude - currentPoint.latitude
                lookAheadDirection.1 = futurePoint.longitude - currentPoint.longitude
                
                // Нормализуем направление
                let length = sqrt(lookAheadDirection.0 * lookAheadDirection.0 + 
                                 lookAheadDirection.1 * lookAheadDirection.1)
                if length > 0 {
                    lookAheadDirection.0 /= length
                    lookAheadDirection.1 /= length
                }
            }
            
            // Используем пространственный индекс для быстрого поиска
            let latGrid = floor(correctedCoordinate.latitude / gridSize) * gridSize
            let lonGrid = floor(correctedCoordinate.longitude / gridSize) * gridSize
            
            // Ищем в ближайших ячейках сетки (расширяем радиус поиска для лучшего сопоставления)
            var nearbySegmentIndices = Set<Int>()
            
            // Расширенный поиск для точек, которые могут быть далеко от существующих дорог
            // Для первой точки или после потери дороги используем больший радиус
            let searchRadius = (i == 0 || lastMatchedSegmentIndex == nil) ? 3 : 2
            
            // Ищем в окрестности точки с радиусом searchRadius
            for dLat in -searchRadius...searchRadius {
                for dLon in -searchRadius...searchRadius {
                    let dLatDouble = Double(dLat)
                    let dLonDouble = Double(dLon)
                    let key = "\(latGrid + dLatDouble * gridSize):\(lonGrid + dLonDouble * gridSize)"
                    if let indices = spatialIndex[key] {
                        nearbySegmentIndices.formUnion(indices)
                    }
                }
            }
            
            // Если ничего не нашли, используем последний сегмент и его соседей
            if nearbySegmentIndices.isEmpty, let lastIdx = lastMatchedSegmentIndex {
                nearbySegmentIndices.insert(lastIdx)
                
                // Добавляем соседние сегменты для непрерывности
                let connected = getConnectedSegments(roadSegments, lastIdx)
                nearbySegmentIndices.formUnion(connected)
                
                // Проверяем соседей соседей для большей связности (на сложных перекрестках)
                if nearbySegmentIndices.count < 5 {
                    for connectedIdx in connected {
                        let secondLevelConnected = getConnectedSegments(roadSegments, connectedIdx)
                        nearbySegmentIndices.formUnion(secondLevelConnected)
                    }
                }
            }
            
            // Если всё еще ничего, делаем более широкий поиск
            if nearbySegmentIndices.isEmpty {
                // Для первой точки выполняем полный поиск
                if i == 0 {
                    print("Полный поиск для первой точки трека")
                    for idx in 0..<min(roadSegments.count, 1000) {
                        nearbySegmentIndices.insert(idx)
                    }
                } else {
                    // Для последующих точек используем выборочный поиск
                    let strideStep = max(1, roadSegments.count / 500)
                    for idx in stride(from: 0, to: roadSegments.count, by: strideStep) {
                        nearbySegmentIndices.insert(idx)
                    }
                }
            }
            
            // Получаем сегменты, связанные с предыдущим сегментом
            let connectedToLastSegment = lastMatchedSegmentIndex != nil ? 
                getConnectedSegments(roadSegments, lastMatchedSegmentIndex) : []
            
            // Если не удалось найти ближайший сегмент
            var closestPoint: CLLocationCoordinate2D?
            var closestSegmentIndex: Int? = nil
            var closestDistance = Double.infinity
            
            // Массив потенциальных сегментов с их рейтингами
            var candidateSegments: [(index: Int, distance: Double, score: Double)] = []
            
            // Разделяем поиск на две фазы:
            // 1. Предварительный отбор (дистанция, направление)
            // 2. Ранжирование и выбор лучшего сегмента
            
            // Предварительный отбор сегментов
            for segmentIndex in nearbySegmentIndices {
                let segment = roadSegments[segmentIndex]
                let distance = distanceFromPoint(correctedCoordinate,
                                              toLineSegment: segment.start,
                                              end: segment.end)
                
                // Отсеиваем слишком далекие сегменты
                if distance <= maxDistance * 2.0 {
                    let segmentDirection = getSegmentDirection(segment)
                    let directionMatch = dotProduct(direction, segmentDirection)
                    let futureDirectionMatch = dotProduct(lookAheadDirection, segmentDirection)
                    
                    // Проверка ограничений по направлению дороги
                    let directionAllowed = checkDirectionAllowed(segment, directionMatch)
                    
                    // Базовый скор для сегмента
                    var segmentScore = 1.0
                    
                    // Учитываем дистанцию (ближе - лучше)
                    segmentScore *= (maxDistance * 2.0 - distance) / (maxDistance * 2.0)
                    
                    // Учитываем совпадение направления (выше - лучше)
                    if directionMatch > 0 {
                        segmentScore *= (1.0 + directionMatch)
                    } else {
                        // Штрафуем за противоположное направление
                        segmentScore *= 0.5
                    }
                    
                    // Учитываем ограничения дороги
                    if !directionAllowed {
                        segmentScore *= 0.3  // Существенный штраф за нарушение правил движения
                    }
                    
                    // Для связанных с предыдущим сегментов добавляем бонус
                    if lastMatchedSegmentIndex != nil && 
                       connectedToLastSegment.contains(segmentIndex) {
                        segmentScore *= 1.5  // Бонус за связность
                    }
                    
                    // Добавляем в кандидаты
                    candidateSegments.append((segmentIndex, distance, segmentScore))
                }
            }
            
            // Если нашли сегменты-кандидаты, выбираем лучший
            if !candidateSegments.isEmpty {
                // Сортируем по скору (от высокого к низкому)
                candidateSegments.sort { $0.score > $1.score }
                
                // Выбираем лучший сегмент
                let bestCandidate = candidateSegments[0]
                closestSegmentIndex = bestCandidate.index
                closestDistance = bestCandidate.distance
                
                // Находим точку на сегменте
                let segment = roadSegments[bestCandidate.index]
                closestPoint = findNearestPointOnSegment(correctedCoordinate,
                                                       start: segment.start,
                                                       end: segment.end)
            }
            
            // Если нашли ближайшую точку на дороге
            if let matchedPoint = closestPoint, let segmentIndex = closestSegmentIndex {
                // Сохраняем индекс сегмента для связности
                lastMatchedSegmentIndex = segmentIndex
                
                // Вычисляем новую погрешность относительно скорректированной точки
                let newErrorLat = matchedPoint.latitude - correctedCoordinate.latitude
                let newErrorLon = matchedPoint.longitude - correctedCoordinate.longitude
                
                // Вычисляем накопленную погрешность для текущей точки
                // Добавляем новую погрешность к предыдущей накопленной
                let totalOffsetLat = previousOffset.0 + newErrorLat
                let totalOffsetLon = previousOffset.1 + newErrorLon
                
                // Сохраняем эту погрешность для применения к следующим точкам
                cumulativeOffsets[i] = (totalOffsetLat, totalOffsetLon)
                
                // Отладочный вывод для существенных погрешностей
                if abs(totalOffsetLat) > 0.0001 || abs(totalOffsetLon) > 0.0001 {
                    print("Точка \(i): накопленное смещение (\(totalOffsetLat), \(totalOffsetLon))")
                }
                
                // Добавляем притянутую точку в результат
                matchedTrack.append(matchedPoint)
            } else {
                // Сохраняем предыдущую накопленную погрешность без изменений
                cumulativeOffsets[i] = previousOffset
                
                // Если требуется принудительная привязка к дороге
                if forceSnapToRoad {
                    // Вместо использования скорректированной GPS-точки, найдем ближайший сегмент
                    // без учёта ограничений направления или расстояния
                    var absoluteClosestDistance = Double.infinity
                    var absoluteClosestPoint: CLLocationCoordinate2D? = nil
                    var absoluteClosestSegmentIndex: Int? = nil
                    
                    // Проверяем все сегменты в расширенном радиусе поиска
                    let extendedSearchRadius = 5 // Увеличиваем радиус поиска
                    var extendedSegmentIndices = Set<Int>()
                    
                    for dLat in -extendedSearchRadius...extendedSearchRadius {
                        for dLon in -extendedSearchRadius...extendedSearchRadius {
                            let dLatDouble = Double(dLat)
                            let dLonDouble = Double(dLon)
                            let key = "\(latGrid + dLatDouble * gridSize):\(lonGrid + dLonDouble * gridSize)"
                            if let indices = spatialIndex[key] {
                                extendedSegmentIndices.formUnion(indices)
                            }
                        }
                    }
                    
                    // Если все еще ничего не нашли, делаем выборочный поиск по всем сегментам
                    if extendedSegmentIndices.isEmpty {
                        // При полном сбое, возможно, индексацию надо проводить по-другому
                        print("Ошибка: не найдено сегментов в расширенном радиусе поиска. Использую полный поиск.")
                        let strideStep = max(1, roadSegments.count / 200)
                        for idx in stride(from: 0, to: roadSegments.count, by: strideStep) {
                            extendedSegmentIndices.insert(idx)
                        }
                    }
                    
                    // Найдем абсолютно ближайший сегмент без учета ограничений
                    for segmentIndex in extendedSegmentIndices {
                        let segment = roadSegments[segmentIndex]
                        let distance = distanceFromPoint(correctedCoordinate,
                                                      toLineSegment: segment.start,
                                                      end: segment.end)
                        
                        if distance < absoluteClosestDistance {
                            absoluteClosestDistance = distance
                            absoluteClosestPoint = findNearestPointOnSegment(correctedCoordinate,
                                                                          start: segment.start,
                                                                          end: segment.end)
                            absoluteClosestSegmentIndex = segmentIndex
                        }
                    }
                    
                    if let absolutePoint = absoluteClosestPoint, let absoluteIndex = absoluteClosestSegmentIndex {
                        // Проверяем, что расстояние не превышает максимально допустимое для принудительной привязки
                        if absoluteClosestDistance <= maxForceSnapDistance {
                            // Даже если сегмент далеко, мы всё равно привязываем точку к дороге
                            lastMatchedSegmentIndex = absoluteIndex
                            matchedTrack.append(absolutePoint)
                            
                            // Логируем информацию о дальней привязке
                            if absoluteClosestDistance > maxDistance {
                                print("Точка \(i): принудительная привязка к дороге на расстоянии \(String(format: "%.2f", absoluteClosestDistance)) м")
                            }
                        } else {
                            // Если найденная дорога слишком далеко, используем исходную точку
                            matchedTrack.append(correctedCoordinate)
                            print("Точка \(i): найденная дорога слишком далеко (\(String(format: "%.2f", absoluteClosestDistance)) м > \(maxForceSnapDistance) м)")
                        }
                    } else {
                        // В крайнем случае, если вообще ничего не найдено, используем GPS-точку
                        // Но это должно происходить только в исключительных случаях
                        matchedTrack.append(correctedCoordinate)
                        print("Точка \(i): не удалось найти ни одного дорожного сегмента поблизости")
                    }
                } else {
                    // Если принудительная привязка не требуется, используем скорректированную GPS-точку
                    matchedTrack.append(correctedCoordinate)
                }
            }
        }
        
        let endTime = Date()
        let totalTime = endTime.timeIntervalSince(startTime)
        print("Сопоставление трека завершено за \(String(format: "%.2f", totalTime)) секунд")
        
        // Считаем статистику
        var onRoadPoints = 0
        var offRoadPoints = 0
        
        for i in 0..<effectiveGpsTrack.count {
            if i < matchedTrack.count {
                let correctedCoordinate = CLLocationCoordinate2D(
                    latitude: effectiveGpsTrack[i].coordinate.latitude + cumulativeOffsets[i].0,
                    longitude: effectiveGpsTrack[i].coordinate.longitude + cumulativeOffsets[i].1
                )
                
                // Проверяем, совпадает ли точка с скорректированной координатой
                let matchedPoint = matchedTrack[i]
                if matchedPoint.latitude == correctedCoordinate.latitude && 
                   matchedPoint.longitude == correctedCoordinate.longitude {
                    offRoadPoints += 1
                } else {
                    onRoadPoints += 1
                }
            }
        }
        
        print("Статистика: \(onRoadPoints) точек на дороге, \(offRoadPoints) точек вне дороги")
        
        if !cumulativeOffsets.isEmpty {
            let finalOffset = cumulativeOffsets.last!
            print("Финальное накопленное смещение: (\(finalOffset.0), \(finalOffset.1))")
        }
        
        // Удаляем дубликаты точек, если это необходимо
        var finalTrack = matchedTrack
        if removeDuplicates {
            finalTrack = removeDuplicatePoints(matchedTrack)
            print("Удалено \(matchedTrack.count - finalTrack.count) дублирующихся точек")
        }
        
        // Заполняем пропуски в треке, если это необходимо
        if fillGaps && finalTrack.count > 1 {
            finalTrack = fillTrackGaps(finalTrack)
        }
        
        // Возвращаем результат без дополнительного сглаживания
        return finalTrack
    }
    
    // Находит сегменты, соединенные с указанным
    private func getConnectedSegments(_ segments: [RoadSegment], _ segmentIndex: Int?) -> [Int] {
        guard let segmentIndex = segmentIndex, segmentIndex < segments.count else {
            return []
        }
        
        let currentSegment = segments[segmentIndex]
        var connectedIndices: [Int] = []
        
        // Максимальное расстояние для определения соединенных сегментов (в метрах)
        // Увеличиваем до 50 метров для лучшей связности сети дорог
        let maxConnectionDistance: Double = 50.0
        
        // Вычисляем направление текущего сегмента для проверки согласованности направлений
        let currentDirection = getSegmentDirection(currentSegment)
        
        // Определяем, в каком направлении мы двигаемся по текущему сегменту
        let movingForward = currentSegment.isOneway ? currentSegment.forwardDirection : true
        
        // Каждый сегмент имеет две точки подключения - start и end
        // Если мы двигаемся по сегменту от start к end (forward), то следующий сегмент должен подключаться к end
        // Если мы двигаемся по сегменту от end к start (backward), то следующий сегмент должен подключаться к start
        
        // Определяем точку выхода из текущего сегмента
        let exitPoint = movingForward ? currentSegment.end : currentSegment.start
        
        // Кэшируем для ускорения
        let exitPointLocation = CLLocation(latitude: exitPoint.latitude, longitude: exitPoint.longitude)
        
        // Приоритизируем результаты
        var prioritizedConnections: [(index: Int, distance: Double, angleDiff: Double)] = []
        
        // Проверяем все сегменты (кроме текущего) на соединение
        for (index, segment) in segments.enumerated() {
            if index == segmentIndex { continue } // Пропускаем текущий сегмент
            
            // Проверяем расстояния до обоих концов сегмента
            let startLocation = CLLocation(latitude: segment.start.latitude, longitude: segment.start.longitude)
            let endLocation = CLLocation(latitude: segment.end.latitude, longitude: segment.end.longitude)
            
            let distToStart = exitPointLocation.distance(from: startLocation)
            let distToEnd = exitPointLocation.distance(from: endLocation)
            
            // Если хотя бы один конец достаточно близок
            if min(distToStart, distToEnd) <= maxConnectionDistance {
                // Определяем, какой конец ближе (в него будем входить)
                let isStartCloser = distToStart <= distToEnd
                
                // Проверяем ограничения движения по сегменту
                let canEnterSegment: Bool
                
                if isStartCloser {
                    // Если входим в начало сегмента, то нужно двигаться вперед по нему
                    canEnterSegment = !segment.isOneway || segment.forwardDirection
                } else {
                    // Если входим в конец сегмента, то нужно двигаться назад по нему
                    canEnterSegment = !segment.isOneway || !segment.forwardDirection
                }
                
                // Если движение по сегменту разрешено, проверяем угол между сегментами
                if canEnterSegment {
                    // Вычисляем направление следующего сегмента
                    let nextSegmentDirection = getSegmentDirection(segment)
                    
                    // Если входим в конец сегмента, инвертируем направление
                    let effectiveDirection = isStartCloser ? nextSegmentDirection : (-nextSegmentDirection.0, -nextSegmentDirection.1)
                    
                    // Вычисляем косинус угла между направлениями (от -1 до 1)
                    let cosAngle = dotProduct(currentDirection, effectiveDirection)
                    
                    // Добавляем в приоритетный список с учетом расстояния и угла
                    prioritizedConnections.append((
                        index: index,
                        distance: min(distToStart, distToEnd),
                        angleDiff: cosAngle
                    ))
                }
            }
        }
        
        // Если нашли соединения, сортируем по приоритету и возвращаем лучшие
        if !prioritizedConnections.isEmpty {
            // Сортируем: сначала по углу (от большего к меньшему - чтобы прямое направление было выше),
            // затем по расстоянию (от меньшего к большему)
            prioritizedConnections.sort { (a, b) -> Bool in
                if abs(a.angleDiff - b.angleDiff) > 0.2 {
                    return a.angleDiff > b.angleDiff
                }
                return a.distance < b.distance
            }
            
            // Лимитируем количество возвращаемых сегментов
            let maxConnectedSegments = 20
            connectedIndices = prioritizedConnections.prefix(maxConnectedSegments).map { $0.index }
        }
        
        return connectedIndices
    }
    
    // Проверяет, разрешено ли движение в текущем направлении для данного сегмента
    private func checkDirectionAllowed(_ segment: RoadSegment, _ directionMatch: Double) -> Bool {
        // Если дорога не односторонняя, движение разрешено в обоих направлениях
        if !segment.isOneway {
            return true
        }
        
        // Определяем, двигаемся ли мы в направлении сегмента или против него
        let movingForward = directionMatch > 0
        
        // Для односторонней дороги:
        // - Если forwardDirection = true, разрешено движение от start к end (movingForward = true)
        // - Если forwardDirection = false, разрешено движение от end к start (movingForward = false)
        return segment.forwardDirection == movingForward
    }
    
    // Вычисляет направление сегмента
    private func getSegmentDirection(_ segment: RoadSegment) -> (Double, Double) {
        let deltaLat = segment.end.latitude - segment.start.latitude
        let deltaLon = segment.end.longitude - segment.start.longitude
        
        // Нормализуем направление
        let length = sqrt(deltaLat * deltaLat + deltaLon * deltaLon)
        if length > 0 {
            return (deltaLat / length, deltaLon / length)
        }
        
        return (0, 0)
    }
    
    // Вычисляет скалярное произведение двух векторов (косинус угла между ними)
    private func dotProduct(_ v1: (Double, Double), 
                           _ v2: (Double, Double)) -> Double {
        return v1.0 * v2.0 + v1.1 * v2.1
    }
    
    // Вычисляет расстояние между двумя координатами
    private func calculateDistance(coord1: CLLocationCoordinate2D, coord2: CLLocationCoordinate2D) -> Double {
        let location1 = CLLocation(latitude: coord1.latitude, longitude: coord1.longitude)
        let location2 = CLLocation(latitude: coord2.latitude, longitude: coord2.longitude)
        return location1.distance(from: location2)
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
    
    // Удаляет дублирующиеся последовательные точки из трека
    private func removeDuplicatePoints(_ track: [CLLocationCoordinate2D], 
                                      minDistanceThreshold: Double = 0.1) -> [CLLocationCoordinate2D] {
        guard track.count > 1 else { return track }
        
        var result: [CLLocationCoordinate2D] = [track[0]]
        
        for i in 1..<track.count {
            let prevPoint = result.last!
            let currentPoint = track[i]
            
            // Вычисляем расстояние между точками
            let distance = calculateDistance(coord1: prevPoint, coord2: currentPoint)
            
            // Добавляем точку только если она достаточно отличается от предыдущей
            if distance > minDistanceThreshold {
                result.append(currentPoint)
            }
        }
        
        return result
    }
    
    // Заполняет пропуски в треке, добавляя промежуточные точки
    private func fillTrackGaps(_ track: [CLLocationCoordinate2D], 
                             maxGapDistance: Double = 50.0,
                             maxPointsToAdd: Int = 5) -> [CLLocationCoordinate2D] {
        guard track.count > 1 else { return track }
        
        var filledTrack: [CLLocationCoordinate2D] = []
        var gapsFound = 0
        var pointsAdded = 0
        
        // Добавляем первую точку
        filledTrack.append(track[0])
        
        for i in 1..<track.count {
            let prevPoint = track[i-1]
            let currentPoint = track[i]
            
            // Вычисляем расстояние между точками
            let distance = calculateDistance(coord1: prevPoint, coord2: currentPoint)
            
            // Если расстояние больше порога, добавляем промежуточные точки
            if distance > maxGapDistance {
                gapsFound += 1
                
                // Вычисляем направление движения между точками
                let direction = getDirectionVector(from: prevPoint, to: currentPoint)
                
                // Определяем количество точек для добавления (не больше maxPointsToAdd)
                // и адаптивно зависит от расстояния
                let numPointsToAdd = min(maxPointsToAdd, max(1, Int(distance / maxGapDistance)))
                
                // Добавляем промежуточные точки, равномерно распределенные по прямой
                for j in 1...numPointsToAdd {
                    let fraction = Double(j) / Double(numPointsToAdd + 1)
                    
                    // Интерполяция между предыдущей и текущей точками
                    let interpolatedLat = prevPoint.latitude + fraction * (currentPoint.latitude - prevPoint.latitude)
                    let interpolatedLon = prevPoint.longitude + fraction * (currentPoint.longitude - prevPoint.longitude)
                    
                    let interpolatedPoint = CLLocationCoordinate2D(
                        latitude: interpolatedLat,
                        longitude: interpolatedLon
                    )
                    
                    filledTrack.append(interpolatedPoint)
                    pointsAdded += 1
                }
            }
            
            // Добавляем текущую точку
            filledTrack.append(currentPoint)
        }
        
        if gapsFound > 0 {
            print("Найдено \(gapsFound) пропусков в треке, добавлено \(pointsAdded) промежуточных точек")
        }
        
        return filledTrack
    }
    
    // Вычисляет вектор направления между двумя точками
    private func getDirectionVector(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> (Double, Double) {
        let deltaLat = end.latitude - start.latitude
        let deltaLon = end.longitude - start.longitude
        
        // Нормализуем вектор
        let length = sqrt(deltaLat * deltaLat + deltaLon * deltaLon)
        if length > 0 {
            return (deltaLat / length, deltaLon / length)
        }
        
        return (0, 0)
    }
}
