// EntitlementManager.swift

import Foundation
import Combine

/// Runtime source of truth governing premium TTS playback permissions and explicit user gating.
final class EntitlementManager: ObservableObject {
    // TODO: Temporary client-side placeholder plan model.
    // Backend authority and real StoreKit-backed tier mapping will come later.
    @Published var currentPlan: Plan = .reader

    @Published var premiumEntitlement: PremiumEntitlementState = .requiresDecision
    @Published var lastResolvedSessionChoice: PlaybackGateChoice? = nil
    @Published var lastGateReason: String? = nil
    @Published var showUpgradeBanner: Bool = false

    /// Determines if a gate interface must be shown before continuing playback in the requested mode.
    func requiresExplicitGate(for requestedMode: VoiceMode) -> Bool {
        if requestedMode == .standard {
            return false
        }
        return !(premiumEntitlement == .allowed && lastResolvedSessionChoice == .premium)
    }

    /// Checks if we have an active, resolved intent guaranteeing premium network fetching is allowed.
    func canGeneratePremiumAudio() -> Bool {
        return premiumEntitlement == .allowed && lastResolvedSessionChoice == .premium
    }

    /// Checks if the engine is authorized to resume reading a premium queued item.
    func canResumePremiumPlayback() -> Bool {
        return canGeneratePremiumAudio()
    }

    /// Records the user's explicit monetization or fallback choice from a gate interface.
    func recordGateChoice(_ choice: PlaybackGateChoice) {
        switch choice {
        case .premium:
            lastResolvedSessionChoice = .premium
            premiumEntitlement = .allowed
        case .standard:
            lastResolvedSessionChoice = .standard
        case .cancel:
            lastResolvedSessionChoice = nil
        }
    }

    /// Forcibly revokes premium access and logs exactly why (e.g. quota depleted, network failure).
    func downgradeToStandard(reason: String) {
        premiumEntitlement = .standardOnly
        lastResolvedSessionChoice = .standard
        lastGateReason = reason
    }

    /// Clears the active session choice without revoking the underlying entitlement capability.
    func resetSessionDecision() {
        lastResolvedSessionChoice = nil
    }
}
