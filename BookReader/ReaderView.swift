import SwiftUI

struct ReaderView: View {
    @EnvironmentObject var audioController: AudioController
    let document: ParsedDocument
    let bookID: UUID
    @ObservedObject var libraryManager: LibraryManager
    @ObservedObject var settings = SettingsManager.shared
    
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
    @State private var isShowingTOC = false

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
            
            // Custom Search Bar
            if isSearching {
                HStack {
                    TextField("Search book...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .focused($isSearchFieldFocused)
                        .padding(.leading)
                        .submitLabel(.search)
                    
                    Button("Cancel") {
                        withAnimation {
                            isSearching = false
                            searchText = ""
                        }
                    }
                    .padding(.trailing)
                }
                .padding(.vertical, 8)
                .background(Color(UIColor.systemBackground))
                .transition(.move(edge: .top).combined(with: .opacity))
                
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
            .safeAreaInset(edge: .bottom) {
                if showingControls {
                    ReaderControlsView(
                        isDraggingSlider: $isDraggingSlider,
                        dragProgress: $dragProgress,
                        isShowingTOC: $isShowingTOC
                    )
                    .transition(.move(edge: .bottom))
                    .background(settings.currentTheme.backgroundColor.opacity(0.96).ignoresSafeArea())
                    .overlay(Rectangle().frame(width: nil, height: 1, alignment: .top).foregroundColor(settings.currentTheme.textColor.opacity(0.15)), alignment: .top)
                }
            }
        } // End Main VStack
        .background(settings.currentTheme.backgroundColor.edgesIgnoringSafeArea(.all))
        .preferredColorScheme((settings.readerTheme == "dark" || settings.readerTheme == "lowContrastDark") ? .dark : (settings.readerTheme == "system" ? nil : .light))
        .onChange(of: searchText) { _, newValue in
            performSearch(query: newValue)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    if isSearching && !searchResults.isEmpty {
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
                    
                    // Sleep Timer Menu
                    Menu {
                        if audioController.sleepTimerActive {
                            Button("Cancel Timer", role: .destructive) {
                                audioController.cancelSleepTimer()
                            }
                            Divider()
                        }
                        Button("15 Minutes") { audioController.startSleepTimer(minutes: 15) }
                        Button("30 Minutes") { audioController.startSleepTimer(minutes: 30) }
                        Button("45 Minutes") { audioController.startSleepTimer(minutes: 45) }
                        Button("60 Minutes") { audioController.startSleepTimer(minutes: 60) }
                    } label: {
                        HStack(spacing: 4) {
                            if audioController.sleepTimerActive {
                                Text(audioController.sleepTimerString)
                                    .font(.caption.monospacedDigit())
                            }
                            Image(systemName: audioController.sleepTimerActive ? "moon.fill" : "moon")
                        }
                        .foregroundColor(audioController.sleepTimerActive ? .accentColor : (isSearching ? .primary : settings.currentTheme.textColor))
                    }
                    
                    // Search Button
                    Button(action: {
                        withAnimation {
                            isSearching.toggle()
                            // When opening search, SwiftUI focus works best with a slight delay
                            if isSearching {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    isSearchFieldFocused = true
                                }
                            } else {
                                searchText = ""
                            }
                        }
                    }) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(isSearching ? .accentColor : .primary)
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
                                    .foregroundColor(settings.currentTheme.textColor)
                                    .padding()
                                    .background(settings.currentTheme.backgroundColor.opacity(0.9))
                                    .clipShape(Circle())
                                    .shadow(color: settings.currentTheme.textColor.opacity(0.2), radius: 5)
                            }
                            .padding(.bottom, 220) // Adjust based on control height
                            .padding(.trailing, 20)
                        }
                    }
                }
            }
        )
        .sheet(isPresented: $isShowingTOC) {
            if !document.chapters.isEmpty {
                NavigationStack {
                    List(document.chapters) { chapter in
                        Button(action: {
                            audioController.setManualPlaybackPosition(index: chapter.paragraphIndex)
                            isShowingTOC = false
                        }) {
                            HStack {
                                Text(chapter.title)
                                    .foregroundColor(.primary)
                                Spacer()
                                if audioController.currentParagraphIndex >= chapter.paragraphIndex {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                    .navigationTitle("Table of Contents")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { isShowingTOC = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            } else {
                NavigationStack {
                    VStack(spacing: 20) {
                        Image(systemName: "book.closed")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No Table of Contents")
                            .foregroundColor(.secondary)
                    }
                    .navigationTitle("Table of Contents")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { isShowingTOC = false }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
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
    @ObservedObject var settings = SettingsManager.shared
    
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
                        .onTapGesture {
                            audioController.setManualPlaybackPosition(index: index)
                        }
                    }
                }
                .padding()
            }
            .coordinateSpace(name: "ScrollView")
            .onChange(of: targetScrollIndex) { _, index in
                if let idx = index {
                    withAnimation {
                         proxy.scrollTo(idx, anchor: .center)
                    }
                }
            }
            .onChange(of: searchResults) { _, results in
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
            .onChange(of: audioController.currentParagraphIndex) { _, newIndex in
                guard audioController.currentBookID == bookID else { return }
                libraryManager.updateProgress(for: bookID, index: newIndex)
                if !isDraggingSlider && !isUserScrolling {
                    withAnimation {
                        proxy.scrollTo(newIndex, anchor: .top)
                    }
                }
            }
            // Scroll to the new position when the slider is released.
            // A brief async hop ensures seek() has finished updating currentParagraphIndex
            // before we scroll (the @State and @Published updates race otherwise).
            .onChange(of: isDraggingSlider) { _, dragging in
                if !dragging && !isUserScrolling {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(audioController.currentParagraphIndex, anchor: .top)
                        }
                    }
                }
            }
            .onChange(of: audioController.isPlaying) { _, playing in
                if playing && !isDraggingSlider && !isUserScrolling {
                    withAnimation {
                        proxy.scrollTo(audioController.currentParagraphIndex, anchor: .top)
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
    @ObservedObject var settings = SettingsManager.shared
    @Binding var isDraggingSlider: Bool
    @Binding var dragProgress: Double
    @Binding var isShowingTOC: Bool
    
    @State private var wasPlayingBeforeDrag = false
    
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
                        if editing {
                            self.wasPlayingBeforeDrag = self.audioController.isPlaying
                            if self.wasPlayingBeforeDrag {
                                self.audioController.pause()
                            }
                        } else {
                            self.audioController.seek(to: self.dragProgress, playAfterSeek: self.wasPlayingBeforeDrag)
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
                .foregroundColor(settings.currentTheme.textColor.opacity(0.7))
            }
            .padding(.horizontal)
            
            // Playback Controls
            HStack(spacing: 20) {
                // 30 Secs Back
                Button(action: { audioController.skip(bySeconds: -30) }) {
                    Image(systemName: "gobackward.30").font(.title2)
                }
                
                // 15 Secs Back
                Button(action: { audioController.skip(bySeconds: -15) }) {
                    Image(systemName: "gobackward.15").font(.title2)
                }
                
                Spacer()
                
                // Play/Pause (Centered)
                StablePlayButton(isPlaying: audioController.isPlaying) {
                    if audioController.isPlaying {
                        audioController.pause()
                    } else {
                        audioController.play()
                    }
                }
                
                Spacer()
                
                // 15 Secs Forward
                Button(action: { audioController.skip(bySeconds: 15) }) {
                    Image(systemName: "goforward.15").font(.title2)
                }
                
                // 30 Secs Forward
                Button(action: { audioController.skip(bySeconds: 30) }) {
                    Image(systemName: "goforward.30").font(.title2)
                }
            }
            .padding(.horizontal, 30) // Add padding to center play button visually between spacers
            
            // Speed Control & TOC
            HStack(spacing: 25) {
                Button(action: { isShowingTOC = true }) {
                    Image(systemName: "list.bullet")
                        .font(.title3)
                }
                
                HStack {
                    Image(systemName: "tortoise.fill").font(.caption)
                    Slider(value: $audioController.playbackRate, in: 0.5...4.0, step: 0.1)
                    Image(systemName: "hare.fill").font(.caption)
                    Text(String(format: "%.1fx", audioController.playbackRate))
                        .font(.caption)
                        .frame(width: 40)
                }
            }
            .padding(.horizontal)
            
        }
        .padding(.vertical, 30)
        .foregroundColor(settings.currentTheme.textColor)
        .shadow(color: settings.currentTheme.textColor.opacity(0.1), radius: 10, y: -5)
    }
}

struct ParagraphRow: View {
    @ObservedObject var settings = SettingsManager.shared
    let text: String
    let index: Int
    let currentIndex: Int
    let searchText: String
    let isSearchResult: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Elegant leading vertical bar that fades in when active
            RoundedRectangle(cornerRadius: 2)
                .fill(settings.currentTheme.textColor.opacity(0.6))
                .frame(width: 4)
                .padding(.vertical, 6)
                .padding(.trailing, 12)
                .opacity(index == currentIndex ? 1.0 : 0.0)
            
            Text(highlightObject(for: text, query: searchText))
                .font(settings.currentFont)
                .foregroundColor(settings.currentTheme.textColor)
                .lineSpacing(6)
                .padding(4)
                .background(
                    isSearchResult ? settings.currentTheme.textColor.opacity(0.1) : Color.clear
                )
                .cornerRadius(4)
                .textSelection(.enabled)
        }
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
    let isPlaying: Bool
    let action: () -> Void
    
    static func == (lhs: StablePlayButton, rhs: StablePlayButton) -> Bool {
        return lhs.isPlaying == rhs.isPlaying
    }
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Play Icon
                Image(systemName: "play.circle.fill")
                    .resizable()
                    .frame(width: 60, height: 60)
                    .foregroundColor(.accentColor)
                    .opacity(isPlaying ? 0 : 1)
                
                // Pause Icon
                Image(systemName: "pause.circle.fill")
                    .resizable()
                    .frame(width: 60, height: 60)
                    .foregroundColor(.accentColor)
                    .opacity(isPlaying ? 1 : 0)
            }
            // Use transaction to prevent parent animations from leaking in
            .transaction { transaction in
                transaction.animation = nil
            }
        }
    }
}
