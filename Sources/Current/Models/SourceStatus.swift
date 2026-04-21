import Foundation
import SwiftUI

enum SourceAvailability: Equatable {
    case unavailable       // tool not found on PATH
    case disabled          // turned off in preferences
    case available         // ready
}

struct SourceState: Identifiable, Equatable {
    let id: String                 // "brew", "npm", ...
    let displayName: String
    let iconSystemName: String
    let tint: Color
    var availability: SourceAvailability
    var itemCount: Int
}
