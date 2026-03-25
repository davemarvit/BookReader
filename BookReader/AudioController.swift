import Foundation
import UIKit
import AVFoundation
import MediaPlayer
import Combine

class AudioController: NSObject, ObservableObject {
    @Published var isPlaying: Bool = false {
        didSet {
            // Update rate on change if needed, though handled by player logic mostly
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
    
    // Weak reference so AudioController can self-save progress without a retain cycle
    weak var libraryManager: LibraryManager?
    
    @Published var currentParagraphIndex: Int = 0 {
        didSet {
            updateNowPlayingInfo()
        }
    }
    
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    // Stable state validation
    @Published var isSessionActive: Bool = false
    @Published var diagnosticDetails: String = "Diagnostics: Initializing..."
    private var playbackGeneration = UUID()
    
    // Task management
    private var activeTask: Task<Void, Never>?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var bgTaskWorkItem: DispatchWorkItem?

    @Published var totalParagraphs: Int = 0
    @Published var currentBookID: UUID?
    @Published var bookTitle: String = ""
    @Published var coverImage: UIImage?
    
    // Progress (0.0 to 1.0)
    var progress: Double {
        guard totalParagraphs > 0 else { return 0 }
        return Double(currentParagraphIndex) / Double(totalParagraphs)
    }
    
    var paragraphs: [String] = []
    
    // MARK: - Audio Engines
    // Google TTS / Pre-recorded
    private let player = AVQueuePlayer() // Restored rock-solid 5-paragraph AVQueuePlayer
    private let ttsClient = GoogleTTSClient()
    
    // Apple Local TTS
    private let localSynthesizer = AVSpeechSynthesizer()
    
    // Cache & Downloading
    private var audioCache: [Int: URL] = [:]
    private var downloadTasks: [Int: Task<URL, Error>] = [:]
    
    // State Tracking
    private var cancellables = Set<AnyCancellable>()
    private var playerItemObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var appleTTSDebounceTimer: Timer?
    private var currentAppleUtterance: AVSpeechUtterance?
    
    // Smart Options
    private var lastPauseTime: Date? = nil
    
    // Sleep Timer
    @Published var sleepTimerActive: Bool = false
    @Published var sleepTimerRemaining: TimeInterval = 0
    private var sleepTimer: Timer?
    
    // Queue Management
    private var itemIndexMap: [AVPlayerItem: Int] = [:]

    override init() {
        super.init()
        setupAudioSession()
        setupRemoteCommandCenter()
        localSynthesizer.delegate = self
        
        // Optimize for speech latency
        player.automaticallyWaitsToMinimizeStalling = false
        
        // Observe AVQueuePlayer currentItem changes to auto-advance index natively
        playerItemObservation = player.observe(\.currentItem, options: [.new, .old]) { [weak self] player, change in
            guard let self = self else { return }
            if let newItem = change.newValue as? AVPlayerItem {
                self.handleCurrentItemChange(to: newItem)
            } else if change.newValue == nil && self.isGoogleMode {
                // Queue finished?
                DispatchQueue.main.async {
                    if self.currentParagraphIndex >= self.paragraphs.count - 1 {
                        self.isPlaying = false
                        self.isSessionActive = false
                    }
                }
            }
        }
        
        // Stats Tracking
        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
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
    
    private var isGoogleMode: Bool {
        return (SettingsManager.shared.preferredEngine == "google") && SettingsManager.shared.hasValidGoogleKey
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
        
        // Play
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }
        
        // Pause
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        
        // Skip Forward (Native 30s for Control Center / CarPlay)
        commandCenter.skipForwardCommand.preferredIntervals = [30]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            self?.skip(bySeconds: 30)
            return .success
        }
        
        // Skip Backward (Native 15s for Control Center / CarPlay)
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skip(bySeconds: -15)
            return .success
        }
        
        // Next Track (Headphone buttons double-tap fallback)
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.skip(bySeconds: 30)
            return .success
        }
        
        // Previous Track (Headphone buttons triple-tap fallback)
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.skip(bySeconds: -15)
            return .success
        }
        
        // Scrubbing (Seek)
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] _ in
            guard self != nil else { return .commandFailed }
            // This is tricky with paragraph based playback. 
            // We'll treat the "Track" as the FULL BOOK? Or the single paragraph?
            // Usually easier to treat as single paragraph for scrub, but MPInfo is hard.
            // For now, let's ignore fine-scrubbing inside a paragraph or assume it seeks within the paragraph if Google mode.
            // Actually, let's map it to "percentage of book" if provided? 
            // Standard scrubber is usually "time in track". 
            // Let's Skip implementing scrubbing for this iteration to ensure stability first.
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
        // If the stored index is out of range (e.g. saved with old single-line split),
        // reset to 0 rather than clamping to the end of the book.
        let safeIndex = (initialIndex >= 0 && initialIndex < self.paragraphs.count) ? initialIndex : 0
        self.currentParagraphIndex = safeIndex
        // If we had to reset (stale stored index), immediately persist the correction.
        if safeIndex != initialIndex {
            libraryManager?.updateProgress(for: bookID, index: safeIndex)
        }
        
        self.audioCache.removeAll()
        self.downloadTasks.values.forEach { $0.cancel() }
        self.downloadTasks.removeAll()
        self.playbackGeneration = UUID()
        
        // Preload if Google
        if isGoogleMode {
             // We don't auto-play on load, but we can queue up the first item?
             // Or just pre-fetch.
             Task {
                 await preloadAudio(for: initialIndex)
                 await maintainQueue(currentIndex: initialIndex)
             }
        }
    }
    
    func play() {
        // Ensure Session Active
        do { try AVAudioSession.sharedInstance().setActive(true) } catch { print("Audio Session Error: \(error)") }
        
        // Evaluate Smart Rewind
        if let pauseTime = lastPauseTime {
            let pauseDuration = Date().timeIntervalSince(pauseTime)
            if pauseDuration > 30.0 && isGoogleMode {
                let currentSeconds = player.currentTime().seconds
                if currentSeconds > 0 && !currentSeconds.isNaN && !currentSeconds.isInfinite {
                    // Safe rewind boundary (3 seconds) clamped to 0
                    let newSeconds = max(0.0, currentSeconds - 3.0)
                    let newTime = CMTime(seconds: newSeconds, preferredTimescale: 600)
                    player.seek(to: newTime)
                }
            }
        }
        self.lastPauseTime = nil // Consume timestamp
        
        isSessionActive = true // User intent
        
        if isGoogleMode {
            playGoogle()
        } else {
            playLocal()
        }
    }
    
    func pause() {
        endBackgroundTask()
        isSessionActive = false
        isPlaying = false
        
        self.lastPauseTime = Date() // Record pause boundary
        
        player.pause()
        if localSynthesizer.isSpeaking {
            localSynthesizer.pauseSpeaking(at: .immediate)
        }
        
        updateNowPlayingInfo(playbackRate: 0.0)
    }
    
    func stopEverything() {
        self.playbackGeneration = UUID()
        pause()
        player.removeAllItems()
        itemIndexMap.removeAll()
        appleTTSDebounceTimer?.invalidate()
        currentAppleUtterance = nil
        localSynthesizer.stopSpeaking(at: .immediate)
    }
    
    // MARK: - Navigation
    
    func seek(to percentage: Double) {
        let newIndex = Int(Double(totalParagraphs) * percentage)
        let clampedIndex = min(max(newIndex, 0), totalParagraphs - 1)
        jumpToParagraph(at: clampedIndex)
    }
    
    func restorePosition(index: Int) {
        guard index >= 0 && index < totalParagraphs else { return }
        currentParagraphIndex = index
    }
    
    func skip(bySeconds seconds: Double) {
        guard !paragraphs.isEmpty else { return }
        
        // Native approximation: 15 chars per second at 1.0x playback rate
        let charsPerSecond = 15.0 * Double(playbackRate)
        let targetCharsShift = Int(seconds * charsPerSecond)
        
        var newIndex = currentParagraphIndex
        var shiftAccumulator = 0
        
        if targetCharsShift > 0 { // Forward
            while newIndex < paragraphs.count - 1 && shiftAccumulator < targetCharsShift {
                shiftAccumulator += paragraphs[newIndex].count
                newIndex += 1
            }
        } else if targetCharsShift < 0 { // Backward
            let targetAbsChars = abs(targetCharsShift)
            while newIndex > 0 && shiftAccumulator < targetAbsChars {
                newIndex -= 1
                shiftAccumulator += paragraphs[newIndex].count
            }
        }
        
        jumpToParagraph(at: newIndex)
    }
    
    func setManualPlaybackPosition(index: Int) {
        guard index >= 0 && index < totalParagraphs else { return }
        
        if isPlaying {
            // If playing, jump immediately
            jumpToParagraph(at: index)
        } else {
            // If paused, clear the player entirely to break any background cascades
            self.playbackGeneration = UUID() // Explicitly invalidate stale pre-load task returns
            currentParagraphIndex = index
            player.pause()
            player.removeAllItems()
            itemIndexMap.removeAll()
            appleTTSDebounceTimer?.invalidate()
            currentAppleUtterance = nil
            localSynthesizer.stopSpeaking(at: .immediate)
            
            // Specifically enqueue the EXACT tapped paragraph as the root queue element. 
            // The pipeline will insert it, naturally trigger handleCurrentItemChange, 
            // and spin off the maintainQueue lookahead automatically behind it!
            if isGoogleMode {
                activeTask?.cancel()
                activeTask = Task {
                    let task = await ensureAudioTask(for: index)
                    if let url = try? await task.value {
                        let item = AVPlayerItem(url: url)
                        await MainActor.run {
                            self.itemIndexMap[item] = index
                            if self.player.items().isEmpty {
                                self.player.insert(item, after: nil)
                            }
                            // Remain paused. State is preserved.
                        }
                    }
                }
            }
        }
    }
    
    private func jumpToParagraph(at index: Int) {
        self.playbackGeneration = UUID()
        player.pause()
        player.removeAllItems()
        itemIndexMap.removeAll()
        appleTTSDebounceTimer?.invalidate()
        currentAppleUtterance = nil
        localSynthesizer.stopSpeaking(at: .immediate)
        
        currentParagraphIndex = index
        isSessionActive = true
        activeTask?.cancel()
        
        if isGoogleMode {
            activeTask = Task {
                 await EnqueueAndPlay(from: index)
            }
        } else {
            playLocal()
        }
    }
    
    // MARK: - Apple TTS Implementation
    
    private func playLocal() {
        if localSynthesizer.isPaused {
            localSynthesizer.continueSpeaking()
            isPlaying = true
            updateNowPlayingInfo(playbackRate: Double(playbackRate))
            return
        }
        
        if localSynthesizer.isSpeaking {
             // Already speaking current?
             // If different, we'd have stopped first.
             return
        }
        
        speakLocalParagraph(index: currentParagraphIndex)
    }
    
    private func speakLocalParagraph(index: Int) {
        guard index < paragraphs.count else {
            // End of book
            isPlaying = false
            return
        }
        
        let text = paragraphs[index]
        let utterance = AVSpeechUtterance(string: text)
        
        let appleVoiceID = SettingsManager.shared.selectedAppleVoiceID
        if !appleVoiceID.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: appleVoiceID) {
            utterance.voice = voice
        }
        
        // Apple TTS 'default' is 0.5. 'maximum' is 1.0 (which is absurdly fast, like 5x human speed).
        // 1.0 slider = 0.5 rate
        // 2.0 slider = 0.625 rate
        // 3.0 slider = 0.75 rate
        let baseRate = AVSpeechUtteranceDefaultSpeechRate
        let mappedRate = baseRate + ((playbackRate - 1.0) * 0.125)
        let appleRate = min(max(mappedRate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        utterance.rate = appleRate
        
        self.currentAppleUtterance = utterance
        
        DispatchQueue.main.async {
            self.localSynthesizer.speak(utterance)
            self.isPlaying = true
            self.updateNowPlayingInfo(playbackRate: Double(self.playbackRate))
        }
    }
    
    // MARK: - Google TTS Implementation (AVQueuePlayer Restored)
    
    private func playGoogle() {
        if player.currentItem != nil {
            player.defaultRate = playbackRate
            player.play()
            player.rate = playbackRate
            isPlaying = true
            return
        }
        
        // Empty queue? Start from current
        activeTask?.cancel()
        activeTask = Task {
             await EnqueueAndPlay(from: currentParagraphIndex)
        }
    }
    
    private func EnqueueAndPlay(from index: Int) async {
        guard index < paragraphs.count else { return }
        
        DispatchQueue.main.async { self.isLoading = true }
        let expectedGen = self.playbackGeneration
        
        do {
            let currentTask = await ensureAudioTask(for: index)
            
            let url = try await currentTask.value
            guard self.playbackGeneration == expectedGen else { return }
            
            let item = AVPlayerItem(url: url)
            
            await MainActor.run {
                self.itemIndexMap[item] = index
                
                // Directly insert into the empty player. The change in currentItem will naturally trigger the maintainQueue pipeline via the observer.
                if self.player.items().isEmpty {
                    self.player.insert(item, after: nil)
                }
                
                self.player.defaultRate = self.playbackRate
                self.player.play()
                self.player.rate = self.playbackRate
                self.isPlaying = true
                self.isLoading = false
            }
        } catch {
            print("Playback Error: \(error)")
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    @MainActor
    private func maintainQueue(currentIndex: Int) async {
        let lookahead = 5
        var tasks: [(Int, Task<URL, Error>)] = []
        for i in 1...lookahead {
            let nextIndex = currentIndex + i
            guard nextIndex < paragraphs.count else { break }
            let task = ensureAudioTask(for: nextIndex)
            tasks.append((nextIndex, task))
        }
        
        let expectedGen = self.playbackGeneration
        for (nextIndex, task) in tasks {
            if let url = try? await task.value {
                 guard self.playbackGeneration == expectedGen else { return }
                 let items = self.player.items()
                 let alreadyQueued = items.contains { self.itemIndexMap[$0] == nextIndex }
                 
                 if !alreadyQueued {
                     let newItem = AVPlayerItem(url: url)
                     self.itemIndexMap[newItem] = nextIndex
                     if let last = items.last {
                          self.player.insert(newItem, after: last)
                     } else {
                          self.player.insert(newItem, after: nil)
                     }
                 }
            }
        }
    }
    
    private func handleCurrentItemChange(to item: AVPlayerItem) {
        guard let index = itemIndexMap[item] else { return }
        DispatchQueue.main.async {
            self.currentParagraphIndex = index
            self.updateNowPlayingInfo()
            self.updateDiagnosticDetails()
        }
        
        let expectedGen = self.playbackGeneration
        Task {
            guard self.playbackGeneration == expectedGen else { return }
            await maintainQueue(currentIndex: index)
        }
    }
    
    private func updatePlaybackRate() {
        print("DIAGNOSTIC: updatePlaybackRate called. slider:\(playbackRate)")
        if isPlaying {
            if isGoogleMode {
                player.defaultRate = playbackRate
                player.rate = playbackRate
            } else {
                appleTTSDebounceTimer?.invalidate()
                appleTTSDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
                    guard let self = self, self.isPlaying, !self.isGoogleMode else { return }
                    self.currentAppleUtterance = nil
                    self.localSynthesizer.stopSpeaking(at: .immediate)
                    self.speakLocalParagraph(index: self.currentParagraphIndex)
                }
            }
            updateNowPlayingInfo(playbackRate: Double(playbackRate))
        }
        updateDiagnosticDetails()
    }
    
    private func updateDiagnosticDetails() {
         let engine = self.isGoogleMode ? "Google" : "Apple Fallback!"
         let pRate = String(format: "%.2f", self.playbackRate)
         let aRate = String(format: "%.2f", self.player.rate)
         let cInt = self.player.currentItem != nil ? 1 : 0
         let stat = self.isPlaying ? "Playing" : "Paused"
         
         DispatchQueue.main.async {
             self.diagnosticDetails = "Engine: \(engine) | Slider: \(pRate) | True Rate: \(aRate) | Queue: \(cInt) | \(stat)"
         }
    }
    
    // MARK: - Downloader Logic (Preserved & Simplified)
    
    private func startBackgroundTask() {
         guard backgroundTask == .invalid else { return }
         backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
             self?.endBackgroundTask()
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
    
    // Returns an existing or new task for the index
    @MainActor
    private func ensureAudioTask(for index: Int) -> Task<URL, Error> {
        // If already cached, return a completed task
        if let url = audioCache[index], FileManager.default.fileExists(atPath: url.path) {
            return Task { return url }
        }
        
        // If already downloading, return that task
        if let existing = downloadTasks[index] {
            return existing
        }
        
        // Start new task
        // Wrap network call in Background Task
        startBackgroundTask()
        
        let task = Task<URL, Error> {
            do {
                print("DEBUG: Fetching audio for \(index)")
                let text = paragraphs[index]
                let data = try await ttsClient.fetchAudio(text: text, speed: 1.0)
                let tempDir = FileManager.default.temporaryDirectory
                let fileURL = tempDir.appendingPathComponent("para_\(currentBookID?.uuidString ?? "temp")_\(index).mp3")
                try data.write(to: fileURL)
                
                await MainActor.run { endBackgroundTask() } // End immediately after fetch
                return fileURL
            } catch {
                await MainActor.run { endBackgroundTask() }
                throw error
            }
        }
        
        downloadTasks[index] = task
        
        // Cache on completion (side effect)
        Task {
            if let url = try? await task.value {
                audioCache[index] = url
                downloadTasks[index] = nil
            }
        }
        
        return task
    }
    
    @MainActor
    private func getAudioURL(for index: Int) async throws -> URL {
        return try await ensureAudioTask(for: index).value
    }
    
    // MARK: - MPNowPlayingInfoCenter
    
    private func updateNowPlayingInfo(playbackRate: Double? = nil) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()
        
        // Title & Artist
        info[MPMediaItemPropertyTitle] = bookTitle.isEmpty ? "Book Reader" : bookTitle
        info[MPMediaItemPropertyArtist] = "Book Reader"
        
        // Artwork
        if let cover = coverImage {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: cover.size) { _ in return cover }
        }
        
        // Duration & Progress (Estimated)
        // We use estimation because actual audio duration varies per paragraph.
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
        // Estimate based on 15 chars per second (average reading speed)
        let totalChars = paragraphs.reduce(0) { $0 + $1.count }
        let baseSeconds = Double(totalChars) / 15.0
        // We do NOT adjust by playbackRate here for the *Duration* field in MPInfo,
        // because MPInfo handles rate scaling visually if we provide the base duration and set the rate.
        return baseSeconds
    }
    
    var estimatedElapsedDuration: Double {
        guard currentParagraphIndex < paragraphs.count else { return estimatedTotalDuration }
        let passedChars = paragraphs.prefix(currentParagraphIndex).reduce(0) { $0 + $1.count }
        return Double(passedChars) / 15.0
    }
    
    // MARK: - Helpers
    
    var timeElapsedString: String {
        // Estimation helper
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
        return String(format: "%.1f%%", progress * 100)
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
        cancelSleepTimer() // Clean up any existing timer
        
        sleepTimerRemaining = TimeInterval(minutes * 60)
        sleepTimerActive = true
        
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            if self.sleepTimerRemaining > 0 {
                self.sleepTimerRemaining -= 1
            } else {
                // Time's up!
                self.pause()
                self.cancelSleepTimer()
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
extension AudioController: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard !isGoogleMode else { return }
        
        // Only auto-advance if it's our active tracked utterance
        guard utterance == currentAppleUtterance else { return }
        
        if isSessionActive {
            // Auto-advance
            let next = currentParagraphIndex + 1
            if next < paragraphs.count {
                currentParagraphIndex = next
                speakLocalParagraph(index: next)
            } else {
                isPlaying = false
                isSessionActive = false
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
