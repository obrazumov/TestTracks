//
//  TrackData.swift
//  TestTracks
//
//  Created by Dmitriy Obrazumov on 13/03/2025.
//
import MapKit

struct TrackData {
    let coordinate: CLLocationCoordinate2D
    let timestampMs: Int
    let headingTrueRad: Double
    let headingEstRad: Double?
    let dRmeters: Double?
}
