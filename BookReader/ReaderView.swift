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

    // Search State
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var searchResults: [Int] = []
    @State private var currentSearchMatchIndex = 0
    @FocusState private var isSearchFieldFocused: Bool
    @State private var targetScrollIndex: Int?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text(document.title)
                .font(.headline)
                .lineLimit(1)
                .padding()
            
            Divider()
            
            // Search Bar Overlay
            if isSearching {
                HStack {
                    TextField("Find in page...", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .focused($isSearchFieldFocused)
                        .onChange(of: searchText) { newValue in
                            performSearch(query: newValue)
                        }
                    
                    if !searchResults.isEmpty {
                        Text("\(currentSearchMatchIndex + 1) of \(searchResults.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button(action: { previousMatch() }) {
                            Image(systemName: "chevron.up")
                        }
                        
                        Button(action: { nextMatch() }) {
                            Image(systemName: "chevron.down")
                        }
                    }
                    
                    Button("Done") {
                        isSearching = false
                        searchText = ""
                        searchResults = []
                        isSearchFieldFocused = false
                        targetScrollIndex = nil
                    }
                }
                .padding(8)
                .background(Color(UIColor.systemBackground))
                .transition(.move(edge: .top))
                Divider()
            }
            
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
                isInitialLoad: $isInitialLoad,
                searchResults: searchResults,
                searchText: searchText,
                targetScrollIndex: $targetScrollIndex
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
                HStack {
                    // Search Button
                    Button(action: {
                        withAnimation {
                            isSearching.toggle()
                            if isSearching {
                                isSearchFieldFocused = true
                            }
                        }
                    }) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.primary)
                    }
                    
                    Button(action: {
                        // Go Library
                        onOpenLibrary?()
                    }) {
                        Image(systemName: "books.vertical.fill")
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .overlay(
            Group {
                if showingControls && !isSearching {
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
    
    func performSearch(query: String) {
        if query.isEmpty {
            searchResults = []
            return
        }
        
        let lowerQuery = query.lowercased()
        searchResults = audioController.paragraphs.enumerated().compactMap { index, text in
            if text.localizedCaseInsensitiveContains(lowerQuery) {
                return index
            }
            return nil
        }
        currentSearchMatchIndex = 0
        if let first = searchResults.first {
            targetScrollIndex = first
            // Sync audio position
            if !audioController.isSessionActive {
                audioController.restorePosition(index: first)
            }
        }
    }
    
    func nextMatch() {
        if searchResults.isEmpty { return }
        currentSearchMatchIndex = (currentSearchMatchIndex + 1) % searchResults.count
        let newIndex = searchResults[currentSearchMatchIndex]
        targetScrollIndex = newIndex
        
        // Sync audio position
        if !audioController.isSessionActive {
            audioController.restorePosition(index: newIndex)
        }
    }
    
    func previousMatch() {
        if searchResults.isEmpty { return }
        currentSearchMatchIndex = (currentSearchMatchIndex - 1 + searchResults.count) % searchResults.count
        let newIndex = searchResults[currentSearchMatchIndex]
        targetScrollIndex = newIndex
        
        // Sync audio position
        if !audioController.isSessionActive {
            audioController.restorePosition(index: newIndex)
        }
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
    
    // Search Props
    let searchResults: [Int]
    let searchText: String
    @Binding var targetScrollIndex: Int?
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(0..<audioController.totalParagraphs, id: \.self) { (index: Int) in
                        ParagraphRow(
                            text: audioController.paragraphs[index],
                            index: index,
                            currentIndex: audioController.currentParagraphIndex,
                            searchText: searchText,
                            isSearchResult: searchResults.contains(index)
                        )
                        .id(index)
                    }
                }
                .padding()
            }
            .coordinateSpace(name: "ScrollView")
            .onChange(of: targetScrollIndex) { index in
                if let idx = index {
                    // Scroll to the requested search result
                    withAnimation {
                         proxy.scrollTo(idx, anchor: .center)
                    }
                }
            }
            .onChange(of: searchResults) { results in
                if let first = results.first {
                    withAnimation { proxy.scrollTo(first, anchor: .center) }
                }
            }
            // Logic to scroll when 'currentSearchMatchIndex' changes in parent is tricky without binding.
            // WORKAROUND: We can expose a Binding<Int?> for 'scrollToRequest' from parent.
            // BUT, for now, let's just make the parent 'jump' the audio? 
            // No, user might want to find without losing spot.
            // Let's rely on the user scrolling OR simple highlighting. 
            // Actually, to make Next/Prev work, we really need the proxy.
            // Let's add specific logic to ReaderTextView to handle external scroll requests?
            // Simpler: Just rely on 'audioController' for NOW? No, that changes playback.
            
            // Let's add @Binding var requestedScrollIndex: Int?
            
            // For now, I'll stick to updating the view to support highlighting first.
            
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
    let searchText: String
    let isSearchResult: Bool
    
    var body: some View {
        Text(highlightObject(for: text, query: searchText))
            .font(.body)
            .foregroundColor(.primary)
            .padding(4)
            .background(
                // Priority: Current Playback = Yellow, Search Match = Gray?
                index == currentIndex ? Color.yellow.opacity(0.3) : (isSearchResult ? Color.gray.opacity(0.2) : Color.clear)
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
    
    func highlightObject(for text: String, query: String) -> AttributedString {
        var attributed = AttributedString(text)
        if query.isEmpty { return attributed }
        
        // Find all ranges
        // Helper to loop
        var searchRange = attributed.startIndex..<attributed.endIndex
        while let range = attributed[searchRange].range(of: query, options: .caseInsensitive) {
            attributed[range].backgroundColor = .yellow
            attributed[range].foregroundColor = .black
            searchRange = range.upperBound..<attributed.endIndex
        }
        return attributed
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
