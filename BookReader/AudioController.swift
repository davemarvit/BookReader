import Foundation
import AVFoundation
import Combine

class AudioController: ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var playbackRate: Float = UserDefaults.standard.float(forKey: "playbackRate") == 0 ? 1.0 : UserDefaults.standard.float(forKey: "playbackRate") {
        didSet {
            UserDefaults.standard.set(playbackRate, forKey: "playbackRate")
            if isPlaying {
                player.rate = playbackRate
            }
        }
    }
    @Published var currentParagraphIndex: Int = 0
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    // Stable state validation (ignores buffer underruns)
    @Published var isSessionActive: Bool = false
    
    // Task management
    private var activeTask: Task<Void, Never>?
    
    @Published var totalParagraphs: Int = 0
    
    // Progress (0.0 to 1.0)
    var progress: Double {
        guard totalParagraphs > 0 else { return 0 }
        return Double(currentParagraphIndex) / Double(totalParagraphs)
    }
    
    // Time Estimation
    var timeRemainingString: String {
        let remainingParagraphs = paragraphs.suffix(from: currentParagraphIndex)
        let charCount = remainingParagraphs.reduce(0) { $0 + $1.count }
        
        // Approximation: ~15 chars per second at 1.0x speed
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

    private let player = AVQueuePlayer()
    private let ttsClient = GoogleTTSClient()
    
    // Cache for downloaded audio: [ParagraphIndex: URL]
    private var audioCache: [Int: URL] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Observe player status to update UI
        player.publisher(for: \.rate).sink { [weak self] rate in
            self?.isPlaying = rate > 0
        }.store(in: &cancellables)
    }

    func loadBook(text: String) {
        self.paragraphs = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        self.totalParagraphs = self.paragraphs.count
        self.currentParagraphIndex = 0
        self.isSessionActive = false // Reset
        self.audioCache.removeAll()
        self.player.removeAllItems()
        
        // Preload first few paragraphs
        Task {
            await preloadAudio(for: 0)
            await preloadAudio(for: 1)
        }
    }
    
    func seek(to percentage: Double) {
        let newIndex = Int(Double(totalParagraphs) * percentage)
        let clampedIndex = min(max(newIndex, 0), totalParagraphs - 1)
        
        if clampedIndex != currentParagraphIndex {
            jumpToParagraph(at: clampedIndex)
        }
    }
    
    private func jumpToParagraph(at index: Int) {
        player.pause()
        currentParagraphIndex = index
        isSessionActive = true // Treat seek as intent to play? Or just keep current state?
        // User probably expects it to pause if it was paused? 
        // Let's assume we maintain isSessionActive status OR auto-play.
        // Usually seek implies play in this context.
        
        // Cancel previous loading task
        activeTask?.cancel()
        
        activeTask = Task {
            await playParagraph(at: index)
        }
    }

    func restorePosition(index: Int) {
        guard index >= 0 && index < totalParagraphs else { return }
        currentParagraphIndex = index
    }
    
    func play() {
        isSessionActive = true
        if player.currentItem == nil {
             // If stopped, play current
            activeTask?.cancel()
            activeTask = Task {
                await playParagraph(at: currentParagraphIndex)
            }
        } else {
            // Check if we finished?
            if player.currentTime() == player.currentItem?.duration {
                 // Restart or move next?
                activeTask?.cancel()
                activeTask = Task {
                    await playParagraph(at: currentParagraphIndex)
                }
            } else {
                player.rate = playbackRate
            }
        }
    }
    
    func pause() {
        isSessionActive = false
        player.pause()
    }
    
    func skipForward() {
        let nextIndex = currentParagraphIndex + 1
        guard nextIndex < paragraphs.count else { return }
        
        player.pause()
        currentParagraphIndex = nextIndex
        isSessionActive = true
        Task {
            await playParagraph(at: nextIndex)
        }
    }
    
    func skipBackward() {
        let prevIndex = currentParagraphIndex - 1
        guard prevIndex >= 0 else { return }
        
        player.pause()
        currentParagraphIndex = prevIndex
        isSessionActive = true
        Task {
            await playParagraph(at: prevIndex)
        }
    }
    
    var paragraphs: [String] = []
    
    private func playParagraph(at index: Int) async {
        guard index < paragraphs.count else { return }
        
        let paragraphText = paragraphs[index]
        if paragraphText.count > 4800 {
            DispatchQueue.main.async {
                self.errorMessage = "Paragraph too long for TTS (\(paragraphText.count) chars). skipping."
                self.isLoading = false
            }
            return
        }
        
        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = nil
        }
        
        do {
            let url = try await getAudioURL(for: index)
            
            // Check cancellation
            if Task.isCancelled { return }
            
            let item = AVPlayerItem(url: url)
            
            NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
                .sink { [weak self] _ in
                    self?.onParagraphFinished()
                }
                .store(in: &cancellables)
            
            DispatchQueue.main.async {
                self.player.replaceCurrentItem(with: item)
                self.player.rate = self.playbackRate
                self.isLoading = false
            }
            
            await preloadAudio(for: index + 1)
            
        } catch {
            print("Error playing paragraph: \(error)")
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = "Playback Error: \(error.localizedDescription)"
            }
        }
    }
    
    private func onParagraphFinished() {
        // Auto-advance
        let nextIndex = currentParagraphIndex + 1
        if nextIndex < paragraphs.count {
            currentParagraphIndex = nextIndex
            Task {
                await playParagraph(at: nextIndex)
            }
        } else {
            DispatchQueue.main.async {
                self.player.pause()
                self.isPlaying = false
                self.isSessionActive = false
            }
        }
    }
    
    private func preloadAudio(for index: Int) async {
        guard index < paragraphs.count else { return }
        if audioCache[index] != nil { return } // Already cached
        
        _ = try? await getAudioURL(for: index)
    }
    
    private func getAudioURL(for index: Int) async throws -> URL {
        if let url = audioCache[index] {
            return url
        }
        
        let text = paragraphs[index]
        let data = try await ttsClient.fetchAudio(text: text, speed: 1.0) // We handle speed in player, so request 1x
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("para_\(index).mp3")
        try data.write(to: fileURL)
        
        audioCache[index] = fileURL
        return fileURL
    }
}
