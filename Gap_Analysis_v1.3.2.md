# BookReader Gap Analysis: Codebase vs. Spec v1.3.2

This report evaluates the current macOS/iOS SwiftUI codebase (`ReaderApp`) against the provided v1.3.2 Unified System Spec. 

## 1. Current implementation summary

**Playback architecture:** The app uses a dual-engine approach (`AVQueuePlayer` for Premium/Google TTS and `AVSpeechSynthesizer` for Standard/Apple TTS). It processes audio paragraph-by-paragraph. A sophisticated `AudioController` manages pre-fetching, starvation handling, dynamic queue buffering, and lifecycle execution. 

**Voice mode architecture:** The codebase uses `premium` and `standard` internal enums instead of the spec's `enhanced` and `basic` nomenclature, though the UI explicitly translates these to match the "Basic" vs "Enhanced" text on-screen. Transitions are smoothly managed by delaying requested mode switches to paragraph boundaries via the `VoiceModeController` to prevent audio tearing.

**Enhanced/basic switching & Recovery:** Switching triggers localized caching boundaries. Beautifully, the codebase goes beyond the spec by implementing a robust background `premiumRecoveryTimer`. When Premium degrades to Basic (due to transient network failures), the client actively, yet silently, probes ahead by attempting to download future paragraphs. Once it sustains 2 consecutive successful probes and builds a 10s buffer, it automatically restores the user to Premium.

**Reader banner behavior:** Implemented flawlessly. Five distinct states map to the `ReaderBannerState` correctly triggering UI changes ("Enhanced Audio", "Basic · Enhanced Available", "Basic · Enhanced Temporarily Unavailable", "Basic · Enhanced audio limit reached", etc).

**Quota / entitlement behavior:** 
- The app currently proxies "Quota" entirely off raw HTTP 429 / `"quotaExceeded"` errors from Google Cloud TTS API (`GoogleTTSClient.swift`). 
- It does not contain independent time-metric usage ledgers.
- The `EntitlementManager` resolves simple `.allowed` vs `.standardOnly` booleans, ignoring the complex `Free / Reader / Avid Reader` three-tier plan structure from the spec.

**Gating / modal behavior:** Gating relies on `PlaybackGateController` utilizing an elegant `CheckedContinuation` system to pause Swift concurrency threads waiting for a user decision in modals. Clicking "Upgrade" currently cancels the flow with "Coming Soon" (`ReaderView.swift` L350).

**Segmentation / read-along model:** Implemented and geometry-aware. Oversized paragraphs that exceed 60% of the `viewportHeight` are cleanly divided into visual segments that highlight synchronously during playback via `ReaderTextView`.

**Speed/Library cap:** Did not observe backend-enforced bounding. Speed is passed straight to the AV engines, missing the 1.5x snap-back. The 10-book library cap is absent.

---

## 2. Spec reconciliation

| Spec Area | Classification | Notes |
| :--- | :--- | :--- |
| **Audio modes** | **Implemented but evolved** | Uses `premium/standard` under the hood. The codebase actually has *better* recovery logic (silent probe ahead) than the spec mandates. |
| **Subscription plans** | **Not implemented yet** | The codebase treats entitlement as binary. `aviderReader`, `free` and `reader` plan models do not exist. |
| **Enhanced limit behavior** | **Partially implemented** | The audio queue halts appropriately and the UI updates to "Limit Reached", but this limit is generated directly from Google Cloud quota limits, not from a custom seconds-metered plan. |
| **Runtime unavailability behavior**| **Implemented and aligned** | Transitions gracefully to Apple TTS under the hood, updating banners exactly as requested. |
| **Interruption recovery** | **Partially implemented** | Apple iOS handles system-level pauses but explicit serialization of standard interruption logic across hard restarts is sparse. |
| **Library cap behavior** | **Not implemented yet** | Missing the "delete to make room" logic entirely. |
| **Speed cap behavior** | **Not implemented yet** | 1.5x snap-back for Free users is missing. |
| **Reader banner** | **Implemented and aligned** | High-fidelity implementation in `ReaderView.swift`. |
| **Now Playing status line** | **Partially implemented** | The global PlayerState manages availability well, though view layer checks for strict Now Playing passive behaviors are minimal. |
| **Audio messaging layer** | **Partially implemented** | Code fires `exhaustion_alert.mp3` upon quota exhaustion but there's no evidence of TTS saying exactly "You've reached the limit...". |
| **Playback gates** | **Implemented and aligned** | Highly stable asynchronous `PendingPlaybackGate` architecture. |
| **Segment model** | **Implemented but evolved** | `ReaderTextView` handles read-along segments brilliantly via `computeSegmentCount` reacting directly to geometry vs viewport instead of backend-supplied timing ranges. |
| **Capability snapshot & Usage Metering** | **Spec likely outdated / missing** | The codebase connects directly to Google TTS with a standard API key, relying on Google's own limits to trigger failures. It completely assumes a zero-backend world. |

---

## 3. Code vs spec mismatches that matter

**A. Direct Client-to-Provider TTS Integration**
The spec assumes a `Backend Services` layer acts as a proxy for TTS generation, metering seconds, and returning audio. **Reality:** The codebase connects directly to `texttospeech.googleapis.com`. This breaks the capability snapshot architecture entirely and prevents exact second metering.

**B. Binary Entitlements**
The spec dictates a tiered plan structure (Free, Reader, Avid Reader) with monthly hour buffers. **Reality:** The code considers users either `.allowed` or restricted, governed solely if they possess a valid API key or have hit a direct Google quota wall.

**C. No Speed or Library Enforcements**
Because there are no tier contexts, the app never actually enforces the 1.5x Speed limit or the 10-Book Library limit. Free users have infinite access until a Google quota fails.

**D. Evolution: Silent Recovery Probes**
The spec says "app may auto-recover to Enhanced at boundary". The codebase implements an incredibly sophisticated, silent background `getAudioTask` predictor that probes Google's availability for future paragraphs without disrupting the Apple fallback TTS. The code is *superior* to the spec here.

---

## 4. Backend-dependent vs client-implementable

### A. Requires backend or is meaningfully blocked by backend

- **Real usage accounting:** You cannot measure the exact generated TTS seconds precisely and reliably using client-side code alone, especially if users crash or disconnect. Metering must happen at a proxy server.
- **Authoritative capability snapshots:** A secure, trustworthy payload defining active plan entitlements (e.g., Avid Reader vs Free) and exactly how many seconds are left. If done on the client, it is trivial to hack/bypass.
- **StoreKit/Purchase backend validation:** Validating server-side transaction receipts to guarantee Apple handles proration securely.
- **Connecting to Provider Proxy:** The `GoogleTTSClient.swift` must be gutted and replaced to point at your own API Gateway rather than bypassing it and going straight to Google.

### B. Can still be implemented client-side now

- **Placeholder Plan Models (Mocks):** Updating `EntitlementManager` to parse an enum of `Free, Reader, AvidReader` instead of a plain boolean.
- **Speed Cap (1.5x snap-back):** You can implement the logic restricting `< 1.5x` if `activePlan == .free` entirely in `SettingsManager` / `AudioController` *today*.
- **Library Cap (10 limits):** You can implement a `books.count >= 10 && activePlan == .free` check in `LibraryManager.swift` to trigger a modal.
- **Spoken Audio Messaging Layer:** Injecting actual `AVSpeechUtterance` instances for "Connection lost. Switching to Basic audio." during capability transitions. Right now it just plays a tone (`exhaustion_alert.mp3`).

---

## 5. Recommended next priorities

1. **Stub the Tiered Plan Models (Client-Side, Low Risk)**
   - *Why:* It allows you to build the UI flow for different capabilities.
   - *Order:* 1

2. **Implement Speed & Library Soft-Caps (Client-Side, Low Risk)**
   - *Why:* Unlocks UI work for upgrade flows. Free tier needs to feel bounded. Build the 1.5x slider snap-back and the 10-book library full modal so those conversion funnels exist when the backend does arrive.
   - *Order:* 2

3. **Complete the Audio Message Layer (Client-Side, Low Risk)**
   - *Why:* The banner changes when network drops, but users listening with phones in their pockets have no idea. Use `AVSpeechUtterance` to announce "Basic Audio" transitions.
   - *Order:* 3

4. **Prepare the Backend Proxy Transition (Backend-Dependent, High Risk)**
   - *Why:* `GoogleTTSClient.swift` directly queries Google. You need to spin up a basic backend proxy that performs the exact HTTP call and meters it, then migrate the iOS endpoint URL to your new proxy. 
   - *Order:* 4

---

## 6. Suggested spec update

The spec is a great product document but has lost sync with the technical realities of what makes this app actually work right now. 

- **REVISE: Audio Modes (Section 1.2):** Clarify that internally, the engine utilizes `premium/standard` to represent networks, but publishes `enhanced/basic` to the view layer.
- **KEEP: Segment Display Model (Section 1.7):** Keep this! The developer did an amazing job interpreting it.
- **SPLIT: Architecture (Section 6):** Separate this into "Phase 1: Direct-to-Provider (Current)" and "Phase 2: Authoritative Proxy (Future)". It is critical to document that the app *currently* runs entirely on the client.
- **REVISE: Recovery Rules (Section 1.9 & 8.3):** Update the spec to officially enshrine the "Silent Recovery Probe" logic built into the codebase as the canonical way network recovery should function.

---

### Most useful next move

The single highest-leverage next thing to do in the codebase right now is **implementing the Speed Cap (1.5x snap-back) and Library Cap (10 books) in the client layer while mocking a "Free" tier state.** 

Because the entire architecture currently lacks a backend and operates globally as a "premium" user until Google cuts you off, building the strict behavioral gating mechanisms (snapping the slider back, blocking library imports) into the UI forces the conversion logic to be battle-tested immediately. When the backend finally arrives, dropping in the true entitlement boolean will seamlessly light up the pathways you've already built.
