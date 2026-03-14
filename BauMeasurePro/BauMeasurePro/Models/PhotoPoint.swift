import Foundation
import CoreGraphics

struct PhotoPoint: Identifiable, Codable, Equatable {
    var id = UUID()
    var x: Double
    var y: Double
    var distance: Double
}
