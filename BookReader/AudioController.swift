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
    
    @Published var currentParagraphIndex: Int = 0 {
        didSet {
            updateNowPlayingInfo()
        }
    }
    
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    // Stable state validation
    @Published var isSessionActive: Bool = false
    
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
    private let player = AVQueuePlayer()
    private var playerLooper: Any? // Not using looper, managing queue manually
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
    
    // Queue Management
    // Maps [AVPlayerItem : ParagraphIndex] to track which item corresponds to which paragraph
    private var itemIndexMap: [AVPlayerItem: Int] = [:]

    override init() {
        super.init()
        setupAudioSession()
        setupRemoteCommandCenter()
        localSynthesizer.delegate = self
        
        // Observe AVQueuePlayer currentItem changes to auto-advance index
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
                guard let self = self, self.isPlaying else { return }
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
        
        // Next Track (Next Paragraph)
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.skipForward()
            return .success
        }
        
        // Previous Track (Prev Paragraph)
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.skipBackward()
            return .success
        }
        
        // Scrubbing (Seek)
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self, let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
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
        self.paragraphs = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        self.totalParagraphs = self.paragraphs.count
        self.currentParagraphIndex = initialIndex
        
        self.audioCache.removeAll()
        self.downloadTasks.values.forEach { $0.cancel() }
        self.downloadTasks.removeAll()
        
        // Preload if Google
        if isGoogleMode {
             // We don't auto-play on load, but we can queue up the first item?
             // Or just pre-fetch.
             Task {
                 await preloadAudio(for: initialIndex)
                 await preloadAudio(for: initialIndex + 1)
             }
        }
    }
    
    func play() {
        // Ensure Session Active
        do { try AVAudioSession.sharedInstance().setActive(true) } catch { print("Audio Session Error: \(error)") }
        
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
        
        player.pause()
        if localSynthesizer.isSpeaking {
            localSynthesizer.pauseSpeaking(at: .immediate)
        }
        
        updateNowPlayingInfo(playbackRate: 0.0)
    }
    
    func stopEverything() {
        pause()
        player.removeAllItems()
        itemIndexMap.removeAll()
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
    
    func skipForward(amount: Int = 1) {
        let nextIndex = min(currentParagraphIndex + amount, paragraphs.count - 1)
        jumpToParagraph(at: nextIndex)
    }
    
    func skipBackward(amount: Int = 1) {
        let prevIndex = max(currentParagraphIndex - amount, 0)
        jumpToParagraph(at: prevIndex)
    }
    
    private func jumpToParagraph(at index: Int) {
        // Stop current
        player.pause()
        player.removeAllItems()
        itemIndexMap.removeAll()
        localSynthesizer.stopSpeaking(at: .immediate)
        
        currentParagraphIndex = index
        isSessionActive = true
        activeTask?.cancel()
        
        if isGoogleMode {
            // Re-build queue starting from index
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
        
        // Map rate
        let appleRate = min(max(AVSpeechUtteranceDefaultSpeechRate * playbackRate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        utterance.rate = appleRate
        
        DispatchQueue.main.async {
            self.localSynthesizer.speak(utterance)
            self.isPlaying = true
            self.updateNowPlayingInfo(playbackRate: Double(self.playbackRate))
        }
    }
    
    // MARK: - Google TTS Implementation (AVQueuePlayer)
    
    private func playGoogle() {
        if player.currentItem != nil {
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
        // 1. Fetch current
        // 2. Insert
        // 3. Play
        // 4. Fetch Next & Insert
        
        guard index < paragraphs.count else { return }
        
        DispatchQueue.main.async { self.isLoading = true }
        
        do {
            let url = try await getAudioURL(for: index)
            let item = AVPlayerItem(url: url)
            
            // Lock UI thread for queue manipulation
            await MainActor.run {
                self.itemIndexMap[item] = index
                if self.player.items().isEmpty {
                    self.player.insert(item, after: nil)
                }
                
                self.player.play()
                self.player.rate = self.playbackRate
                self.isPlaying = true
                self.isLoading = false
            }
            
            // Lookahead
            await maintainQueue(currentIndex: index)
            
        } catch {
            print("Playback Error: \(error)")
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    /// Ensures we have the next few items in the queue
    private func maintainQueue(currentIndex: Int) async {
        let lookahead = 2
        for i in 1...lookahead {
            let nextIndex = currentIndex + i
            guard nextIndex < paragraphs.count else { break }
            
            // Check if already in queue?
            // AVQueuePlayer doesn't easily let us inspect index of items relative to model, 
            // so we'll rely on our rigorous 'itemIndexMap' or just check if we have enough items.
            // Simplify: Just try to fetch and append if NOT duplicate.
            
            // Optimization: If `downloadTasks` already has it, we wait.
            // If already cached, fast.
            
            // Perform fetch
            if let url = try? await getAudioURL(for: nextIndex) {
                // Check if this particular URL/Index is already in the player's items
                // This must be main thread check
                await MainActor.run {
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
    }
    
    private func handleCurrentItemChange(to item: AVPlayerItem) {
        guard let index = itemIndexMap[item] else { return }
        print("DEBUG: AVQueuePlayer advanced to paragraph \(index)")
        
        DispatchQueue.main.async {
            self.currentParagraphIndex = index
            self.updateNowPlayingInfo()
        }
        
        // Trigger maintenance (prefetch next items)
        Task {
            await maintainQueue(currentIndex: index)
        }
    }
    
    private func updatePlaybackRate() {
        if isPlaying {
            if isGoogleMode {
                player.rate = playbackRate
            } else {
                // Apple TTS rate can't be changed mid-utterance easily without stopping?
                // Actually AVSpeechSynthesizer stop/continue works, but rate is on Utterance.
                // So dynamic rate change for Apple TTS is hard. Ignore for now.
            }
            updateNowPlayingInfo(playbackRate: Double(playbackRate))
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
        _ = try? await getAudioURL(for: index)
    }
    
    private func getAudioURL(for index: Int) async throws -> URL {
        if let url = audioCache[index], FileManager.default.fileExists(atPath: url.path) {
             return url
        }
        
        if let existingTask = downloadTasks[index] {
            return try await existingTask.value
        }
        
        // Wrap network call in Background Task
        await MainActor.run { startBackgroundTask() }
        
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
        
        do {
            let url = try await task.value
            audioCache[index] = url
            downloadTasks[index] = nil
            return url
        } catch {
            downloadTasks[index] = nil
            throw error
        }
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
}

// MARK: - Apple TTS Delegate
extension AudioController: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard !isGoogleMode else { return }
        
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
