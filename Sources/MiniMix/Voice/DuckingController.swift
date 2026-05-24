import Foundation

enum DuckingReason: Equatable {
    case voiceInput
}

protocol DuckingCoordinating {
    func beginDucking(reason: DuckingReason)
    func endDucking(reason: DuckingReason)
}
