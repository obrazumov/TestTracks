//
//  MapModel.swift
//  TestTracks
//
//  Created by Dmitriy Obrazumov on 13/03/2025.
//

import Foundation
import _MapKit_SwiftUI

enum TrackType: CaseIterable {
    case road
    case route
    
    var fileName: String {
        switch self {
        case .road:
            return "raw_track.nmea"
        case .route:
            return "output_track.nmea"
        }
    }
}

final class MapModel: ObservableObject {
    let coordinateConverter: CoordinateConverter = .init()
    let mapMatcher: MapMatcher = .init()
    @Published var tracks: [Track] = []
    @Published var position: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    ))
    private var roadSegments: [RoadSegment] = []
    
    func loadTracks() {
//let trackFiles = [/*"testcsv.csv", */"raw_track.nmea", "output_track.nmea"]
        
        for (index, trackType) in TrackType.allCases.enumerated() {
            if let filePath = Bundle.main.path(forResource: trackType.fileName, ofType: nil) {
                let fileURL = URL(fileURLWithPath: filePath)
                let coordinates: [CLLocationCoordinate2D]
                var trackPoints: [TrackPoint] = []
                if fileURL.pathExtension.lowercased() == "nmea" {
                    let data = TrackParser.parseNMEAFile(fileURL)
                    trackPoints = data.map({ TrackPoint(coordinate: $0.coordinate, timestamp: $0.timestamp)})
                    coordinates = trackPoints.map({ $0.coordinate })
                } else if fileURL.pathExtension.lowercased() == "csv" {
                    coordinates = TrackParser.parseCSVFile(fileURL).map({ $0.coordinate })
                } else {
                    continue
                }
                
                switch trackType {
                case.road:
                    roadSegments = coordinateConverter.convertToRoadSegments(coordinates: coordinates)
                case .route:
                    let mapMatcherTrack = mapMatcher.matchTrackWithErrorCorrection(gpsTrack: trackPoints, roadSegments: roadSegments)
                    tracks.append(Track(
                        name: "validTrack",
                        coordinates: mapMatcherTrack.map({ CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }),
                        color: .green))
                                  
                }
                
                if !coordinates.isEmpty {
                    let track = Track(
                        name: fileURL.deletingPathExtension().lastPathComponent,
                        coordinates: coordinates,
                        color: Track.colors[index % Track.colors.count]
                    )
                    tracks.append(track)
                }
            }
        }
        
        // Set the map region to show all tracks
        if let firstTrack = tracks.first {
            position = .region(MKCoordinateRegion(
                center: firstTrack.coordinates[0],
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)))
        }
        
    }
}
