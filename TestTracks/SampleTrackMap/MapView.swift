import SwiftUI
import MapKit
import ObjectiveC

// Ключи для Associated Objects
private struct AssociatedKeys {
    static var segmentType = "segmentType"
    static var candidateColor = "candidateColor"
}

// Класс для отображения кандидатов на карте
class TestCandidateAnnotation: NSObject, MKAnnotation {
    let candidate: TestCandidat
    var coordinate: CLLocationCoordinate2D {
        candidate.trackPoint.coordinate
    }
    
    init(candidate: TestCandidat) {
        self.candidate = candidate
        super.init()
    }
}

// Класс для отображения сегмента дороги с цветом из TestCandidate
class CandidatePolyline: MKPolyline {
    var segmentType: SegmentType = .projection
    var candidateColor: UIColor = .red
    
    enum SegmentType {
        case roadSegment
        case projection
    }
}

struct MapView: View {
    @ObservedObject private var model: MapModel = .init()
    @State private var showConnectionLines = false
    @State private var showAllRoads = true
    
    var body: some View {
        ZStack {
            // Используем MapViewRepresentable для поддержки оверлеев
            MapViewRepresentable(
                position: $model.position,
                showAllRoads: $showAllRoads,
                candidates: $model.candidates,
                model: model,
                tracks: filteredTracks
            )
            .edgesIgnoringSafeArea(.all)
            .onAppear {
                Task {
                    await model.loadTracks()
                }
            }
            
            // Улучшенный индикатор загрузки с процентами
            if model.isLoading {
                Color.black.opacity(0.3)
                    .edgesIgnoringSafeArea(.all)
                
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    
                    Text("Загрузка карты")
                        .foregroundColor(.white)
                        .font(.headline)
                        .padding(.top, 10)
                    
                    // Отображение текущего статуса загрузки
                    Text(model.loadingProgress)
                        .foregroundColor(.white)
                        .font(.subheadline)
                        .padding(.top, 5)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                    
                    // Отображение текущей статистики
                    if !model.roads.isEmpty {
                        Text("Дороги: \(model.roads.count)")
                            .foregroundColor(.white)
                            .font(.caption)
                            .padding(.top, 10)
                        
                        if !model.tracks.isEmpty {
                            Text("Треки: \(model.tracks.filter { !$0.name.hasPrefix("connection_") }.count)")
                                .foregroundColor(.white)
                                .font(.caption)
                        }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.7))
                )
            }
            
            // Индикатор прогресса обработки
            if model.isProcessing {
                VStack {
                    Text("Обработка точек трека")
                        .foregroundColor(.white)
                        .font(.headline)
                    
                    // Отображаем процент выполнения и количество обработанных точек
                    HStack {
                        let processedPoints = Int(Float(model.trackPointCount) * model.processingProgress)
                        let totalPoints = model.trackPointCount
                        Text("\(processedPoints)/\(totalPoints) точек")
                            .foregroundColor(.white)
                            .font(.caption)
                        
                        Spacer().frame(width: 10)
                        
                        Text("(\(Int(model.processingProgress * 100))%)")
                            .foregroundColor(.white)
                            .font(.subheadline)
                            .bold()
                    }
                    .padding(.top, 2)
                    
                    // Визуальный прогресс-бар
                    ProgressView(value: model.processingProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        .frame(width: 200)
                        .padding(.top, 5)
                    
                    // Кнопка отмены обработки
                    Button(action: {
                        model.cancelProcessing()
                    }) {
                        Text("Отмена")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.red))
                    }
                    .padding(.top, 10)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.7))
                )
                .padding()
                .position(x: UIScreen.main.bounds.width / 2, y: 100)
            }
            
            // Легенда карты
            VStack {
                Spacer()
                HStack {
                    Button("Next") {
                        Task {
                            await model.next()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("All") {
                        Task {
                            await model.all()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isProcessing) // Блокируем кнопку во время обработки
                    
                    Button("Фильтр") {
                        model.visualizeFilteredRoadSegments()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple) // Фиолетовый цвет для кнопки фильтрации
                    .disabled(model.isProcessing) // Блокируем кнопку во время обработки
                    
                    Button("Сброс") {
                        model.resetRoadSegments()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange) // Оранжевый цвет для кнопки сброса
                    .disabled(model.isProcessing) // Блокируем кнопку во время обработки
                }
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Rectangle()
                                .fill(Color.blue)
                                .frame(width: 30, height: 3)
                            Text("Используемые дороги")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                        
                        HStack {
                            Rectangle()
                                .fill(Color.gray.opacity(0.5))
                                .frame(width: 30, height: 1.5)
                            Text("Остальные дороги")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                        
                        HStack {
                            Rectangle()
                                .fill(Color.red)
                                .frame(width: 30, height: 3)
                            Text("GPS-трек")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                        
                        HStack {
                            Rectangle()
                                .fill(Color.green)
                                .frame(width: 30, height: 3)
                            Text("Скорректированный трек")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                        
                        HStack {
                            Rectangle()
                                .fill(Color.purple)
                                .frame(width: 30, height: 3)
                            Text("Отфильтрованные сегменты")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                        
                        Toggle("Показать соединения", isOn: $showConnectionLines)
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.top, 5)
                        
                        Toggle("Показать все дороги", isOn: $showAllRoads)
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.top, 2)
                    }
                }
                .padding()
                .background(Color.black.opacity(0.6))
                .cornerRadius(10)
                .padding()
            }
        }
    }
    
    // Фильтруем треки для показа/скрытия соединительных линий
    private var filteredTracks: [Track] {
        return model.tracks.filter { track in
            if track.name.hasPrefix("connection_") {
                return showConnectionLines
            }
            return true
        }
    }
}

// Адаптер для использования UIKit MapView с оверлеями
struct MapViewRepresentable: UIViewRepresentable {
    @Binding var position: MapCameraPosition
    @Binding var showAllRoads: Bool
    @Binding var candidates: [TestCandidat]
    var model: MapModel
    var tracks: [Track]
    // Отслеживаем изменения в дорожных сегментах, чтобы обновлять карту
    @State private var lastRoadSegmentsCount: Int = 0
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.mapType = .satelliteFlyover
        // Настройка отображения карты
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.showsUserLocation = false
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Обновление положения карты при изменении положения
        if let region = position.region,
           mapView.overlays.filter({ $0 is TrackPolyline }).isEmpty {
            mapView.setRegion(region, animated: true)
        }
        
        // Проверяем, изменились ли roadSegments
//        let currentSegmentsCount = model.roadSegments.count
//        if currentSegmentsCount != lastRoadSegmentsCount {
//            // Обновляем счетчик сегментов
//            lastRoadSegmentsCount = currentSegmentsCount
//            // Полное обновление оверлеев дорог для отображения новых сегментов
//            let existingRoadOverlays = mapView.overlays.filter { $0 is RoadsOverlay }
//            if !existingRoadOverlays.isEmpty {
//                mapView.removeOverlays(existingRoadOverlays)
//            }
//        }
        
        // Обновляем треки
        updateTracks(mapView)
        
        updateCandidates(mapView)
        // Обновляем дороги через оверлеи
        updateRoadsOverlays(mapView)
    }
    
    private func updateTracks(_ mapView: MKMapView) {
        // Удаляем все предыдущие треки
        let existingTrackOverlays = mapView.overlays.filter { $0 is TrackPolyline }
        mapView.removeOverlays(existingTrackOverlays)
        
        // Добавляем новые треки
        for track in tracks {
            let polyline = TrackPolyline(coordinates: track.coordinates, count: track.coordinates.count)
            polyline.trackName = track.name
            polyline.color = UIColor(track.color)
            mapView.addOverlay(polyline)
        }
    }
    private func updateCandidates(_ mapView: MKMapView) {
        // Удаляем все предыдущие аннотации кандидатов и оверлеи сегментов
        let existingAnnotations = mapView.annotations.filter { $0 is TestCandidateAnnotation }
        let existingPolylines = mapView.overlays.filter { 
            $0 is CandidatePolyline
        }
        mapView.removeAnnotations(existingAnnotations)
        mapView.removeOverlays(existingPolylines)
        
        // Добавляем новые аннотации и оверлеи для каждого кандидата
        for candidate in candidates {
            // Добавляем аннотацию кандидата
            let annotation = TestCandidateAnnotation(candidate: candidate)
            mapView.addAnnotation(annotation)
            
            // Добавляем оверлей сегмента дороги
            for segment in candidate.candidates {
                // Создаем полилинию для сегмента дороги
                let segmentPolyline = createCandidatePolyline(
                    coordinates: [segment.start, segment.end],
                    type: .roadSegment,
                    color: candidate.color
                )
                mapView.addOverlay(segmentPolyline, level: .aboveRoads)
                
                // Рисуем линию от точки до проекции
                let projectionPolyline = createCandidatePolyline(
                    coordinates: [candidate.trackPoint.coordinate, candidate.newPoint],
                    type: .projection,
                    color: candidate.color
                )
                mapView.addOverlay(projectionPolyline, level: .aboveRoads)
            }
        }
        mapView.setNeedsDisplay()
    }
    
    // Вспомогательный метод для создания CandidatePolyline
    private func createCandidatePolyline(coordinates: [CLLocationCoordinate2D], type: CandidatePolyline.SegmentType, color: UIColor) -> MKPolyline {
        let polyline = CandidatePolyline(coordinates: coordinates, count: coordinates.count)
        polyline.candidateColor = color
        polyline.segmentType = type
        return polyline
    }
    
    private func updateRoadsOverlays(_ mapView: MKMapView) {
        // Проверяем, изменились ли дорожные сегменты с момента последнего обновления
        let roadsNeedUpdate = !model.roadSegmentsForDisplay.isEmpty
        
        // Удаляем все предыдущие оверлеи дорог если нужно обновление
        let existingRoadOverlays = mapView.overlays.filter { $0 is RoadsOverlay }
        if roadsNeedUpdate && !existingRoadOverlays.isEmpty {
            mapView.removeOverlays(existingRoadOverlays)
        } else if !existingRoadOverlays.isEmpty && !roadsNeedUpdate {
            // Если оверлеи уже есть и обновление не требуется, выходим
            return
        }
        
        // Добавляем новый оверлей дорог в зависимости от showAllRoads
        if showAllRoads, let overlay = model.roadsOverlay {
            print("Добавляем оверлей всех дорог: \((overlay as! RoadsOverlay).roads.count) дорог")
            
            // Добавляем оверлей в начало списка, чтобы он был под треками
            mapView.insertOverlay(overlay, at: 0)
            
            // Заставляем карту перерисоваться
            mapView.setNeedsDisplay()
            
            print("Текущие оверлеи на карте после добавления: \(mapView.overlays.count)")
        } else if let overlay = model.usedRoadsOverlay {
            print("Добавляем оверлей используемых дорог: \((overlay as! RoadsOverlay).roads.filter { $0.isUsedByTrack }.count) дорог")
            
            // Добавляем оверлей в начало списка, чтобы он был под треками
            mapView.insertOverlay(overlay, at: 0)
            
            // Заставляем карту перерисоваться
            mapView.setNeedsDisplay()
            
            print("Текущие оверлеи на карте после добавления: \(mapView.overlays.count)")
        } else {
            print("ПРЕДУПРЕЖДЕНИЕ: Нет доступных оверлеев дорог для отображения")
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // Координатор для делегатов карты
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewRepresentable
        
        init(_ parent: MapViewRepresentable) {
            self.parent = parent
        }
        
        // Создание рендереров для различных типов оверлеев
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let trackOverlay = overlay as? TrackPolyline {
                let renderer = MKPolylineRenderer(overlay: trackOverlay)
                renderer.strokeColor = trackOverlay.color
                
                if trackOverlay.trackName == "validTrack" {
                    renderer.lineWidth = 3
                } else if trackOverlay.trackName.hasPrefix("connection_") {
                    renderer.lineWidth = 1
                } else {
                    renderer.lineWidth = 3
                }
                
                return renderer
            } else if let roadsOverlay = overlay as? RoadsOverlay {
                return RoadsOverlayRenderer(overlay: roadsOverlay)
            } else if let candidatesOverlay = overlay as? CandidatePolyline {
                let renderer = MKPolylineRenderer(overlay: overlay)
                renderer.strokeColor = candidatesOverlay.candidateColor
                switch candidatesOverlay.segmentType {
                case .projection:
                    renderer.lineWidth = 1.5
                    renderer.lineDashPattern = [2, 2]
                case .roadSegment:
                    renderer.lineWidth = 3
                    renderer.strokeColor = .random()
                }
                return renderer
            } else {
                // Для неизвестных типов используем стандартный рендерер
                return MKOverlayRenderer(overlay: overlay)
            }
        }
    }
}

// Кастомный класс для полилиний треков с дополнительными свойствами
class TrackPolyline: MKPolyline {
    var trackName: String = ""
    var color: UIColor = .red
}

#Preview {
    MapView()
} 
