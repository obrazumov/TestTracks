//
//  NMEAData.swift
//  TestTracks
//
//  Created by Dmitriy Obrazumov on 13/03/2025.
//
import MapKit

struct NMEAData {
    let coordinate: CLLocationCoordinate2D
    let timestamp: Date
    let utcTime: String
    let date: String
    let isValid: Bool
}
