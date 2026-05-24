import Foundation

struct AudioAppRule: Codable, Equatable {
    let bundleIdentifier: String
    var volume: Double
    var isMuted: Bool
}
