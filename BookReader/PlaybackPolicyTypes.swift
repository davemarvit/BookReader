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
