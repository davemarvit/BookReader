// ReaderView.swift

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
    @State private var showingVoiceModeSheet = false
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
                .foregroundColor(settings.currentTheme.textColor)
                .lineLimit(1)
                .padding(.top, 0)
                .padding(.horizontal)
                .padding(.bottom, 24)
            
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
                VStack(spacing: 8) {
                    // Loading block purposefully relocated to top header overlay to prevent text occlusion
                    
                    if audioController.entitlementManager.showUpgradeBanner {
                        UpgradeBannerView()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .padding(.bottom, 4)
                    }
                    
                    if showingControls {
                        ReaderControlsView(
                            isDraggingSlider: $isDraggingSlider,
                            dragProgress: $dragProgress,
                            isShowingTOC: $isShowingTOC
                        )
                        .transition(.move(edge: .bottom))
                        .background(settings.currentTheme.backgroundColor.opacity(0.96).ignoresSafeArea())
                        .overlay(
                            Rectangle()
                                .frame(width: nil, height: 1, alignment: .top)
                                .foregroundColor(settings.currentTheme.textColor.opacity(0.15)),
                            alignment: .top
                        )
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: audioController.isLoading)
            }
        } // End Main VStack
        .overlay(alignment: .top) {
            // Enhanced Overlay Top Status Indicator - Theme Adaptive High Contrast
            if audioController.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: settings.currentTheme.backgroundColor))
                        .scaleEffect(0.7)
                    Text("Preparing enhanced audio...")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(settings.currentTheme.backgroundColor)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(
                    Capsule()
                        .fill(settings.currentTheme.textColor.opacity(0.85))
                        .shadow(color: Color.black.opacity(0.2), radius: 4, y: 2)
                )
                .padding(.top, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(settings.currentTheme.backgroundColor.edgesIgnoringSafeArea(.all))
        .preferredColorScheme((settings.readerTheme == "dark" || settings.readerTheme == "lowContrastDark") ? .dark : (settings.readerTheme == "system" ? nil : .light))
        .onChange(of: searchText) { _, newValue in
            performSearch(query: newValue)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
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
                        Image(systemName: audioController.sleepTimerActive ? "moon.fill" : "moon")
                        if audioController.sleepTimerActive {
                            Text(audioController.sleepTimerString)
                                .font(.caption.monospacedDigit())
                        }
                    }
                    .foregroundColor(audioController.sleepTimerActive ? .accentColor : settings.currentTheme.textColor)
                }
            }
            
            ToolbarItem(placement: .principal) {
                Button(action: {
                    print("--- BANNER TAPPED ---")
                    print("Preferred Engine: \(settings.preferredEngine)")
                    print("Entitlement State: \(audioController.entitlementManager.premiumEntitlement)")
                    print("Active Voice Mode: \(audioController.voiceModeController.activeMode)")
                    // showingVoiceModeSheet = true
                }) {
                    Text(voiceModeLabel)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .truncationMode(.tail)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(settings.currentTheme.textColor.opacity(0.1))
                        .cornerRadius(12)
                        .layoutPriority(1)
                }
                .foregroundColor(settings.currentTheme.textColor)
            }
            
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

        .onChange(of: audioController.activeGate) { _, newGate in
            if newGate != nil {
                print("DIAGNOSTIC: ReaderView directly observed activeGate changing to NON-NIL!")
            }
        }
        .sheet(item: $audioController.activeGate) { gate in
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.orange)
                    .padding(.bottom, 8)
                Text("Enhanced Audio Limit Reached")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("You’ve reached the limit of your Enhanced audio. You can upgrade or continue with Basic audio.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                VStack(spacing: 12) {
                    Button("Continue with Basic Audio") {
                        audioController.gateController.resolvePendingGate(with: .standard)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Upgrade (Coming Soon)") {
                        audioController.gateController.resolvePendingGate(with: .cancel)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(32)
            .interactiveDismissDisabled()
        }
    } // End Body
    
    var voiceModeLabel: String {
        return audioController.playbackState.bannerText
    }
    
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
                    // Warning: We are keeping the Array(.enumerated()) conversion here 
                    // to test if it's the specific cause of the freeze.
                    ForEach(Array(audioController.paragraphs.enumerated()), id: \.offset) { index, paragraph in
                        ParagraphRow(
                            text: paragraph,
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
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .onChange(of: audioController.currentParagraphIndex) { _, newIndex in
                guard audioController.currentBookID == bookID else { return }
                libraryManager.updateProgress(for: bookID, index: newIndex)
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
            .task {
                print("BOOK PREP START")
                let coverImage: UIImage? = {
                    if let book = libraryManager.books.first(where: { $0.id == bookID }),
                       let coverURL = libraryManager.getCoverURL(for: book),
                       let data = try? Data(contentsOf: coverURL) {
                        return UIImage(data: data)
                    }
                    return nil
                }()
                
                let book = libraryManager.books.first(where: { $0.id == bookID })
                let prepared = audioController.prepareBookContent(
                    text: document.text,
                    bookID: bookID,
                    title: book?.title ?? document.title,
                    cover: coverImage,
                    initialIndex: book?.lastParagraphIndex ?? 0
                )
                
                await MainActor.run {
                    audioController.applyBookContent(prepared)
                    if let index = book?.lastParagraphIndex, !audioController.isSessionActive {
                        audioController.restorePosition(index: index)
                    }
                }
            }
        }
    }
}

struct UpgradeBannerView: View {
    @EnvironmentObject var audioController: AudioController
    @ObservedObject var settings = SettingsManager.shared
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .foregroundColor(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Enhanced Audio Ended")
                    .font(.subheadline.bold())
                Text("Playing Basic audio. Upgrade to resume.")
                    .font(.caption)
                    .foregroundColor(settings.currentTheme.textColor.opacity(0.8))
                    .lineLimit(1)
            }
            Spacer()
            
            Button("Upgrade") {
                // Future monetization hook / Launch paywall
                audioController.entitlementManager.showUpgradeBanner = false
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            
            Button {
                withAnimation { audioController.entitlementManager.showUpgradeBanner = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.callout)
                    .foregroundColor(settings.currentTheme.textColor.opacity(0.6))
                    .padding(.leading, 4)
            }
        }
        .padding(12)
        .background(settings.currentTheme.backgroundColor)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.15), radius: 8, y: 4)
        .padding(.horizontal)
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
        let isActive = (index == currentIndex)
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(isActive ? settings.currentTheme.textColor.opacity(0.6) : Color.clear)
                .frame(width: 4)
                .cornerRadius(2)
            
            Text(text)
                .padding(4)
        }
    }
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
struct AnimatedEllipsisView: View {
    @State private var dotCount = 0
    let timer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(String(repeating: ".", count: dotCount))
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(width: 15, alignment: .leading)
            .onReceive(timer) { _ in
                dotCount = (dotCount + 1) % 4
            }
    }
}
