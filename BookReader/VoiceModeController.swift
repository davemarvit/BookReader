// VoiceModalController.swift

import Foundation
import Combine

/// Manages the currently active voice mode, cleanly integrating with SettingsManager and delaying safe transitions to paragraph boundaries.
final class VoiceModeController: ObservableObject {
    @Published private(set) var requestedMode: VoiceMode
    @Published private(set) var activeMode: VoiceMode
    private var pendingMode: VoiceMode? = nil

    init() {
        let defaultMode = SettingsManager.shared.preferredVoiceMode
        self.requestedMode = defaultMode
        self.activeMode = defaultMode
    }

    /// Reads the global preferred settings and aligns the requested mode.
    func syncRequestedModeFromSettings() {
        requestedMode = SettingsManager.shared.preferredVoiceMode
    }

    /// Queues or instantly applies a mode change depending on intent and playback state.
    func requestModeSwitch(_ mode: VoiceMode, intent: VoiceSwitchIntent, isPlaying: Bool) {
        requestedMode = mode
        
        switch intent {
        case .userInitiated:
            // Manual switches happen immediately; they do not wait for boundaries
            activeMode = mode
            pendingMode = nil
            if mode == .premium {
                isPremiumTemporarilyUnavailable = false // Clear blocks upon manual re-engagement
            }
            
        case .systemForcedFallback:
            // System switches wait for paragraph boundaries to prevent jarring audio tearing
            if isPlaying {
                if mode != activeMode {
                    pendingMode = mode
                } else {
                    pendingMode = nil
                }
            } else {
                activeMode = mode
                pendingMode = nil
            }
            
        case .systemRecovery:
            // Recovery must force a boundary handoff even if activeMode logically remained .premium
            let bPending = pendingMode
            let bActive = activeMode
            let bReq = requestedMode
            
            if isPlaying {
                pendingMode = mode
            } else {
                activeMode = mode
                pendingMode = nil
            }
            print("[RECOVERY_TRACE] VMC systemRecovery: mode=\(mode) isPlaying=\(isPlaying) | Before: a=\(bActive) r=\(bReq) p=\(String(describing: bPending)) | After: a=\(activeMode) r=\(requestedMode) p=\(String(describing: pendingMode))")
        }
    }

    /// Evaluates and applies any pending mode changes, returning the resolved mode.
    func resolveModeForNextParagraph() -> VoiceMode {
        if let mode = pendingMode {
            activeMode = mode
            pendingMode = nil
        }
        return activeMode
    }

    /// Forcefully commits the previously requested mode immediately over the active mode.
    func applyImmediateRequestedMode() -> VoiceMode {
        activeMode = requestedMode
        pendingMode = nil
        return activeMode
    }

    /// Hard-sets both the requested and active modes instantly, cancelling any pending states.
    func forceMode(_ mode: VoiceMode) {
        requestedMode = mode
        activeMode = mode
        pendingMode = nil
    }

    /// Resets entirely to the environment's preferred default mode.
    func reset() {
        let defaultMode = SettingsManager.shared.preferredVoiceMode
        requestedMode = defaultMode
        activeMode = defaultMode
        pendingMode = nil
        isPremiumTemporarilyUnavailable = false
    }

    /// Indicates whether a mode switch is waiting for the next boundary evaluation.
    var hasPendingSwitch: Bool {
        return pendingMode != nil
    }
    
    @Published private(set) var isPremiumTemporarilyUnavailable: Bool = false
    
    func markPremiumTemporarilyUnavailable(_ unavailable: Bool) {
        if isPremiumTemporarilyUnavailable != unavailable {
            isPremiumTemporarilyUnavailable = unavailable
        }
    }
}
