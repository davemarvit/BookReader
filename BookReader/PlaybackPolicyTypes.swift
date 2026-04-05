import Foundation

/// Represents the high-level voice playback engine mode.
enum VoiceMode {
    case premium
    case standard
}

/// Represents the current monetization entitlement status for premium network TTS.
enum PremiumEntitlementState {
    case allowed
    case requiresDecision
    case standardOnly
    case blocked
}

/// Represents the user's explicit choice when presented with a monetization or playback gate.
enum PlaybackGateChoice {
    case premium
    case standard
    case cancel
}

/// Categorizes the origin of a playback intent to provide context for analytics and gate behavior.
enum PlaybackIntentSource {
    case playButton
    case remoteCommand
    case sliderResume
    case paragraphTapResume
    case tocResume
    case skipResume
    case programmaticResume
    case modeSwitchRestart
    case systemForcedFallback
}

/// Represents the explicit reason behind a voice mode switch
enum VoiceSwitchIntent {
    case userInitiated
    case systemForcedFallback
    case systemRecovery
}

/// Encapsulates a suspended playback request waiting for user action (e.g., agreeing to consume a credit).
struct PendingPlaybackGate: Identifiable, Equatable {
    let id = UUID()
    let source: PlaybackIntentSource
    let paragraphIndex: Int
    let requestedMode: VoiceMode
}

enum Plan: String, Codable, CaseIterable {
    case free
    case reader
    case avidReader
    
    var displayName: String {
        switch self {
        case .free: return "Free"
        case .reader: return "Reader"
        case .avidReader: return "Avid Reader"
        }
    }
}

struct PlanCapabilities {
    let maxPlaybackSpeed: Double
    let maxBooks: Int?   // nil = unlimited
    let enhancedAvailable: Bool
    let monthlyPremiumMinutes: Double? // nil = unlimited
}

extension Plan {
    var capabilities: PlanCapabilities {
        switch self {
        case .free:
            return PlanCapabilities(
                maxPlaybackSpeed: 1.5,
                maxBooks: 10,
                enhancedAvailable: true,
                monthlyPremiumMinutes: 0.1
            )
        case .reader:
            return PlanCapabilities(
                maxPlaybackSpeed: 4.0,
                maxBooks: nil,
                enhancedAvailable: true,
                monthlyPremiumMinutes: 600
            )
        case .avidReader:
            return PlanCapabilities(
                maxPlaybackSpeed: 4.0,
                maxBooks: nil,
                enhancedAvailable: true,
                monthlyPremiumMinutes: 1500
            )
        }
    }
}
