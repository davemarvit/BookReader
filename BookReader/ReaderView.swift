import SwiftUI

struct ReaderView: View {
    @EnvironmentObject var audioController: AudioController
    let document: ParsedDocument
    let bookID: UUID
    @ObservedObject var libraryManager: LibraryManager
    
    // Navigation Callbacks
    var onClose: (() -> Void)?
    var onOpenLibrary: (() -> Void)?
    
    // Dragging state
    @State private var isDraggingSlider = false
    @State private var dragProgress: Double = 0.0
    // Scroll state
    @State private var isUserScrolling = false
    @State private var showingMetadata = false
    // Prevent initial scroll layout from resetting position
    @State private var isInitialLoad = true
    
    @Environment(\.presentationMode) var presentationMode
    @State private var showingControls = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text(document.title)
                .font(.headline)
                .lineLimit(1)
                .padding()
            
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
            
            // Hidden Link for Metadata
            NavigationLink(isActive: $showingMetadata, destination: {
                if let book = libraryManager.books.first(where: { $0.id == bookID }) {
                    MetadataView(
                        libraryManager: libraryManager,
                        book: book,
                        onRequestLibrary: onOpenLibrary,
                        onRequestHome: onClose
                    )
                }
            }) { EmptyView() }
            
            // Expanded Text View
            ReaderTextView(
                libraryManager: libraryManager,
                bookID: bookID,
                document: document,
                isDraggingSlider: isDraggingSlider,
                isUserScrolling: $isUserScrolling,
                isInitialLoad: $isInitialLoad
            )
            
            Divider()
            
            ReaderControlsView(
                isDraggingSlider: $isDraggingSlider,
                dragProgress: $dragProgress
            )
        } // End Main VStack
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    // Go Home
                    onClose?()
                }) {
                    Image(systemName: "house.fill")
                        .foregroundColor(.primary)
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    // Go Library
                    onOpenLibrary?()
                }) {
                    Image(systemName: "books.vertical.fill")
                        .foregroundColor(.primary)
                }
            }
        }
        .overlay(
            Group {
                if showingControls {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: { showingMetadata = true }) {
                                Image(systemName: "info.circle")
                                    .font(.title2)
                                    .foregroundColor(.accentColor)
                                    .padding()
                                    .background(Color(UIColor.systemBackground).opacity(0.8))
                                    .clipShape(Circle())
                                    .shadow(radius: 5)
                            }
                            .padding(.bottom, 220) // Adjust based on control height
                            .padding(.trailing, 20)
                        }
                    }
                }
            }
        )
    } // End Body
    
    func getParagraph(at index: Int) -> String {
        return audioController.paragraphs[index]
    }
}

struct ReaderTextView: View {
    @EnvironmentObject var audioController: AudioController
    @ObservedObject var libraryManager: LibraryManager 
    
    let bookID: UUID
    let document: ParsedDocument
    let isDraggingSlider: Bool
    @Binding var isUserScrolling: Bool
    @Binding var isInitialLoad: Bool
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(0..<audioController.totalParagraphs, id: \.self) { (index: Int) in
                        ParagraphRow(
                            text: audioController.paragraphs[index],
                            index: index,
                            currentIndex: audioController.currentParagraphIndex
                        )
                        .id(index)
                    }
                }
                .padding()
            }
            .coordinateSpace(name: "ScrollView")
            .onPreferenceChange(ViewOffsetKey.self) { offsets in
                if isInitialLoad { return }
                
                if isUserScrolling {
                    let sorted = offsets.map { (key: $0.key, val: $0.value) }.sorted { $0.val < $1.val }
                    
                    if let topNode = sorted.first(where: { $0.val >= 0 }) {
                         let index = topNode.key
                         
                         if index != audioController.currentParagraphIndex {
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
                guard audioController.currentBookID == bookID else { return }
                
                libraryManager.updateProgress(for: bookID, index: newIndex)
                
                if !isDraggingSlider && !isUserScrolling {
                    withAnimation {
                        proxy.scrollTo(newIndex, anchor: .top)
                    }
                }
            }
            .onAppear {
                if let book = libraryManager.books.first(where: { $0.id == bookID }) {
                     // Fetch Cover
                     var coverImage: UIImage? = nil
                     if let coverURL = libraryManager.getCoverURL(for: book),
                        let data = try? Data(contentsOf: coverURL) {
                         coverImage = UIImage(data: data)
                     }
                     
                     audioController.loadBook(text: document.text, bookID: bookID, title: book.title, cover: coverImage, initialIndex: book.lastParagraphIndex)
                     
                     if audioController.currentBookID == bookID {
                          // Increased delay to ensure Layout is ready for scrollTo
                          DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                              if !audioController.isSessionActive {
                                  // Use transaction to force immediate jump without animation for 'initial' load
                                  var transaction = Transaction()
                                  transaction.disablesAnimations = true
                                  withTransaction(transaction) {
                                      proxy.scrollTo(audioController.currentParagraphIndex, anchor: .top)
                                  }
                              }
                          }
                     }
                } else {
                     audioController.loadBook(text: document.text, bookID: bookID, title: document.title, cover: nil)
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.isInitialLoad = false
                }
            }
        }
    }
}

struct ReaderControlsView: View {
    @EnvironmentObject var audioController: AudioController
    @Binding var isDraggingSlider: Bool
    @Binding var dragProgress: Double
    
    var body: some View {
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
                    // Elapsed
                    Text(audioController.timeElapsedString)
                        .frame(minWidth: 50, alignment: .leading)
                    Spacer()
                    // Percentage
                    Text(audioController.percentageString)
                        .fontWeight(.bold)
                    Spacer()
                    // Remaining
                    Text("-" + audioController.timeRemainingString)
                         .frame(minWidth: 50, alignment: .trailing)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            // Playback Controls
            HStack(spacing: 20) {
                // 1 Para Back
                Button(action: { audioController.skipBackward() }) {
                    Image(systemName: "chevron.left").font(.title2)
                }
                
                // 5 Paras Back
                Button(action: { audioController.skipBackward(amount: 5) }) {
                    Image(systemName: "chevron.left.2").font(.title2)
                }
                
                Spacer()
                
                // Play/Pause (Centered)
                StablePlayButton(isSessionActive: audioController.isSessionActive) {
                    if audioController.isSessionActive {
                        audioController.pause()
                    } else {
                        audioController.play()
                    }
                }
                
                Spacer()
                
                // 5 Paras Forward
                Button(action: { audioController.skipForward(amount: 5) }) {
                    Image(systemName: "chevron.right.2").font(.title2)
                }
                
                // 1 Para Forward
                Button(action: { audioController.skipForward() }) {
                    Image(systemName: "chevron.right").font(.title2)
                }
            }
            .padding(.horizontal, 30) // Add padding to center play button visually between spacers
            
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
}

struct ParagraphRow: View {
    let text: String
    let index: Int
    let currentIndex: Int
    
    var body: some View {
        Text(text)
            .font(.body)
            .foregroundColor(.primary)
            .padding(4)
            .background(
                index == currentIndex ? Color.yellow.opacity(0.3) : Color.clear
            )
            .cornerRadius(4)
            .textSelection(.enabled)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ViewOffsetKey.self,
                        value: [index: geo.frame(in: .named("ScrollView")).minY]
                    )
                }
            )
    }
}

struct ViewOffsetKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

// ZStack-based Button to prevent SF Symbol swapping flicker
// MARK: - Equatable to prevent redundancy
struct StablePlayButton: View, Equatable {
    let isSessionActive: Bool
    let action: () -> Void
    
    static func == (lhs: StablePlayButton, rhs: StablePlayButton) -> Bool {
        return lhs.isSessionActive == rhs.isSessionActive
    }
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Play Icon
                Image(systemName: "play.circle.fill")
                    .resizable()
                    .frame(width: 60, height: 60)
                    .foregroundColor(.accentColor)
                    .opacity(isSessionActive ? 0 : 1)
                
                // Pause Icon
                Image(systemName: "pause.circle.fill")
                    .resizable()
                    .frame(width: 60, height: 60)
                    .foregroundColor(.accentColor)
                    .opacity(isSessionActive ? 1 : 0)
            }
            // Use transaction to prevent parent animations from leaking in
            .transaction { transaction in
                transaction.animation = nil
            }
        }
    }
}
