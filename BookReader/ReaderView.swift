import SwiftUI

struct ReaderView: View {
    @StateObject var audioController = AudioController()
    let document: ParsedDocument
    let bookID: UUID
    @ObservedObject var libraryManager: LibraryManager
    
    // Dragging state
    @State private var isDraggingSlider = false
    @State private var dragProgress: Double = 0.0
    // Scroll state
    @State private var isUserScrolling = false
    
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
                                .id(index)
                                .background( // Keep the geometry reader for scroll tracking
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: ViewOffsetKey.self,
                                            value: [index: geo.frame(in: .named("ScrollView")).minY]
                                        )
                                    }
                                )
                                .onTapGesture {
                                    audioController.seek(to: Double(index) / Double(audioController.totalParagraphs))
                                }
                        }
                    }
                    .padding()
                }
                .coordinateSpace(name: "ScrollView")
                .onPreferenceChange(ViewOffsetKey.self) { offsets in
                    // Sync only if session is NOT active (Paused)
                    if isUserScrolling || !audioController.isSessionActive {
                        let sorted = offsets.map { (key: $0.key, val: $0.value) }.sorted { $0.val < $1.val }
                        
                        if let topNode = sorted.first(where: { $0.val >= 0 }) {
                             let index = topNode.key
                             
                             if index != audioController.currentParagraphIndex {
                                 // Double check strict conditions to prevent jumping
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
                    // Save progress
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
                    audioController.loadBook(text: document.text)
                    
                    if let book = libraryManager.books.first(where: { $0.id == bookID }) {
                        // Set the initial index without triggering animations
                         DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                             audioController.restorePosition(index: book.lastParagraphIndex)
                             proxy.scrollTo(book.lastParagraphIndex, anchor: .top)
                         }
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
