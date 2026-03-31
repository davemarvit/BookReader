import Foundation
import UIKit
import AVFoundation
import MediaPlayer
import Combine

@MainActor
class AudioController: NSObject, ObservableObject {
    @Published var isPlaying: Bool = false {
        didSet {
            if isPlaying {
                updateNowPlayingInfo(playbackRate: Double(playbackRate))
            } else {
                updateNowPlayingInfo(playbackRate: 0.0)
            }
        }
    }

    @Published var playbackRate: Float = UserDefaults.standard.float(forKey: "playbackRate") == 0 ? 1.0 : UserDefaults.standard.float(forKey: "playbackRate") {
        didSet {
            UserDefaults.standard.set(playbackRate, forKey: "playbackRate")
            updatePlaybackRate()
        }
    }

    weak var libraryManager: LibraryManager?

    @Published var currentParagraphIndex: Int = 0 {
        didSet {
            updateNowPlayingInfo()
        }
    }

    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    @Published var isSessionActive: Bool = false
    @Published var diagnosticDetails: String = "Diagnostics: Initializing..."
    private var playbackGeneration = UUID()

    private var isTransitioningPlayback = false

    private let settings = SettingsManager.shared
    let entitlementManager = EntitlementManager()
    let gateController = PlaybackGateController()
    let voiceModeController = VoiceModeController()

    private var premiumCapabilityAvailable: Bool { settings.hasValidGoogleKey }
    
    /// The single source of truth evaluating intended routing for startups and banners
    var resolvedPlaybackMode: VoiceMode {
        let isReady = premiumCapabilityAvailable && !voiceModeController.isPremiumTemporarilyUnavailable
        let targetMode = isSessionActive ? voiceModeController.activeMode : settings.preferredVoiceMode
        return (targetMode == .premium && isReady) ? .premium : .standard
    }
    
    private var isPremiumActiveMode: Bool { resolvedPlaybackMode == .premium }

    private var activeTask: Task<Void, Never>?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var bgTaskWorkItem: DispatchWorkItem?

    @Published var totalParagraphs: Int = 0
    @Published var currentBookID: UUID?
    @Published var bookTitle: String = ""
    @Published var coverImage: UIImage?

    var progress: Double {
        guard totalParagraphs > 0 else { return 0 }
        return Double(currentParagraphIndex) / Double(totalParagraphs)
    }

    var paragraphs: [String] = []

    // MARK: - Audio Engines

    private let player = AVQueuePlayer()
    private var timeControlStatusObserver: NSKeyValueObservation?
    private let ttsClient = GoogleTTSClient()

    private let localSynthesizer = AVSpeechSynthesizer()

    private var audioCache: [Int: URL] = [:]
    private var downloadTasks: [Int: Task<URL, Error>] = [:]

    private var cancellables = Set<AnyCancellable>()
    private var playerItemObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var appleTTSDebounceTimer: Timer?
    private var currentAppleUtterance: AVSpeechUtterance?

    private var lastPauseTime: Date? = nil
    private var lastVoiceID: String = ""
    private var starvationStartTime: Date? = nil

    @Published var sleepTimerActive: Bool = false
    @Published var sleepTimerRemaining: TimeInterval = 0
    private var sleepTimer: Timer?

    private var itemIndexMap: [AVPlayerItem: Int] = [:]
    private var queueMaintenanceTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var highestEnqueuedIndex: Int = -1

    override init() {
        super.init()
        setupAudioSession()
        setupRemoteCommandCenter()
        localSynthesizer.delegate = self

        player.automaticallyWaitsToMinimizeStalling = false

        timeControlStatusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard !self.isTransitioningPlayback else { return }
                if self.isPremiumActiveMode {
                    self.isPlaying = (player.timeControlStatus == .playing || player.timeControlStatus == .waitingToPlayAtSpecifiedRate)
                }
            }
        }

        playerItemObservation = player.observe(\.currentItem, options: [.new, .old]) { [weak self] player, change in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard !self.isTransitioningPlayback else { return }

                if let newItem = change.newValue as? AVPlayerItem {
                    if let oldItem = change.oldValue as? AVPlayerItem, let oldIndex = self.itemIndexMap[oldItem] {
                        AppLogger.logEvent("PLAYBACK_FINISH", metadata: ["index": oldIndex])
                        if let newIndex = self.itemIndexMap[newItem] {
                            AppLogger.logEvent("ADVANCE_TO_NEXT", metadata: ["nextIndex": newIndex])
                        }
                    }
                    self.handleCurrentItemChange(to: newItem)
                } else if player.currentItem == nil && self.voiceModeController.requestedMode == .premium {
                    guard self.highestEnqueuedIndex != -1 else { return }

                    logControlState(event: "queue_empty", reason: "starvation")
                    
                    let completedIndex = self.currentParagraphIndex
                    AppLogger.logEvent("PLAYBACK_FINISH", metadata: ["index": completedIndex])

                    if self.isSessionActive && completedIndex < self.paragraphs.count - 1 {
                        let nextReq = completedIndex + 1
                        AppLogger.logEvent("QUEUE_STARVATION_START", metadata: ["nextRequiredIndex": nextReq, "queueCount": 0])
                        self.starvationStartTime = Date()
                        
                        // If the physical AVPlayer queue runs completely dry mid-book, the network failed 
                        // real-time requirements. Atomically commit paragraph completion and fallback.
                        self.voiceModeController.markPremiumTemporarilyUnavailable(true)
                        AppLogger.logEvent("FALLBACK_TRIGGERED_ON_STARVATION", metadata: ["index": nextReq])
                        self.logControlState(event: "fallback_committed", reason: "queue_empty", extra: ["nextReq": nextReq])
                        self.transitionAndContinuePlayback(to: nextReq, shouldPlay: true, markTemporarilyUnavailable: true)
                    }

                    if self.currentParagraphIndex >= self.paragraphs.count - 1 {
                        self.isPlaying = false
                        self.isSessionActive = false
                    }
                }
            }
        }

        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateDiagnosticDetails()
                guard self.isPlaying else { return }
                StatsManager.shared.logReadingTime(seconds: 1.0)
            }
            .store(in: &cancellables)
    }

    deinit {
        if let timeObserver = timeObserver {
            player.removeTimeObserver(timeObserver)
        }
    }

    // MARK: - Setup

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set audio session category: \(error)")
        }
    }

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.play(source: .remoteCommand)
            }
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pause()
            }
            return .success
        }

        commandCenter.skipForwardCommand.preferredIntervals = [30]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.skip(bySeconds: 30)
            }
            return .success
        }

        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.skip(bySeconds: -15)
            }
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.skip(bySeconds: 30)
            }
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.skip(bySeconds: -15)
            }
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] _ in
            guard self != nil else { return .commandFailed }
            return .commandFailed
        }
    }

    // MARK: - Playback Logic

    func loadBook(text: String, bookID: UUID, title: String, cover: UIImage?, initialIndex: Int = 0) {
        if self.currentBookID == bookID && !self.paragraphs.isEmpty {
            return
        }

        self.stopEverything()

        self.currentBookID = bookID
        self.bookTitle = title
        self.coverImage = cover
        self.paragraphs = text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        self.totalParagraphs = self.paragraphs.count

        let safeIndex = (initialIndex >= 0 && initialIndex < self.paragraphs.count) ? initialIndex : 0
        self.currentParagraphIndex = safeIndex

        if safeIndex != initialIndex {
            libraryManager?.updateProgress(for: bookID, index: safeIndex)
        }

        self.audioCache.removeAll()
        self.downloadTasks.values.forEach { $0.cancel() }
        self.downloadTasks.removeAll()
        self.playbackGeneration = UUID()
        self.highestEnqueuedIndex = -1
        self.queueMaintenanceTask?.cancel()

        // Intentionally no premium prefetch on load.
    }

    func play(source: PlaybackIntentSource = .playButton) {
        Task {
            await handlePlayRequest(source: source)
        }
    }

    @MainActor
    private func handlePlayRequest(source: PlaybackIntentSource) async {
        // Ensure Session Active
        do { try AVAudioSession.sharedInstance().setActive(true) } catch { print("Audio Session Error: \(error)") }
        
        errorMessage = nil // clear error when user attempts to play
        
        // Ensure playback engine synchronizes to the single-source-of-truth resolved mode on cold start.
        // Solves the issue where VoiceModeController's object init blindly captures @AppStorage defaults too early.
        if !isPlaying {
            let targetMode = resolvedPlaybackMode
            if voiceModeController.activeMode != targetMode {
                voiceModeController.requestModeSwitch(targetMode, intent: .userInitiated, isPlaying: false)
            }
        }
        
        // Evaluate Smart Rewind
        if let pauseTime = lastPauseTime {
            let pauseDuration = Date().timeIntervalSince(pauseTime)
            if pauseDuration > 30.0 && isPremiumActiveMode {
                let currentSeconds = player.currentTime().seconds
                if currentSeconds > 0 && !currentSeconds.isNaN && !currentSeconds.isInfinite {
                    // Safe rewind boundary (3 seconds) clamped to 0
                    let newSeconds = max(0.0, currentSeconds - 3.0)
                    let newTime = CMTime(seconds: newSeconds, preferredTimescale: 600)
                    await player.seek(to: newTime)
                }
            }
        }
        self.lastPauseTime = nil // Consume timestamp
        
        isSessionActive = true // User intent
        
        if isPremiumActiveMode {
            playGoogle()
        } else {
            playLocal()
        }
    }

    func pause() {
        endBackgroundTask()
        isSessionActive = false
        isPlaying = false
        isLoading = false
        watchdogTask?.cancel()

        lastPauseTime = Date()

        player.pause()
        if localSynthesizer.isSpeaking {
            localSynthesizer.pauseSpeaking(at: .immediate)
        }

        updateNowPlayingInfo(playbackRate: 0.0)
    }

    func stopEverything() {
        playbackGeneration = UUID()
        highestEnqueuedIndex = -1
        isLoading = false
        queueMaintenanceTask?.cancel()
        watchdogTask?.cancel()
        downloadTasks.values.forEach { $0.cancel() }
        downloadTasks.removeAll()
        pause()
        player.removeAllItems()
        itemIndexMap.removeAll()
        appleTTSDebounceTimer?.invalidate()
        currentAppleUtterance = nil
        localSynthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - Navigation

    func seek(to percentage: Double, playAfterSeek: Bool? = nil) {
        guard totalParagraphs > 0 else { return }
        let newIndex = Int(Double(totalParagraphs) * percentage)
        let clampedIndex = min(max(newIndex, 0), totalParagraphs - 1)
        jumpToParagraph(at: clampedIndex, playAfterSeek: playAfterSeek ?? self.isPlaying, source: .sliderResume)
    }

    func restorePosition(index: Int) {
        guard index >= 0 && index < totalParagraphs else { return }
        currentParagraphIndex = index
    }

    func skip(bySeconds seconds: Double) {
        guard !paragraphs.isEmpty else { return }

        let charsPerSecond = 15.0 * Double(playbackRate)
        let targetCharsShift = Int(seconds * charsPerSecond)

        var newIndex = currentParagraphIndex
        var shiftAccumulator = 0

        if targetCharsShift > 0 {
            while newIndex < paragraphs.count - 1 && shiftAccumulator < targetCharsShift {
                shiftAccumulator += paragraphs[newIndex].count
                newIndex += 1
            }
        } else if targetCharsShift < 0 {
            let targetAbsChars = abs(targetCharsShift)
            while newIndex > 0 && shiftAccumulator < targetAbsChars {
                newIndex -= 1
                shiftAccumulator += paragraphs[newIndex].count
            }
        }

        jumpToParagraph(at: newIndex, playAfterSeek: self.isPlaying, source: .skipResume)
    }

    func setManualPlaybackPosition(index: Int) {
        guard index >= 0 && index < totalParagraphs else { return }

        if isPlaying {
            jumpToParagraph(at: index, playAfterSeek: true, source: .paragraphTapResume)
        } else {
            downloadTasks.values.forEach { $0.cancel() }
            downloadTasks.removeAll()
            playbackGeneration = UUID()
            highestEnqueuedIndex = -1
            queueMaintenanceTask?.cancel()
            watchdogTask?.cancel()
            currentParagraphIndex = index
            isLoading = false
            player.pause()
            player.removeAllItems()
            itemIndexMap.removeAll()
            appleTTSDebounceTimer?.invalidate()
            currentAppleUtterance = nil
            localSynthesizer.stopSpeaking(at: .immediate)
            activeTask?.cancel()
            errorMessage = nil
        }
    }

    private func jumpToParagraph(at index: Int, playAfterSeek: Bool, source: PlaybackIntentSource) {
        downloadTasks.values.forEach { $0.cancel() }
        downloadTasks.removeAll()
        playbackGeneration = UUID()
        highestEnqueuedIndex = -1
        queueMaintenanceTask?.cancel()
        watchdogTask?.cancel()
        player.pause()
        player.removeAllItems()
        itemIndexMap.removeAll()
        appleTTSDebounceTimer?.invalidate()
        currentAppleUtterance = nil
        localSynthesizer.stopSpeaking(at: .immediate)

        currentParagraphIndex = index
        isLoading = false
        activeTask?.cancel()

        if playAfterSeek {
            isSessionActive = true
            play(source: source)
        } else {
            isSessionActive = false
            isPlaying = false
        }
    }

    // MARK: - Voice Mode Switching

    func handleManualVoiceSwitch(to mode: VoiceMode) {
        let isCurrentlyPlaying = self.isPlaying
        self.errorMessage = nil

        voiceModeController.requestModeSwitch(mode, intent: .userInitiated, isPlaying: isCurrentlyPlaying)

        if isCurrentlyPlaying {
            restartCurrentParagraphForEngineSwitch()
        } else {
            // Paused: Just clear out stale caches so the new engine initializes freshly next play
            downloadTasks.values.forEach { $0.cancel() }
            downloadTasks.removeAll()
            player.removeAllItems()
            itemIndexMap.removeAll()
            appleTTSDebounceTimer?.invalidate()
            currentAppleUtterance = nil
            localSynthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func restartCurrentParagraphForEngineSwitch() {
        transitionAndContinuePlayback(to: currentParagraphIndex, shouldPlay: true, markTemporarilyUnavailable: nil)
    }

    private func transitionAndContinuePlayback(to activeIndex: Int, shouldPlay: Bool, markTemporarilyUnavailable: Bool?) {
        print("[TRANSITION_TRACE] Helper start: to=\(activeIndex), choosePremium=\(isPremiumActiveMode), play=\(shouldPlay), unavail=\(String(describing: markTemporarilyUnavailable))")
        isTransitioningPlayback = true
        
        // 1. Clear old engine state
        // PRESERVE pre-fetched tasks exclusively during automated premium recovery
        let isRecoveringPremium = isPremiumActiveMode && (markTemporarilyUnavailable == false)
        if !isRecoveringPremium {
            downloadTasks.values.forEach { $0.cancel() }
            downloadTasks.removeAll()
        }
        playbackGeneration = UUID()
        highestEnqueuedIndex = -1
        queueMaintenanceTask?.cancel()
        watchdogTask?.cancel()
        player.pause()
        player.removeAllItems()
        itemIndexMap.removeAll()
        appleTTSDebounceTimer?.invalidate()
        currentAppleUtterance = nil
        localSynthesizer.stopSpeaking(at: .immediate)
        isLoading = false
        activeTask?.cancel()
        errorMessage = nil
        
        // 2. Set current index correctly
        currentParagraphIndex = activeIndex
        
        // 3. Apply transition state (availability / mode)
        if let unavailable = markTemporarilyUnavailable {
            voiceModeController.markPremiumTemporarilyUnavailable(unavailable)
            if unavailable {
                startPremiumRecoveryProbe()
            } else {
                premiumRecoveryTimer?.invalidate()
                premiumRecoveryTimer = nil
            }
        }
        
        // 4. If playback should continue: explicitly call correct engine start logic
        if shouldPlay {
            isSessionActive = true
            if isPremiumActiveMode {
                playGoogle()
            } else {
                playLocal()
            }
        } else {
            // 5. If playback should NOT continue: remain paused
            isSessionActive = false
            isPlaying = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            print("[TRANSITION_TRACE] +0.1s: isPlay=\(self.isPlaying), item=\(self.player.currentItem != nil), spk=\(self.localSynthesizer.isSpeaking)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            print("[TRANSITION_TRACE] +0.5s: isPlay=\(self.isPlaying), item=\(self.player.currentItem != nil), spk=\(self.localSynthesizer.isSpeaking)")
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isTransitioningPlayback = false
        }
        
        if isRecoveringPremium {
            logControlState(event: "recovery_steady_state", reason: "0s")
            traceSteadyState(after: 1.0, phase: "1s")
            traceSteadyState(after: 3.0, phase: "3s")
            traceSteadyState(after: 5.0, phase: "5s")
            traceSteadyState(after: 10.0, phase: "10s")
        }
    }

    // MARK: - Apple TTS Implementation

    private func playLocal() {
        if localSynthesizer.isPaused && currentAppleUtterance != nil {
            localSynthesizer.continueSpeaking()
            isPlaying = true
            updateNowPlayingInfo(playbackRate: Double(playbackRate))
            return
        }

        if localSynthesizer.isSpeaking && currentAppleUtterance != nil {
            return
        }

        speakLocalParagraph(index: currentParagraphIndex)
    }

    private func speakLocalParagraph(index: Int) {
        guard index < paragraphs.count else {
            isPlaying = false
            return
        }

        let text = paragraphs[index]
        let utterance = AVSpeechUtterance(string: text)

        let appleVoiceID = SettingsManager.shared.selectedAppleVoiceID
        if !appleVoiceID.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: appleVoiceID) {
            utterance.voice = voice
        }

        let baseRate = AVSpeechUtteranceDefaultSpeechRate
        let mappedRate = baseRate + ((playbackRate - 1.0) * 0.125)
        let appleRate = min(max(mappedRate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        utterance.rate = appleRate

        currentAppleUtterance = utterance

        let chars = text.count
        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        let currentSpeed = playbackRate

        AppLogger.logEvent("FALLBACK_TO_APPLE_TTS_START", metadata: ["index": index, "chars": chars, "words": words, "speed": currentSpeed])

        isLoading = false // Ensure loading is off for Apple TTS
        localSynthesizer.speak(utterance)
        AppLogger.logEvent("FALLBACK_TO_APPLE_TTS_SUCCESS", metadata: ["index": index])
        isPlaying = true
        updateNowPlayingInfo(playbackRate: Double(playbackRate))
    }

    // MARK: - Google TTS Implementation

    private func playGoogle() {
        print("[RECOVERY_TRACE] entered playGoogle: idx=\(currentParagraphIndex) item=\(player.currentItem != nil) count=\(player.items().count)")
        if player.currentItem != nil {
            print("[RECOVERY_TRACE] playGoogle branch: resume existing item")
            player.defaultRate = playbackRate
            player.play()
            player.rate = playbackRate
            isPlaying = true
            isLoading = false
            return
        }

        print("[RECOVERY_TRACE] playGoogle branch: enqueue-and-play")
        activeTask?.cancel()
        activeTask = Task { @MainActor in
            await EnqueueAndPlay(from: currentParagraphIndex)
        }
    }

    private func EnqueueAndPlay(from index: Int, startPlaying: Bool = true) async {
        guard index < paragraphs.count else { return }

        let expectedGen = playbackGeneration

        let loadingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            if !Task.isCancelled, let self, self.player.currentItem == nil, self.playbackGeneration == expectedGen {
                self.isLoading = true
            }
        }

        do {
            let currentTask = ensureAudioTask(for: index)
            let url = try await currentTask.value

            guard playbackGeneration == expectedGen else {
                loadingTask.cancel()
                isLoading = false
                return
            }

            let item = AVPlayerItem(url: url)
            itemIndexMap[item] = index

            if player.items().isEmpty {
                highestEnqueuedIndex = index
                AppLogger.logEvent("AUDIO_ENQUEUED", metadata: ["index": index, "reason": "root_insertion"])
                AppLogger.logEvent("QUEUE_COUNT", metadata: ["count": 1])
                player.insert(item, after: nil)
                
                // Explicitly boot the prepipeline since dynamic engine transitions suppress the native KVO hook
                queueMaintenanceTask?.cancel()
                queueMaintenanceTask = Task { @MainActor [weak self] in
                    guard let self = self, self.playbackGeneration == expectedGen else { return }
                    await self.maintainQueue(currentIndex: index)
                }
            }

            loadingTask.cancel()
            isLoading = false

            player.defaultRate = playbackRate
            if startPlaying {
                player.play()
            }
            player.rate = playbackRate

        } catch let caughtError {
            loadingTask.cancel()
            isLoading = false

            let isTransient: Bool
            if let gError = caughtError as? GoogleTTSError {
                switch gError {
                case .invalidAPIKey, .quotaExceeded, .billingIssue, .badURL:
                    isTransient = false
                default:
                    isTransient = true
                }
            } else if caughtError is CancellationError {
                return
            } else {
                isTransient = true
            }

            if isTransient {
                transitionAndContinuePlayback(to: currentParagraphIndex, shouldPlay: true, markTemporarilyUnavailable: true)
            } else {
                isPlaying = false
                errorMessage = caughtError.localizedDescription
            }
            print("[RECOVERY_TRACE] EnqueueAndPlay catch: idx=\(currentParagraphIndex) err=\(caughtError.localizedDescription) trans=\(isTransient) activeMode=\(voiceModeController.activeMode)")
        }
    }

    private func maintainQueue(currentIndex: Int) async {
        let lookahead = 5
        var tasks: [(Int, Task<URL, Error>)] = []

        for i in 1...lookahead {
            let nextIndex = currentIndex + i
            guard nextIndex < paragraphs.count else { break }
            let task = ensureAudioTask(for: nextIndex)
            tasks.append((nextIndex, task))
        }

        let expectedGen = playbackGeneration
        for (nextIndex, task) in tasks {
            do {
                let url = try await task.value
                if Task.isCancelled || playbackGeneration != expectedGen {
                    AppLogger.logEvent("MAINTAIN_QUEUE_CANCELLED", metadata: ["index": nextIndex])
                    return
                }

                let items = player.items()
                let alreadyQueued = items.contains { itemIndexMap[$0] == nextIndex }
                let isMonotonicallyValid = nextIndex > highestEnqueuedIndex
                
                if !alreadyQueued && isMonotonicallyValid {
                    let newItem = AVPlayerItem(url: url)
                    itemIndexMap[newItem] = nextIndex
                    highestEnqueuedIndex = nextIndex
                    AppLogger.logEvent("AUDIO_ENQUEUED", metadata: ["index": nextIndex, "reason": "monotonic_guard_passed"])

                    if let last = items.last {
                        player.insert(newItem, after: last)
                    } else {
                        player.insert(newItem, after: nil)
                    }
                    AppLogger.logEvent("QUEUE_COUNT", metadata: ["count": player.items().count])
                } else if !alreadyQueued && !isMonotonicallyValid {
                    AppLogger.logEvent("ENQUEUE_REJECTED", metadata: ["index": nextIndex, "highestEnqueuedIndex": highestEnqueuedIndex, "reason": "stale_index_chronology"])
                }
            } catch {
                if Task.isCancelled || playbackGeneration != expectedGen { return }
                // Do not trigger aggressive fallback on single fetch failure or minor network jitter.
                // Allow the player to seamlessly consume remaining buffered premium chunks.
                // True exhaustion fallback is cleanly handled by the playerItemObservation QUEUE_EMPTY boundary.
                return // Stop attempting to fill the queue
            }
        }
    }

    private func handleCurrentItemChange(to item: AVPlayerItem) {
        guard let index = itemIndexMap[item] else { return }

        // Mode switch boundary evaluation
        if voiceModeController.hasPendingSwitch {
            let resolvedMode = voiceModeController.resolveModeForNextParagraph()
            print("[TRANSITION_TRACE] AV boundary evaluate: idx=\(index) pending=true resolved=\(resolvedMode)")
            
            let clearFlag: Bool? = (resolvedMode == .premium) ? false : nil
            transitionAndContinuePlayback(to: index, shouldPlay: isSessionActive, markTemporarilyUnavailable: clearFlag)
            return
        }

        AppLogger.logEvent("PLAYBACK_START", metadata: ["index": index])
        AppLogger.logEvent("QUEUE_COUNT", metadata: ["count": player.items().count])

        if let st = starvationStartTime {
            let delayMs = Int(Date().timeIntervalSince(st) * 1000)
            AppLogger.logEvent("QUEUE_STARVATION_END", metadata: ["nextRequiredIndex": index, "delayMs": delayMs])
            starvationStartTime = nil
        }

        watchdogTask?.cancel()
        watchdogTask = Task { @MainActor [weak self, weak item] in
            let duration = try? await item?.asset.load(.duration)
            guard !Task.isCancelled, let self, let item else { return }

            if let seconds = duration?.seconds, !seconds.isNaN, seconds > 0 {
                let currentRate = Double(self.playbackRate)
                let adjustedSeconds = seconds / (currentRate > 0 ? currentRate : 1.0)
                let bufferTime = 2.0
                let totalWaitNs = UInt64((adjustedSeconds + bufferTime) * 1_000_000_000)

                try? await Task.sleep(nanoseconds: totalWaitNs)

                guard !Task.isCancelled, self.isPlaying else { return }
                guard let currentItem = self.player.currentItem, currentItem == item else { return }
                guard self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate else { return }

                AppLogger.logEvent("WATCHDOG_TIMEOUT", metadata: ["index": index, "adjustedSeconds": adjustedSeconds])
            }
        }

        currentParagraphIndex = index
        updateNowPlayingInfo()
        updateDiagnosticDetails()

        let expectedGen = playbackGeneration
        queueMaintenanceTask?.cancel()

        queueMaintenanceTask = Task { @MainActor in
            guard playbackGeneration == expectedGen else { return }
            AppLogger.logEvent("MAINTAIN_QUEUE_TASK_CREATED", metadata: ["triggerIndex": index])
            await maintainQueue(currentIndex: index)
        }
    }

    private func updatePlaybackRate() {
        print("DIAGNOSTIC: updatePlaybackRate called. slider:\(playbackRate)")
        if isPlaying {
            if isPremiumActiveMode {
                player.defaultRate = playbackRate
                player.rate = playbackRate
            } else {
                appleTTSDebounceTimer?.invalidate()
                appleTTSDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.isPlaying, !self.isPremiumActiveMode else { return }
                        self.currentAppleUtterance = nil
                        self.localSynthesizer.stopSpeaking(at: .immediate)
                        self.speakLocalParagraph(index: self.currentParagraphIndex)
                    }
                }
            }
            updateNowPlayingInfo(playbackRate: Double(playbackRate))
        }
        updateDiagnosticDetails()
    }

    private func updateDiagnosticDetails() {
        let engine = isPremiumActiveMode ? "Google" : "Apple Fallback!"
        let pRate = String(format: "%.2f", playbackRate)
        let aRate = String(format: "%.2f", player.rate)
        let cInt = player.currentItem != nil ? 1 : 0
        let stat = isPlaying ? "Playing" : "Paused"

        diagnosticDetails = "Engine: \(engine) | Slider: \(pRate) | True Rate: \(aRate) | Queue: \(cInt) | \(stat)"
    }
    
    private func logControlState(event: String, reason: String? = nil, extra: [String: Any] = [:]) {
        let ts = String(format: "%.3f", Date().timeIntervalSince1970)
        let active = voiceModeController.activeMode == .premium ? "premium" : "standard"
        let req = voiceModeController.requestedMode == .premium ? "premium" : "standard"
        let unavail = voiceModeController.isPremiumTemporarilyUnavailable
        let pend = voiceModeController.hasPendingSwitch
        let qCount = player.items().count
        let fbSec = starvationStartTime != nil ? String(format: "%.1f", abs(Date().timeIntervalSince(starvationStartTime!))) : "nil"

        var msg = "[CONTROL] ts=\(ts) event=\(event)"
        if let r = reason { msg += " reason=\(r)" }
        msg += " idx=\(currentParagraphIndex) req=\(req) act=\(active) unavail=\(unavail) pend=\(pend) play=\(isPlaying) sess=\(isSessionActive) rate=\(playbackRate) qCount=\(qCount) probeCount=\(consecutiveSuccessfulProbes) fbSec=\(fbSec)"
        for (k, v) in extra { msg += " \(k)=\(v)" }
        print(msg)
    }

    private func traceSteadyState(after delay: TimeInterval, phase: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            let hasQTask = self.queueMaintenanceTask != nil && !self.queueMaintenanceTask!.isCancelled
            self.logControlState(event: "steady_state_trace", reason: phase, extra: [
                "delay": delay,
                "hiIdx": self.highestEnqueuedIndex,
                "hasQTask": hasQTask,
                "dlCount": self.downloadTasks.count,
                "gen": self.playbackGeneration.uuidString.prefix(4)
            ])
        }
    }

    // MARK: - Premium Recovery

    private var premiumRecoveryTimer: Timer?
    private var consecutiveSuccessfulProbes = 0
    
    private func startPremiumRecoveryProbe() {
        guard premiumRecoveryTimer == nil else { return }
        consecutiveSuccessfulProbes = 0
        premiumRecoveryTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            Task { @MainActor in
                await self.probePremiumRecovery()
            }
        }
    }
    
    @MainActor
    private func probePremiumRecovery() async {
        // Only run probe if we're theoretically supposed to be using premium
        guard voiceModeController.isPremiumTemporarilyUnavailable, premiumCapabilityAvailable, voiceModeController.requestedMode == .premium else {
            premiumRecoveryTimer?.invalidate()
            premiumRecoveryTimer = nil
            return
        }
        
        logControlState(event: "recovery_probe_runs")
        // Secondary Gate: Cooldown
        if let starvationTime = starvationStartTime, abs(Date().timeIntervalSince(starvationTime)) < 10.0 {
            logControlState(event: "recovery_gate_rejected", reason: "cooldown_active")
            return
        }
        
        // Find next appropriate index to prefetch and probe
        // We advance the lookahead probe index based on consecutive successes to build up the buffer
        let probeOffset = consecutiveSuccessfulProbes + 1
        let probeIndex = min(currentParagraphIndex + probeOffset, paragraphs.count > 0 ? paragraphs.count - 1 : 0)
        
        do {
            let task = ensureAudioTask(for: probeIndex)
            _ = try await task.value
            
            consecutiveSuccessfulProbes += 1
            
            // Primary Gate: Buffered Playback Readiness
            let rate = Double(playbackRate > 0 ? playbackRate : 1.0)
            var totalDuration = 0.0

            let bookIDString = currentBookID?.uuidString ?? "temp"
            let voiceID = SettingsManager.shared.selectedVoiceID
            let tempDir = FileManager.default.temporaryDirectory

            let startIndex = currentParagraphIndex + 1
            if startIndex < paragraphs.count {
                for index in startIndex..<paragraphs.count {
                    let expectedFileURL = tempDir.appendingPathComponent("para_\(bookIDString)_\(index)_\(voiceID).mp3")
                    
                    if FileManager.default.fileExists(atPath: expectedFileURL.path) {
                        let asset = AVURLAsset(url: expectedFileURL)
                        let durationSeconds = asset.duration.seconds
                        if !durationSeconds.isNaN && durationSeconds > 0 {
                            totalDuration += durationSeconds
                        }
                    } else {
                        break // stop at first gap — only contiguous buffer counts
                    }
                }
            }

            let bufferedSeconds = totalDuration / rate
            let isAtEnd = probeIndex == (paragraphs.count > 0 ? paragraphs.count - 1 : 0)

            guard consecutiveSuccessfulProbes >= 2 && (bufferedSeconds >= 10.0 || isAtEnd) else {
                logControlState(event: "recovery_gate_rejected", reason: "buffer_below_threshold", extra: ["bufferedSec": String(format: "%.1f", bufferedSeconds)])
                return // Wait for stability and sufficient buffer before switching
            }
            
            logControlState(event: "recovery_gate_accepted", reason: "recovery_ready")
            
            let wasPlayingFallback = self.isPlaying && !self.isPremiumActiveMode
            logControlState(event: "recovery_committed", reason: "switch_request", extra: ["wasFallback": wasPlayingFallback])
            
            if wasPlayingFallback {
                // Defer clearing flag until the Apple boundary actually executes the pending switch
                voiceModeController.requestModeSwitch(.premium, intent: .systemRecovery, isPlaying: true)
            } else {
                voiceModeController.markPremiumTemporarilyUnavailable(false)
            }
            print("[RECOVERY_TRACE] After switch req: a=\(voiceModeController.activeMode) r=\(voiceModeController.requestedMode) unavail=\(voiceModeController.isPremiumTemporarilyUnavailable) pend=\(voiceModeController.hasPendingSwitch)")
            
            premiumRecoveryTimer?.invalidate()
            premiumRecoveryTimer = nil
            errorMessage = nil // clean stale fallback errors
        } catch {
            consecutiveSuccessfulProbes = 0 // Reset on failure to enforce contiguous stability
            // Suppress repetitive probe failure noise
        }
    }

    // MARK: - Downloader Logic

    private func startBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            Task { @MainActor [weak self] in
                self?.endBackgroundTask()
            }
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func preloadAudio(for index: Int) async {
        guard index < paragraphs.count else { return }
        _ = await ensureAudioTask(for: index).result
    }

    private func ensureAudioTask(for index: Int) -> Task<URL, Error> {
        if let url = audioCache[index], FileManager.default.fileExists(atPath: url.path) {
            return Task { url }
        }

        if let existing = downloadTasks[index] {
            return existing
        }

        startBackgroundTask()

        let qCount = player.items().count
        let nextReq = currentParagraphIndex + (player.currentItem != nil ? 1 : 0)
        let bufferedAhead = max(0, qCount - (player.currentItem != nil ? 1 : 0))
        let isNextReq = (index == currentParagraphIndex) || (index == nextReq)

        // Capture all MainActor state BEFORE leaving MainActor
        let text = self.paragraphs[index]
        let currentSpeed = self.playbackRate
        let bookIDString = self.currentBookID?.uuidString ?? "temp"
        let voiceID = SettingsManager.shared.selectedVoiceID
        let ttsClient = self.ttsClient

        let task = Task.detached(priority: .userInitiated) {
            let networkStartTime = Date()

            let chars = text.count
            let words = text.split { $0.isWhitespace || $0.isNewline }.count
            let sentences = max(1, text.split(whereSeparator: { ".?!".contains($0) }).count)

            do {
                print("DEBUG: Fetching audio for \(index)")

                AppLogger.logEvent("TTS_REQUEST_START", metadata: [
                    "index": index,
                    "textLength": chars,
                    "speed": currentSpeed,
                    "queueCount": qCount,
                    "nextRequiredIndex": nextReq,
                    "bufferedAheadCount": bufferedAhead,
                    "isNextRequired": isNextReq
                ])

                // IMPORTANT: keep speed at 1.0 (do not change behavior)
                print("AUDIO_CONTROLLER: calling fetchAudio for index \(index)")
                let data = try await ttsClient.fetchAudio(
                    text: text,
                    voiceID: voiceID,
                    speed: 1.0
                )
                print("AUDIO_CONTROLLER: fetchAudio returned for index \(index), bytes=\(data.count)")

                let tempDir = FileManager.default.temporaryDirectory
                let fileURL = tempDir.appendingPathComponent(
                    "para_\(bookIDString)_\(index)_\(voiceID).mp3"
                )

                try data.write(to: fileURL)

                let durationMs = Int(Date().timeIntervalSince(networkStartTime) * 1000)

                AppLogger.logEvent("TTS_REQUEST_SUCCESS", metadata: [
                    "index": index,
                    "durationMs": durationMs,
                    "audioSize": data.count
                ])

                Task { @MainActor in
                    self.logControlState(event: "fetch_success", extra: ["durMs": durationMs, "bytes": data.count])
                }
                print("[BookReader][TTS_METRIC] index=\(index) chars=\(chars) words=\(words) sentences=\(sentences) speed=\(currentSpeed) durationMs=\(durationMs) audioBytes=\(data.count) success=true isNextRequired=\(isNextReq) queueCount=\(qCount) nextRequiredIndex=\(nextReq) bufferedAheadCount=\(bufferedAhead)")

                return fileURL

            } catch {
                let durationMs = Int(Date().timeIntervalSince(networkStartTime) * 1000)
                let nsError = error as NSError

                AppLogger.logEvent("TTS_REQUEST_FAILED", metadata: [
                    "index": index,
                    "domain": nsError.domain,
                    "code": nsError.code,
                    "description": nsError.localizedDescription,
                    "durationMs": durationMs
                ])

                Task { @MainActor in
                    self.logControlState(event: "fetch_failure", reason: "network_error", extra: ["domain": nsError.domain, "code": nsError.code])
                }
                print("[BookReader][TTS_METRIC] index=\(index) chars=\(chars) words=\(words) sentences=\(sentences) speed=\(currentSpeed) durationMs=\(durationMs) success=false errorDomain=\(nsError.domain) errorCode=\(nsError.code) isNextRequired=\(isNextReq) queueCount=\(qCount) nextRequiredIndex=\(nextReq) bufferedAheadCount=\(bufferedAhead)")

                throw error
            }
        }

        downloadTasks[index] = task

        // Return to MainActor for state updates
        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let url = try await task.value
                self.audioCache[index] = url
            } catch {
                // handled upstream
            }

            self.downloadTasks[index] = nil
            self.endBackgroundTask()
        }

        return task
    }

    private func getAudioURL(for index: Int) async throws -> URL {
        try await ensureAudioTask(for: index).value
    }

    // MARK: - MPNowPlayingInfoCenter

    private func updateNowPlayingInfo(playbackRate: Double? = nil) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()

        info[MPMediaItemPropertyTitle] = bookTitle.isEmpty ? "Book Reader" : bookTitle
        info[MPMediaItemPropertyArtist] = "Book Reader"

        if let cover = coverImage {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: cover.size) { _ in cover }
        }

        let totalDuration = estimatedTotalDuration
        let elapsed = estimatedElapsedDuration

        info[MPMediaItemPropertyPlaybackDuration] = totalDuration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed

        if let rate = playbackRate {
            info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Duration Estimation

    var estimatedTotalDuration: Double {
        let totalChars = paragraphs.reduce(0) { $0 + $1.count }
        let baseSeconds = Double(totalChars) / 15.0
        return baseSeconds
    }

    var estimatedElapsedDuration: Double {
        guard currentParagraphIndex < paragraphs.count else { return estimatedTotalDuration }
        let passedChars = paragraphs.prefix(currentParagraphIndex).reduce(0) { $0 + $1.count }
        return Double(passedChars) / 15.0
    }

    // MARK: - Helpers

    var timeElapsedString: String {
        guard currentParagraphIndex < paragraphs.count else { return "0m" }
        var charCount = 0
        for i in 0..<currentParagraphIndex { charCount += (paragraphs[i] as NSString).length }
        let baseSeconds = Double(charCount) / 15.0
        let adjustedSeconds = baseSeconds / Double(playbackRate)
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: TimeInterval(adjustedSeconds)) ?? "0m"
    }

    var timeRemainingString: String {
        guard currentParagraphIndex < paragraphs.count else { return "0m" }
        var charCount = 0
        for i in currentParagraphIndex..<paragraphs.count { charCount += (paragraphs[i] as NSString).length }
        let baseSeconds = Double(charCount) / 15.0
        let adjustedSeconds = baseSeconds / Double(playbackRate)
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: TimeInterval(adjustedSeconds)) ?? "0m"
    }

    var percentageString: String {
        String(format: "%.1f%%", progress * 100)
    }

    // MARK: - Sleep Timer

    var sleepTimerString: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: sleepTimerRemaining) ?? "00:00"
    }

    func startSleepTimer(minutes: Int) {
        cancelSleepTimer()

        sleepTimerRemaining = TimeInterval(minutes * 60)
        sleepTimerActive = true

        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if self.sleepTimerRemaining > 0 {
                    self.sleepTimerRemaining -= 1
                } else {
                    self.pause()
                    self.cancelSleepTimer()
                }
            }
        }
    }

    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerActive = false
        sleepTimerRemaining = 0
    }
}

// MARK: - Apple TTS Delegate
extension AudioController: @preconcurrency AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if isTransitioningPlayback { return }
        guard !isPremiumActiveMode else { return }

        guard utterance == currentAppleUtterance else { return }

        if isSessionActive {
            let next = currentParagraphIndex + 1
            if next < paragraphs.count {
                print("[RECOVERY_TRACE] Apple boundary evaluate: currIdx=\(currentParagraphIndex) next=\(next) pend=\(voiceModeController.hasPendingSwitch) a=\(voiceModeController.activeMode) r=\(voiceModeController.requestedMode) unavail=\(voiceModeController.isPremiumTemporarilyUnavailable) isPremAct=\(isPremiumActiveMode)")
                if voiceModeController.hasPendingSwitch {
                    let resolvedMode = voiceModeController.resolveModeForNextParagraph()
                    print("[RECOVERY_TRACE] Apple boundary HAS PENDING: resolved=\(resolvedMode) -> calling transitionAndContinuePlayback")
                    
                    let clearFlag: Bool? = (resolvedMode == .premium) ? false : nil
                    transitionAndContinuePlayback(to: next, shouldPlay: true, markTemporarilyUnavailable: clearFlag)
                } else if voiceModeController.activeMode == .premium && premiumCapabilityAvailable && !voiceModeController.isPremiumTemporarilyUnavailable {
                    // Restores premium natively if it was temporarily disabled due to failure and just recovered
                    transitionAndContinuePlayback(to: next, shouldPlay: true, markTemporarilyUnavailable: false)
                } else {
                    currentParagraphIndex = next
                    speakLocalParagraph(index: next)
                }
            } else {
                isPlaying = false
                isSessionActive = false
                isLoading = false
            }
        } else {
            isPlaying = false
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) { if !isTransitioningPlayback { isPlaying = false } }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) { if !isTransitioningPlayback { isPlaying = true } }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("[TRANSITION_TRACE] Apple didStart: index=\(currentParagraphIndex) transitioning=\(isTransitioningPlayback)")
        if !isTransitioningPlayback { isPlaying = true }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { if !isTransitioningPlayback { isPlaying = false } }
}

