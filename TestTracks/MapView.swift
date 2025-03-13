import SwiftUI
import MapKit

struct MapView: View {
    @ObservedObject private var model: MapModel = .init()
    
    var body: some View {
        Map(position: $model.position) {
            ForEach(model.tracks) { track in
                MapPolyline(coordinates: track.coordinates)
                    .stroke(track.color, lineWidth: track.name == "validTrack" ? 2 : 3)
            }
        }
        .onAppear {
            model.loadTracks()
        }
    }
}

#Preview {
    MapView()
} 
