import Foundation
import CoreLocation
import SwiftUI

struct Track: Identifiable {
    let id = UUID()
    let name: String
    let coordinates: [CLLocationCoordinate2D]
    let color: Color
    
    static let colors: [Color] = [.red, .blue]
} 
