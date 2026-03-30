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

    private let settings = SettingsManager.shared
    let entitlementManager = EntitlementManager()
    let gateController = PlaybackGateController()
    let voiceModeController = VoiceModeController()

    private var premiumCapabilityAvailable: Bool { settings.hasValidGoogleKey }
    private var isPremiumActiveMode: Bool { voiceModeController.activeMode == .premium && premiumCapabilityAvailable && !voiceModeController.isPremiumTemporarilyUnavailable }

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
                if self.isPremiumActiveMode {
                    self.isPlaying = (player.timeControlStatus == .playing || player.timeControlStatus == .waitingToPlayAtSpecifiedRate)
                }
            }
        }

        playerItemObservation = player.observe(\.currentItem, options: [.new, .old]) { [weak self] player, change in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let newItem = change.newValue as? AVPlayerItem {
                    if let oldItem = change.oldValue as? AVPlayerItem, let oldIndex = self.itemIndexMap[oldItem] {
                        AppLogger.logEvent("PLAYBACK_FINISH", metadata: ["index": oldIndex])
                        if let newIndex = self.itemIndexMap[newItem] {
                            AppLogger.logEvent("ADVANCE_TO_NEXT", metadata: ["nextIndex": newIndex])
                        }
                    }
                    self.handleCurrentItemChange(to: newItem)
                } else if change.newValue == nil && self.isPremiumActiveMode {
                    guard self.highestEnqueuedIndex != -1 else { return }

                    AppLogger.logEvent("QUEUE_EMPTY")
                    if let oldItem = change.oldValue as? AVPlayerItem, let oldIndex = self.itemIndexMap[oldItem] {
                        AppLogger.logEvent("PLAYBACK_FINISH", metadata: ["index": oldIndex])

                        if self.isPlaying && oldIndex < self.paragraphs.count - 1 {
                            let nextReq = oldIndex + 1
                            AppLogger.logEvent("QUEUE_STARVATION_START", metadata: ["nextRequiredIndex": nextReq, "queueCount": 0])
                            self.starvationStartTime = Date()
                        }
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
        if player.currentItem != nil {
            player.defaultRate = playbackRate
            player.play()
            player.rate = playbackRate
            isPlaying = true
            isLoading = false
            return
        }

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
                voiceModeController.markPremiumTemporarilyUnavailable(true)
                startPremiumRecoveryProbe()
                playLocal()
            } else {
                isPlaying = false
                errorMessage = caughtError.localizedDescription
            }
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
            if let url = try? await task.value {
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
            }
        }
    }

    private func handleCurrentItemChange(to item: AVPlayerItem) {
        guard let index = itemIndexMap[item] else { return }

        // Mode switch boundary evaluation
        if voiceModeController.hasPendingSwitch {
            let resolvedMode = voiceModeController.resolveModeForNextParagraph()
            
            AppLogger.logEvent("VOICE_MODE_SWITCH", metadata: ["newMode": resolvedMode == .premium ? "premium" : "standard", "boundaryIndex": index])
            
            let boundaryIndex = index
            playbackGeneration = UUID()
            
            activeTask?.cancel()
            appleTTSDebounceTimer?.invalidate()
            currentAppleUtterance = nil
            localSynthesizer.stopSpeaking(at: .immediate)
            
            queueMaintenanceTask?.cancel()
            watchdogTask?.cancel()
            downloadTasks.values.forEach { $0.cancel() }
            downloadTasks.removeAll()
            audioCache.removeAll()
            player.pause()
            player.removeAllItems()
            itemIndexMap.removeAll()
            highestEnqueuedIndex = -1
            currentParagraphIndex = boundaryIndex
            isLoading = false
            errorMessage = nil
            
            if resolvedMode == .premium && premiumCapabilityAvailable && !voiceModeController.isPremiumTemporarilyUnavailable {
                playGoogle()
            } else {
                playLocal()
            }
            
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
    
    // MARK: - Premium Recovery

    private var premiumRecoveryTimer: Timer?
    
    private func startPremiumRecoveryProbe() {
        guard premiumRecoveryTimer == nil else { return }
        premiumRecoveryTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] timer in
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
        
        // Find next appropriate index to prefetch and probe
        let probeIndex = min(currentParagraphIndex + 1, paragraphs.count > 0 ? paragraphs.count - 1 : 0)
        do {
            let task = ensureAudioTask(for: probeIndex)
            _ = try await task.value
            
            print("Premium capability recovered via probe.")
            voiceModeController.markPremiumTemporarilyUnavailable(false)
            premiumRecoveryTimer?.invalidate()
            premiumRecoveryTimer = nil
            errorMessage = nil // clean stale fallback errors
        } catch {
            print("Premium probe failed, still unavailable.")
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
        guard !isPremiumActiveMode else { return }

        guard utterance == currentAppleUtterance else { return }

        if isSessionActive {
            let next = currentParagraphIndex + 1
            if next < paragraphs.count {
                if voiceModeController.hasPendingSwitch {
                    currentAppleUtterance = nil
                    
                    let resolvedMode = voiceModeController.resolveModeForNextParagraph()
                    currentParagraphIndex = next
                    
                    if resolvedMode == .premium && premiumCapabilityAvailable && !voiceModeController.isPremiumTemporarilyUnavailable {
                        playGoogle()
                    } else {
                        speakLocalParagraph(index: next)
                    }
                } else if voiceModeController.activeMode == .premium && premiumCapabilityAvailable && !voiceModeController.isPremiumTemporarilyUnavailable {
                    // Restores premium natively if it was temporarily disabled due to failure and just recovered
                    currentAppleUtterance = nil
                    currentParagraphIndex = next
                    playGoogle()
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

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) { isPlaying = false }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) { isPlaying = true }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) { isPlaying = true }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { isPlaying = false }
}

