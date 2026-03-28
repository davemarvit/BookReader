# BookReader — Phase Zero Implementation Spec
_Version 1.0_
_Target audience: Gemini / implementation engineer_
_Goal: add monetization foundations safely, without destabilizing the current audio system_

---

## 0. Purpose

Phase Zero is an **internal / TestFlight / friends-and-family** implementation phase.

It is **not** the final public-launch monetization system.

Phase Zero should implement:

- free vs paid gating
- subscription purchase flow
- free-tier Apple TTS fallback
- paid-tier premium cloud TTS entitlement flow
- usage accounting foundations
- paywall / exhaustion UX at paragraph boundaries
- settings + account surfaces needed to test the model

Phase Zero should **not** implement full public-launch top-ups yet. However, the architecture must reserve clean hooks for future top-up hours.

---

## 1. Hard Constraints from Existing Codebase

### 1.1 Preserve audio queue stability
The current paragraph-by-paragraph `AVQueuePlayer` system is delicate and recently stabilized.

**Do not make fundamental changes** to:
- `AudioController.ensureAudioTask()`
- the `AVQueuePlayer` lifecycle
- the existing paragraph queueing model
- lock screen / background playback behavior

Any monetization logic must be inserted **around** the current engine, not by rewriting it.

### 1.2 Monetization boundaries happen only at paragraph boundaries
Any of the following must occur only at a paragraph boundary:
- free preview exhaustion
- paid hours exhaustion
- free → Apple fallback
- premium interruption prompts
- paywall prompts related to playback

Never interrupt or mutate the currently playing paragraph mid-stream except for the intentionally designed fade-out behavior when a boundary is reached.

### 1.3 Free tier should cost us $0 in TTS
Phase Zero free users should use **Apple local `AVSpeechSynthesizer`** as the effective free-tier engine.

Free users may still have a limited premium preview concept in product logic, but Phase Zero implementation should prioritize keeping server/cloud TTS cost for non-paying users at **exactly $0** unless explicitly enabled for limited internal testing.

### 1.4 Local-first architecture remains the default
The existing app is local-first:
- `library.json`
- local metadata
- local progress
- local settings/state

Do not introduce a heavy remote data model in Phase Zero.

---

## 2. Scope for Phase Zero

### 2.1 Included in Phase Zero
Implement:

1. Subscription framework
2. Free vs paid entitlement model
3. Reader and Avid Reader plans
4. Apple TTS free path
5. Premium cloud TTS paid path
6. Usage accounting foundations
7. Account / subscription screen
8. Library-limit gating
9. Speed-limit gating
10. Playback exhaustion UX
11. Curated voice selection in settings
12. Minimal backend assumptions clearly defined
13. UUID-based stored filenames for imported books

### 2.2 Excluded from Phase Zero
Do **not** implement yet:

1. Public-launch top-ups
2. Auto top-up purchase flow
3. Badge UI
4. Referral system
5. Social sharing
6. Cross-device reading sync
7. Cloud reading-history storage
8. Full remote user-account system beyond the lightest requirement for subscription/TTS mediation

### 2.3 Must be architecturally prepared for later
Even though not yet implemented, Phase Zero must leave clean extension points for:

- top-up hours
- auto top-up
- local-first badge engine
- future backend persistence for top-up balances

---

## 3. Monetization Framework Choice

### 3.1 Use RevenueCat
Phase Zero should use **RevenueCat** for subscriptions.

Do **not** implement raw StoreKit 2 directly unless absolutely necessary.

### 3.2 Why
RevenueCat is preferred because:
- faster integration
- simpler entitlement management
- easier iteration during private testing
- better fit for Phase Zero speed and stability

### 3.3 Implementation expectation
Create a dedicated subscription / entitlement manager that wraps RevenueCat rather than scattering purchase logic across views.

Suggested file:
- `EntitlementManager.swift` or `SubscriptionManager.swift`

---

## 4. Minimal Backend Assumption

### 4.1 Premium TTS requires controlled infrastructure
We are **not** shipping a built-in Google API key in the app.

Therefore:
- free users use Apple local TTS
- paid premium TTS requests must go through infrastructure we control

### 4.2 Phase Zero backend should be minimal
The spec should assume the lightest realistic backend/proxy:

- authenticated request from app
- subscription/entitlement validation
- proxy request to Google Cloud TTS
- return synthesized audio to app

Backend does **not** need to store:
- books
- reading history
- badges
- local progress

### 4.3 Identity model for Phase Zero
Keep identity as light as possible.

Acceptable approaches:
- RevenueCat anonymous / app-user ID
- lightweight backend token tied to RevenueCat entitlement
- no rich user profile system yet

Avoid requiring a full standalone account signup in Phase Zero.

---

## 5. Product Model to Implement in Phase Zero

### 5.1 Plans
Implement two subscription products:

#### Reader
- $5.99/month
- 10 included premium narration hours

#### Avid Reader
- $12.99/month
- 25 included premium narration hours

Both paid plans also unlock:
- unlimited library size
- faster reading speeds up to 4x
- premium cloud narration
- curated premium voice choices

### 5.2 Free tier
Free tier includes:
- unlimited Apple TTS
- library limit = 10 books
- speed limit = 1.5x
- no paid cloud narration entitlement in general usage for Phase Zero

Note: product docs discuss a 20-minute premium preview. For Phase Zero implementation, because free-tier cloud cost should be $0 by default, this preview should be treated as **feature-flagged / optional internal testing behavior**, not a required production behavior in this phase.

---

## 6. Core New Architectural Layer

### 6.1 Add a central UsageManager
Create a single source of truth for monetization usage logic.

Suggested file:
- `UsageManager.swift`

### 6.2 Responsibilities
`UsageManager` should manage:

- active access tier (`free`, `reader`, `avidReader`)
- included plan hours remaining
- reserved placeholder for future top-up hours remaining
- preview-remaining placeholder if feature-flagged later
- usage consumption logic
- eligibility to use premium cloud TTS
- entitlement-aware playback decisions

### 6.3 Required conceptual model
Use a model roughly like:

```swift
enum AccessTier {
    case free
    case reader
    case avidReader
}

struct UsageState {
    var accessTier: AccessTier
    var planHoursRemaining: Double
    var topUpHoursRemaining: Double   // placeholder for Phase One
    var premiumPreviewMinutesRemaining: Double // placeholder / feature flag
    var currentPeriodStart: Date?
}
```

Names can vary, but the architecture must support this shape.

### 6.4 Do not scatter usage logic
Do not store independent monetization logic in:
- random SwiftUI views
- `SettingsManager`
- `StatsManager`
- `AudioController`

Views may query and display state, but `UsageManager` must own the rules.

---

## 7. Accounting Philosophy

### 7.1 Accounting basis
Usage is based on **content duration at 1x speed**, not actual playback speed.

### 7.2 User-favorable drift is acceptable
Exact billing-grade precision is not required in Phase Zero.

If reliability and user trust improve by allowing slight user-favorable drift, choose reliability.

### 7.3 Separate accounting from user-facing rough stats
Do **not** rely on the existing `StatsManager` timer as the billing/entitlement source of truth.

Instead:

- create a canonical usage/accounting path for monetization
- allow `StatsManager` to remain approximate for user-facing stats if needed

### 7.4 Better long-term architecture
If practical, introduce **one underlying event stream** and derive:

- monetization/accounting state
- stats/badge state

But Phase Zero does not need full badge implementation.

---

## 8. Audio Routing Rules

### 8.1 Free users
Free users should default to:
- Apple local TTS only

### 8.2 Paid users
Paid users should use:
- premium cloud TTS (through controlled backend/proxy)
- as long as plan hours remain

### 8.3 When plan hours are exhausted
At a paragraph boundary:
- finish current paragraph
- fade out
- pause
- present exhaustion UI

Do not auto-switch silently.

### 8.4 Phase Zero exhaustion UI for paid users
Voice prompt:
> “You’ve used your included premium hours. Options are available on your screen.”

UI options:
1. Continue with standard voice
2. View subscription/account details

Note:
- top-ups are not implemented yet in Phase Zero
- architecture should reserve space for:
  - Turn on auto top-up
  - Add more hours
  later

### 8.5 Free preview exhaustion
If a premium preview feature flag is enabled internally, exhaustion must behave as designed in the product docs:
- paragraph boundary
- fade
- voice + UI
- subscribe first
- continue with standard voice second

But again, Phase Zero should not depend on non-paying cloud usage by default.

---

## 9. Paywall / Upgrade Entry Points to Implement Now

### 9.1 Library limit
Free tier maximum = 10 books.

When user attempts import beyond 10:
- do not fail silently
- show upgrade UI
- explain that paid plans unlock unlimited library

### 9.2 Speed limit
Free users can use up to 1.5x.

If user attempts >1.5x:
- do not hard-crash or create a jarring modal
- show lightweight upgrade prompt / tooltip:
  > “Subscribe to unlock faster reading speeds”

### 9.3 Voluntary upgrade
Provide upgrade entry points from:
- Settings
- My Account / Subscription screen
- optional Library screen CTA

### 9.4 Playback exhaustion
Paid exhaustion handled as described above.

---

## 10. Voice Strategy to Implement

### 10.1 Premium voices
Keep a **small curated premium voice set**:
- at least one male
- at least one female
- optionally two of each if stable

Default to one chosen premium voice.

### 10.2 Apple voices
Also allow a small curated Apple TTS voice set for fallback.

### 10.3 Do not expose “voice tiers”
Do not present the product as:
- basic premium voice
- super premium voice

This is not a visible pricing ladder.

### 10.4 Settings surface
Voice selection should live in Settings and feel like personalization, not a core monetization funnel.

---

## 11. My Account / Subscription Screen

Implement a dedicated screen or section that shows:

### For free users
- current tier: Free
- library usage: X / 10
- speed limit note
- upgrade CTA

### For paid users
- current plan: Reader or Avid Reader
- plan hours remaining
- renewal date
- premium voice selection
- standard voice selection
- manage subscription action

Do not yet show top-up hours in Phase Zero UI, but structure models so it can be added cleanly later.

---

## 12. File Storage Improvement

### 12.1 Switch internal stored filenames to UUIDs
Current import flow risks filename collisions if different books share the same original filename.

Phase Zero should update local import/storage behavior so imported files are stored under UUID-based internal filenames while preserving user-visible title/author metadata.

This is a correctness improvement and should be done now.

---

## 13. Badge / Future Stats Future-Proofing

### 13.1 Do not build badge UI now
Phase Zero should not implement visible badges.

### 13.2 Do capture enough local data
Phase Zero should preserve enough local data to support future local-first badges, such as:
- session timestamps
- normalized content duration
- progress milestones
- completion events
- word/page estimate foundations if convenient

### 13.3 Privacy posture
Reading activity and badge computation should remain local-first.

---

## 14. Recommended File-Level Changes

This is a guidance map, not a rigid rule.

### 14.1 New / modified files likely needed
- **New:** `UsageManager.swift`
- **New:** `EntitlementManager.swift` or `SubscriptionManager.swift`
- **New:** Paywall / subscription views
- **Modify:** `AudioController.swift`
- **Modify:** `SettingsManager.swift`
- **Modify:** `GoogleTTSClient.swift`
- **Modify:** `LibraryManager.swift`
- **Modify:** `SettingsView.swift`
- **Modify:** `LibraryView.swift`
- **Optional modify:** `StatsManager.swift` (only if needed to align future event capture)
- **Optional new:** lightweight backend client wrapper for premium TTS

### 14.2 AudioController change philosophy
Only add:
- boundary checks
- routing decisions
- calls into `UsageManager`

Do not rewrite queue mechanics.

---

## 15. Implementation Guidance by Subsystem

### 15.1 AudioController
Add the minimum logic needed to:
- determine whether current paragraph should route to premium or standard voice
- detect exhaustion at paragraph boundaries
- trigger fade + pause + UI signal
- preserve queue stability

### 15.2 LibraryManager
Add:
- free-tier library-limit enforcement
- UUID-based storage fix

### 15.3 SettingsManager
Keep existing settings persistence responsibilities, but do not make it the owner of monetization rules.

It may continue to store:
- selected premium voice
- selected Apple voice
- UI preferences

### 15.4 GoogleTTSClient
Prepare for:
- controlled backend/proxy mode
- no shipping built-in production API key

Avoid assumptions that the device holds the company-paid Google key.

### 15.5 Views
Views should:
- render current state
- invoke purchase / upgrade actions
- show exhaustion prompts
but should not independently decide entitlement rules.

---

## 16. RevenueCat / Entitlement Requirements

Implement enough RevenueCat integration to support:

- Reader monthly plan
- Avid Reader monthly plan
- entitlement refresh on launch
- entitlement refresh on foreground
- restore purchases
- graceful offline / loading state behavior

Do not overcomplicate user identity in Phase Zero.

---

## 17. Testing Requirements for Phase Zero

Phase Zero is successful when all of the following are true:

1. Free users can import up to 10 books and use Apple TTS indefinitely
2. Free users are blocked cleanly at >10 books with upgrade prompt
3. Free users cannot exceed 1.5x without lightweight upgrade prompt
4. Paid users can subscribe successfully via RevenueCat
5. Paid users receive premium cloud TTS access when entitled
6. Paid users lose premium access cleanly when included hours are exhausted
7. Paid exhaustion occurs at paragraph boundaries without destabilizing queueing
8. Voice selection works for both premium and standard modes
9. Subscription/account state survives app relaunch
10. No production Google API key is embedded in shipping app logic
11. File import works without filename collisions
12. Code structure remains ready for future top-ups without rewrite

---

## 18. Explicit Non-Goals for Phase Zero

To avoid accidental scope creep, do not implement now:

- top-up purchase products
- auto top-up purchase products
- top-up persistence backend
- referrals
- badge UI
- social feed
- shareable achievements
- remote reading history sync
- elaborate account creation

---

## 19. Summary Implementation Philosophy

Phase Zero should be:

- safe
- minimal
- local-first
- subscription-focused
- backend-light
- audio-stability-preserving
- future-proof for top-ups

The core rule is:

> Do not trade queue stability for monetization cleverness.
