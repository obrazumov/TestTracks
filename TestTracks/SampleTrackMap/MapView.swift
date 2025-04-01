import SwiftUI
import MapKit

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
                model: model,
                tracks: filteredTracks
            )
            .edgesIgnoringSafeArea(.all)
            .onAppear {
                model.loadTracks()
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
            
            // Легенда карты
            VStack {
                Spacer()
                
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
    var model: MapModel
    var tracks: [Track]
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        
        // Настройка отображения карты
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.showsUserLocation = false
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Обновление положения карты при изменении положения
        if let region = position.region {
            mapView.setRegion(region, animated: true)
        }
        
        // Обновляем треки
        updateTracks(mapView)
        
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
    
    private func updateRoadsOverlays(_ mapView: MKMapView) {
        // Удаляем все предыдущие оверлеи дорог
        let existingRoadOverlays = mapView.overlays.filter { $0 is RoadsOverlay }
        if !existingRoadOverlays.isEmpty {
            print("Удаляем \(existingRoadOverlays.count) существующих оверлеев дорог")
            mapView.removeOverlays(existingRoadOverlays)
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
            }
            
            // Для неизвестных типов используем стандартный рендерер
            return MKOverlayRenderer(overlay: overlay)
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
