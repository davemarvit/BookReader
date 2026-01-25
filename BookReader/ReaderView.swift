import SwiftUI

struct ReaderView: View {
    @EnvironmentObject var audioController: AudioController
    let document: ParsedDocument
    let bookID: UUID
    @ObservedObject var libraryManager: LibraryManager
    
    // Dragging state
    @State private var isDraggingSlider = false
    @State private var dragProgress: Double = 0.0
    // Scroll state
    @State private var isUserScrolling = false
    @State private var showingMetadata = false
    // Prevent initial scroll layout from resetting position
    @State private var isInitialLoad = true
    
    var body: some View {
        VStack(spacing: 0) {
            // ... existing UI code ...
            // Header
            Text(document.title)
                .font(.headline)
                .lineLimit(1)
                .padding()
            
            Divider()
            
            // Expanded Text View
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(0..<audioController.totalParagraphs, id: \.self) { index in
                            Text(getParagraph(at: index))
                                .font(.body) // Fixed font size to prevent jitter
                                .foregroundColor(.primary)
                                .padding(4) // Add padding for the background
                                .background(
                                    index == audioController.currentParagraphIndex ? Color.yellow.opacity(0.3) : Color.clear
                                )
                                .cornerRadius(4)
                                .textSelection(.enabled) // Enable Look Up, Copy, Share
                                .id(index)
                                .background( // Keep the geometry reader for scroll tracking
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: ViewOffsetKey.self,
                                            value: [index: geo.frame(in: .named("ScrollView")).minY]
                                        )
                                    }
                                )

                        }
                    }
                    .padding()
                }
                .coordinateSpace(name: "ScrollView")
                .onPreferenceChange(ViewOffsetKey.self) { offsets in
                    // Prevent initial layout from resetting index to 0
                    if isInitialLoad { return }
                    
                    // Sync ONLY if user is actively scrolling. 
                    // We don't want layout changes or momentum from "snap" to overwrite our logical index.
                    if isUserScrolling {
                        let sorted = offsets.map { (key: $0.key, val: $0.value) }.sorted { $0.val < $1.val }
                        
                        // Find the top-most visible paragraph
                        if let topNode = sorted.first(where: { $0.val >= 0 }) {
                             let index = topNode.key
                             
                             if index != audioController.currentParagraphIndex {
                                 // Only update if we are not playing/session active (prevent fighting with auto-scroll)
                                 // OR if we treat user scroll as "override"
                                 if !audioController.isSessionActive {
                                     audioController.restorePosition(index: index)
                                 }
                             }
                        }
                    }
                }
                .simultaneousGesture(
                    DragGesture().onChanged { _ in
                        isUserScrolling = true
                    }.onEnded { _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.isUserScrolling = false
                        }
                    }
                )
                .onChange(of: audioController.currentParagraphIndex) { newIndex in
                    // Save progress ONLY if the controller is handling THIS book.
                    // This prevents "zombie" views (previous book views still in memory) from overwriting
                    // their book's progress when the controller loads a new book.
                    guard audioController.currentBookID == bookID else { return }
                    
                    libraryManager.updateProgress(for: bookID, index: newIndex)
                    
                    // Only auto-scroll if:
                    // 1. User is NOT dragging
                    // 2. User has NOT scrolled away (Lazy approach: check if isUserScrolling)
                    // Unfortunately we don't know if they scrolled away and stopped.
                    // But if 'isSessionActive' is true, we should snap back, UNLESS we assume they want to read ahead.
                    
                    // Simple Rule: If actively playing, we snap.
                    // The user complained about snap-back.
                    // Let's only snap if we are confident they are "following".
                    // For now, let's keep it simple: If they are NOT dragging, we snap.
                    // If they scrolled away and stopped, they will get snapped back on next para.
                    
                    if !isDraggingSlider && !isUserScrolling {
                        withAnimation {
                            proxy.scrollTo(newIndex, anchor: .top)
                        }
                    }
                }
                .onAppear {
                    // Load book with saved position
                    // We fetch the book metadata to get the lastParagraphIndex
                    if let book = libraryManager.books.first(where: { $0.id == bookID }) {
                        audioController.loadBook(text: document.text, bookID: bookID, initialIndex: book.lastParagraphIndex)
                        
                        // If the book was already loaded, loadBook returns early.
                        // We ensure visual sync:
                        if audioController.currentBookID == bookID {
                             DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                 // If we are not playing, or if we just arrived, sync scroll
                                 if !audioController.isSessionActive {
                                     proxy.scrollTo(audioController.currentParagraphIndex, anchor: .top)
                                 }
                             }
                        }
                    } else {
                        // Fallback
                        audioController.loadBook(text: document.text, bookID: bookID)
                    }
                    
                    // Disable initial load guard after layout settles
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.isInitialLoad = false
                    }
                }
            }
            
            Divider()
            
            // Error Overlay
            if let error = audioController.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(8)
                    .padding(.horizontal)
            }
            
            // Controls Area
            VStack(spacing: 20) {
                
                // Progress Bar & Time
                VStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { self.isDraggingSlider ? self.dragProgress : self.audioController.progress },
                            set: { newVal in
                                self.isDraggingSlider = true
                                self.dragProgress = newVal
                            }
                        ),
                        in: 0...1.0,
                        onEditingChanged: { editing in
                            self.isDraggingSlider = editing
                            if !editing {
                                self.audioController.seek(to: self.dragProgress)
                            }
                        }
                    )
                    
                    HStack {
                        Text(audioController.percentageString)
                        Spacer()
                        Text("\(audioController.timeRemainingString) remaining")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                
                // Playback Controls
                HStack(spacing: 40) {
                    Button(action: { audioController.skipBackward() }) {
                        Image(systemName: "backward.end.fill").font(.title2)
                    }
                    
                    Button(action: {
                        if audioController.isPlaying {
                            audioController.pause()
                        } else {
                            audioController.play()
                        }
                    }) {
                        Image(systemName: audioController.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .resizable()
                            .frame(width: 50, height: 50)
                    }
                    
                    Button(action: { audioController.skipForward() }) {
                        Image(systemName: "forward.end.fill").font(.title2)
                    }
                    
                    // Info Button
                    Button(action: { showingMetadata = true }) {
                        Image(systemName: "info.circle")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                    }
                }
                
                // Speed Control
                HStack {
                    Image(systemName: "tortoise.fill").font(.caption)
                    Slider(value: $audioController.playbackRate, in: 0.5...3.0, step: 0.1)
                    Image(systemName: "hare.fill").font(.caption)
                    Text(String(format: "%.1fx", audioController.playbackRate))
                        .font(.caption)
                        .frame(width: 40)
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 30)
            .background(Color(UIColor.systemBackground))
            .shadow(radius: 10, y: -5)

            
            // Hidden Link for Metadata
            NavigationLink(isActive: $showingMetadata, destination: {
                if let book = libraryManager.books.first(where: { $0.id == bookID }) {
                    MetadataView(libraryManager: libraryManager, book: book)
                }
            }) { EmptyView() }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
    
    func getParagraph(at index: Int) -> String {
        // We need to access paragraphs securely. 
        // Since AudioController paragraphs is private, let's just make it public or access via method.
        // For now, assume we updated AudioController to make 'paragraphs' internal/public.
        return audioController.paragraphs[index]
    }
}

struct ViewOffsetKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}
