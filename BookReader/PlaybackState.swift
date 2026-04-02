import Foundation

enum PlaybackMode {
    case basic
    case enhanced
}

enum EnhancedAvailability {
    case notIncluded
    case available
    case temporarilyUnavailable
    case limitReached
}

struct PlaybackState: Equatable {
    let mode: PlaybackMode
    let availability: EnhancedAvailability 
    
    var bannerText: String {
        switch (mode, availability) {
        case (.enhanced, _):
            return "Enhanced Audio"
        case (.basic, .available):
            return "Basic · Enhanced Available"
        case (.basic, .temporarilyUnavailable):
            return "Basic · Enhanced Temporarily Unavailable"
        case (.basic, .limitReached):
            return "Basic · Enhanced audio limit reached"
        case (.basic, .notIncluded):
            return "Basic Audio"
        }
    }
}
