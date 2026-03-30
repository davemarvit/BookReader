import Foundation
import Combine

/// Manages asynchronous UI presentation state for dynamic playback gating.
@MainActor
final class PlaybackGateController: ObservableObject {
    @Published var pendingGate: PendingPlaybackGate? = nil
    private var continuation: CheckedContinuation<PlaybackGateChoice, Never>?

    /// Suspends playback generation until the user resolves the presented monetization constraint.
    func requestPlaybackDecision(
        source: PlaybackIntentSource,
        paragraphIndex: Int,
        requestedMode: VoiceMode,
        entitlementManager: EntitlementManager
    ) async -> PlaybackGateChoice {
        
        if requestedMode == .standard {
            return .standard
        }
        
        if !entitlementManager.requiresExplicitGate(for: requestedMode) && entitlementManager.canResumePremiumPlayback() {
            return .premium
        }
        
        // Ensure no stray continuations leak before replacing the active gate
        cancelPendingGate()
        
        let newGate = PendingPlaybackGate(
            source: source,
            paragraphIndex: paragraphIndex,
            requestedMode: requestedMode
        )
        self.pendingGate = newGate
        
        return await withCheckedContinuation { cont in
            self.continuation = cont
        }
    }

    /// Resumes the suspended async request with the user's explicit choice and dismisses the active gate.
    func resolvePendingGate(with choice: PlaybackGateChoice) {
        if let activeContinuation = continuation {
            // Nullify reference before resuming to explicitly prevent double-resumes
            self.continuation = nil
            activeContinuation.resume(returning: choice)
        }
        self.pendingGate = nil
    }

    /// Explicitly aborts the suspended gate request, returning the cancel choice.
    func cancelPendingGate() {
        resolvePendingGate(with: .cancel)
    }
}
