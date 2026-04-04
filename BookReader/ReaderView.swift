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
    @State private var searchWorkItem: DispatchWorkItem?
    @FocusState private var isSearchFieldFocused: Bool
    
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
                        .onSubmit {
                            if !searchResults.isEmpty {
                                navigateToSearchMatch(at: 0)
                            }
                        }
                    
                    if !searchText.isEmpty && searchResults.isEmpty {
                        Text("Not found")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if !searchResults.isEmpty {
                        HStack(spacing: 8) {
                            Text("\(currentSearchMatchIndex + 1) of \(searchResults.count)")
                            
                            Button(action: { previousMatch() }) {
                                Image(systemName: "chevron.up")
                            }
                            
                            Button(action: { nextMatch() }) {
                                Image(systemName: "chevron.down")
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    
                    Button("Cancel") {
                        withAnimation {
                            isSearching = false
                            searchText = ""
                            searchWorkItem?.cancel()
                            searchWorkItem = nil
                            searchResults = []
                            currentSearchMatchIndex = 0
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
                searchText: searchText
            )
            .id(bookID)
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
        .background(settings.currentTheme.backgroundColor.edgesIgnoringSafeArea(.all))
        .preferredColorScheme((settings.readerTheme == "dark" || settings.readerTheme == "lowContrastDark") ? .dark : (settings.readerTheme == "system" ? nil : .light))
        .onChange(of: searchText) { newValue in
            searchWorkItem?.cancel()
            
            let workItem = DispatchWorkItem {
                performSearch(query: newValue)
            }
            
            searchWorkItem = workItem
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
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
                    showingVoiceModeSheet = true
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

        .onChange(of: audioController.activeGate) { newGate in
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
        .sheet(isPresented: $showingVoiceModeSheet) {
            VoiceModeSheetView(isPresented: $showingVoiceModeSheet, state: bannerState)
                .environmentObject(audioController)
        }
    } // End Body
    
    // MARK: - Banner Derived State
    enum ReaderBannerState {
        case basicNotSubscribed
        case basicEnhancedAvailable
        case basicTemporarilyUnavailable
        case basicEnhancedExhausted
        case enhanced
    }
    
    var bannerState: ReaderBannerState {
        let entitlement = audioController.entitlementManager.premiumEntitlement
        let resolved = audioController.resolvedPlaybackMode
        let availability = audioController.playbackState.availability
        let requested = audioController.voiceModeController.requestedMode

        // Enhanced active
        if resolved == .premium {
            return .enhanced
        }

        // Temporarily unavailable
        if availability == .temporarilyUnavailable {
            return .basicTemporarilyUnavailable
        }

        // Quota exhausted
        if availability == .limitReached {
            return .basicEnhancedExhausted
        }

        let hasPremiumAccess = entitlement != .standardOnly

        // User has entitlement (Enhanced available) but is currently in Basic
        if hasPremiumAccess {
            return .basicEnhancedAvailable
        }

        // Default: not subscribed
        return .basicNotSubscribed
    }
    
    var voiceModeLabel: String {
        switch bannerState {
        case .basicNotSubscribed: return "Basic Audio"
        case .basicEnhancedAvailable: return "Basic · Enhanced Available"
        case .basicTemporarilyUnavailable: return "Basic · Enhanced Temporarily Unavailable"
        case .basicEnhancedExhausted: return "Basic · Enhanced Audio Exhausted"
        case .enhanced: return "Enhanced Audio"
        }
    }
    
    func getParagraph(at index: Int) -> String {
        return audioController.paragraphs[index]
    }
    
    func performSearch(query: String) {
        if query.isEmpty {
            searchResults = []
            currentSearchMatchIndex = 0
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
    }
    
    private func navigateToSearchMatch(at arrayIndex: Int) {
        guard arrayIndex >= 0 && arrayIndex < searchResults.count else { return }
        currentSearchMatchIndex = arrayIndex
        let paragraphIndex = searchResults[arrayIndex]
        audioController.setManualPlaybackPosition(index: paragraphIndex)
    }
    
    func nextMatch() {
        guard !searchResults.isEmpty else { return }
        let newArrayIndex = (currentSearchMatchIndex + 1) % searchResults.count
        navigateToSearchMatch(at: newArrayIndex)
    }
    
    func previousMatch() {
        guard !searchResults.isEmpty else { return }
        let newArrayIndex = (currentSearchMatchIndex - 1 + searchResults.count) % searchResults.count
        navigateToSearchMatch(at: newArrayIndex)
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
    
    @State private var viewportHeight: CGFloat = 0
    @State private var paragraphHeights: [Int: CGFloat] = [:]
    @State private var currentSegmentIndex: Int? = nil
    @State private var lastCenteredSegmentKey: String? = nil
    @State private var accumulatedActiveTime: TimeInterval = 0
    @State private var lastTickDate: Date? = nil
    @State private var paragraphStartIndex: Int? = nil
    @State private var activeBand: ClosedRange<CGFloat>? = nil
    @State private var activeSegmentCount: Int = 1
    @State private var pendingInitialIndex: Int? = nil
    
    private let debugReadAlongSegments = true
    private let debugReadAlongTrace = true
    
    private var traceStateString: String {
        let bID = bookID.uuidString.prefix(4)
        let cbID = audioController.currentBookID?.uuidString.prefix(4) ?? "nil"
        let cpIdx = audioController.currentParagraphIndex
        let pIdx = libraryManager.books.first(where: { $0.id == bookID })?.lastParagraphIndex ?? -1
        let align = didInitialViewportAlign
        let pend = pendingInitialIndex ?? -1
        return "b=\(bID) cb=\(cbID) cp=\(cpIdx) last=\(pIdx) align=\(align) pend=\(pend)"
    }
    
    @State private var didInitialViewportAlign = false
    @State private var didInitialParagraphScroll = false
    
    let readAlongTimer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()
    
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
                            isSearchResult: searchResults.contains(index),
                            activeBand: (index == audioController.currentParagraphIndex) ? activeBand : nil,
                            segmentCount: (index == audioController.currentParagraphIndex) ? activeSegmentCount : 1
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
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: ViewportHeightPreferenceKey.self, value: geo.size.height)
                }
            )
            .onPreferenceChange(ViewportHeightPreferenceKey.self) { height in
                viewportHeight = height
                checkInitialReadiness(proxy: proxy)
            }
            .onPreferenceChange(ParagraphHeightPreferenceKey.self) { heights in
                paragraphHeights.merge(heights) { _, new in new }
                checkInitialReadiness(proxy: proxy)
            }
            .onReceive(readAlongTimer) { _ in
                updateReadAlongState(proxy: proxy)
            }
            .onAppear {
                if debugReadAlongTrace { print("[ReadAlongTrace] appear \(traceStateString)") }
                resetReadAlongEntryState()
                checkInitialReadiness(proxy: proxy)
            }
            .onDisappear {
                if debugReadAlongTrace { print("[ReadAlongTrace] disappear \(traceStateString)") }
                resetReadAlongEntryState(isExit: true)
            }
            .onChange(of: audioController.currentParagraphIndex) { newIndex in
                if debugReadAlongTrace { print("[ReadAlongTrace] paragraph-change new=\(newIndex) \(traceStateString)") }
                guard audioController.currentBookID == bookID else { return }
                libraryManager.updateProgress(for: bookID, index: newIndex)
                
                paragraphStartIndex = newIndex
                accumulatedActiveTime = 0
                lastTickDate = nil
                currentSegmentIndex = nil
                lastCenteredSegmentKey = nil
                activeBand = nil
                
                let pHeight = paragraphHeights[newIndex] ?? 0
                let segCount = computeSegmentCount(paragraphHeight: pHeight, viewportHeight: viewportHeight)
                activeSegmentCount = segCount
                
                if debugReadAlongSegments && segCount > 1 {
                    print("[ReadAlong] oversized p=\(newIndex) h=\(pHeight) vh=\(viewportHeight) segs=\(segCount)")
                }
                
                if segCount <= 1 {
                    let duration = animationDuration(forDistance: viewportHeight * 0.8)
                    withAnimation(.easeInOut(duration: duration)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                } else {
                    currentSegmentIndex = 0
                    
                    let paddingFraction = min(0.08, 0.5 / CGFloat(segCount))
                    activeBand = computeActiveBand(segIndex: 0, segCount: segCount, paddingFraction: paddingFraction)
                    
                    let segKey = "\(newIndex)-0"
                    lastCenteredSegmentKey = segKey
                    
                    let jumpDistance = pHeight / CGFloat(max(1, segCount))
                    let duration = animationDuration(forDistance: jumpDistance)
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: duration)) {
                            proxy.scrollTo(segKey, anchor: .center)
                        }
                    }
                }
            }
            .task {
                print("BOOK PREP START")
                let book = libraryManager.books.first(where: { $0.id == bookID })
                
                if audioController.currentBookID == bookID && !audioController.paragraphs.isEmpty {
                    print("SKIPPING PREP - ALREADY LOADED")
                } else {
                    let coverImage: UIImage? = {
                        if let book = book,
                           let coverURL = libraryManager.getCoverURL(for: book),
                           let data = try? Data(contentsOf: coverURL) {
                            return UIImage(data: data)
                        }
                        return nil
                    }()
                    
                    let prepared = audioController.prepareBookContent(
                        text: document.text,
                        bookID: bookID,
                        title: book?.title ?? document.title,
                        cover: coverImage,
                        initialIndex: book?.lastParagraphIndex ?? 0
                    )
                    
                    await MainActor.run {
                        if debugReadAlongTrace { print("[ReadAlongTrace] task-before-apply \(traceStateString)") }
                        audioController.applyBookContent(prepared)
                        if debugReadAlongTrace { print("[ReadAlongTrace] task-after-apply \(traceStateString)") }
                    }
                }
                
                await MainActor.run {
                    if let index = book?.lastParagraphIndex, !audioController.isSessionActive {
                        if debugReadAlongTrace { print("[ReadAlongTrace] task-before-restore \(traceStateString)") }
                        audioController.restorePosition(index: index)
                        if debugReadAlongTrace { print("[ReadAlongTrace] task-after-restore \(traceStateString)") }
                    }
                }
            }
        }
    }
    
    private func resetReadAlongEntryState(isExit: Bool = false) {
        if debugReadAlongSegments {
            print(isExit ? "[ReadAlong] exit-reset" : "[ReadAlong] entry-reset")
        }
        if debugReadAlongTrace {
            print(isExit ? "[ReadAlongTrace] reset exit \(traceStateString)" : "[ReadAlongTrace] reset entry \(traceStateString)")
        }
        didInitialViewportAlign = false
        didInitialParagraphScroll = false
        pendingInitialIndex = nil
        lastCenteredSegmentKey = nil
        currentSegmentIndex = nil
        activeBand = nil
        paragraphStartIndex = nil
        accumulatedActiveTime = 0
        lastTickDate = nil
    }
    
    private func checkInitialReadiness(proxy: ScrollViewProxy) {
        if debugReadAlongTrace { print("[ReadAlongTrace] check-start \(traceStateString)") }
        
        guard !didInitialViewportAlign else { return }
        guard audioController.currentBookID == bookID else { return }
        guard !audioController.paragraphs.isEmpty else { return }
        
        let book = libraryManager.books.first(where: { $0.id == bookID })
        let persistedIndex = book?.lastParagraphIndex
        let currentIndex = audioController.currentParagraphIndex
        
        var targetIndex = persistedIndex ?? currentIndex
        let maxIndex = audioController.paragraphs.count - 1
        if maxIndex >= 0 {
            targetIndex = max(0, min(maxIndex, targetIndex))
        }
        
        if !didInitialParagraphScroll {
            if debugReadAlongSegments { print("[ReadAlong] init-prealign p=\(targetIndex)") }
            didInitialParagraphScroll = true
            let duration = animationDuration(forDistance: viewportHeight * 0.8)
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: duration)) {
                    proxy.scrollTo(targetIndex, anchor: .center)
                }
            }
            return
        }
        
        guard viewportHeight > 0 else {
            if debugReadAlongSegments { print("[ReadAlong] init-wait p=\(targetIndex) (no viewport)") }
            if debugReadAlongTrace { print("[ReadAlongTrace] check-return reason=no-viewport \(traceStateString)") }
            return
        }
        
        let pHeight = paragraphHeights[targetIndex] ?? 0
        guard pHeight > 0 else {
            if debugReadAlongSegments { print("[ReadAlong] init-wait p=\(targetIndex) (no height)") }
            if debugReadAlongTrace { print("[ReadAlongTrace] check-return reason=no-height \(traceStateString)") }
            return
        }
        
        if pendingInitialIndex != targetIndex {
            if debugReadAlongSegments { print("[ReadAlong] init-candidate p=\(targetIndex)") }
            if debugReadAlongTrace { print("[ReadAlongTrace] check-return reason=await-stable-index \(traceStateString)") }
            pendingInitialIndex = targetIndex
            return
        }
        
        if debugReadAlongSegments { print("[ReadAlong] init-stable p=\(targetIndex)") }
        
        didInitialViewportAlign = true
        libraryManager.updateProgress(for: bookID, index: targetIndex)
        
        let segCount = computeSegmentCount(paragraphHeight: pHeight, viewportHeight: viewportHeight)
        activeSegmentCount = segCount
        
        if debugReadAlongSegments {
            print("[ReadAlong] init-stage2-ready p=\(targetIndex) segs=\(segCount)")
        }
        
        if segCount <= 1 {
            if debugReadAlongTrace { print("[ReadAlongTrace] init-align mode=paragraph target=\(targetIndex) \(traceStateString)") }
            let duration = animationDuration(forDistance: viewportHeight * 0.8)
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: duration)) {
                    proxy.scrollTo(targetIndex, anchor: .center)
                }
            }
        } else {
            paragraphStartIndex = targetIndex
            accumulatedActiveTime = 0
            lastTickDate = nil
            currentSegmentIndex = 0
            
            let paddingFraction = min(0.08, 0.5 / CGFloat(segCount))
            activeBand = computeActiveBand(segIndex: 0, segCount: segCount, paddingFraction: paddingFraction)
            
            let segKey = "\(targetIndex)-0"
            lastCenteredSegmentKey = segKey
            
            if debugReadAlongSegments {
                print("[ReadAlong] init-stage2-scroll p=\(targetIndex) s=0")
            }
            if debugReadAlongTrace { print("[ReadAlongTrace] init-align mode=segment0 target=\(segKey) \(traceStateString)") }
            if debugReadAlongTrace { print("[ReadAlongTrace] init-scroll-target key=\(segKey) \(traceStateString)") }
            
            let jumpDistance = pHeight / CGFloat(max(1, segCount))
            let duration = animationDuration(forDistance: jumpDistance)
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: duration)) {
                    proxy.scrollTo(segKey, anchor: .top)
                }
            }
        }
    }
    
    private func computeActiveBand(segIndex: Int, segCount: Int, paddingFraction: CGFloat) -> ClosedRange<CGFloat> {
        let exactStart = CGFloat(segIndex) / CGFloat(segCount)
        let exactEnd = CGFloat(segIndex + 1) / CGFloat(segCount)
        
        if segCount <= 1 { return 0.0...1.0 }
        
        let topPaddingBase: CGFloat
        let bottomPaddingBase: CGFloat
        
        if segIndex == 0 {
            topPaddingBase = 0.0
            bottomPaddingBase = paddingFraction * 1.15
        } else if segIndex == segCount - 1 {
            topPaddingBase = -min(paddingFraction * 0.2, 0.015)
            bottomPaddingBase = 0.0
        } else {
            topPaddingBase = -min(paddingFraction * 0.2, 0.015)
            bottomPaddingBase = paddingFraction * 0.9
        }
        
        let segmentProgress = segCount > 1 ? CGFloat(segIndex) / CGFloat(segCount - 1) : 0
        let topDriftMultiplier = 1.0 + 0.10 * segmentProgress
        let bottomDriftMultiplier = 1.0 + 0.30 * segmentProgress
        
        var topPadding = topPaddingBase * topDriftMultiplier
        var bottomPadding = bottomPaddingBase * bottomDriftMultiplier
        
        let topPaddingCapFraction: CGFloat = 0.035
        let bottomPaddingCapFraction: CGFloat = 0.07
        
        topPadding = min(topPadding, topPaddingCapFraction)
        bottomPadding = min(bottomPadding, bottomPaddingCapFraction)
        
        let start = min(exactEnd, max(0, exactStart - topPadding))
        let end = min(1, exactEnd + bottomPadding)
        
        return start...end
    }

    private func animationDuration(forDistance distance: CGFloat) -> Double {
        let vh = max(1, viewportHeight)
        let normalized = min(1.0, abs(distance) / vh)
        return 0.18 + 0.22 * Double(normalized)
    }
    
    private func computeSegmentCount(paragraphHeight: CGFloat, viewportHeight: CGFloat) -> Int {
        guard viewportHeight > 0 else { return 1 }
        let threshold = 0.60 * viewportHeight
        if paragraphHeight < threshold { return 1 }
        let rawCount = ceil(paragraphHeight / threshold)
        return max(2, Int(rawCount))
    }
    
    private func updateReadAlongState(proxy: ScrollViewProxy) {
        let isPlaying = audioController.isSessionActive && audioController.isPlaying
        
        guard isPlaying else {
            lastTickDate = nil // reset tick date on pause to prevent accumulating background time natively
            return
        }
        
        let pIndex = audioController.currentParagraphIndex
        if paragraphStartIndex != pIndex {
            // Wait for onChange to run
            return
        }
        
        let now = Date()
        if let lastTick = lastTickDate {
            accumulatedActiveTime += now.timeIntervalSince(lastTick)
        }
        lastTickDate = now
        
        let pHeight = paragraphHeights[pIndex] ?? 0
        let segCount = computeSegmentCount(paragraphHeight: pHeight, viewportHeight: viewportHeight)
        
        if activeSegmentCount != segCount {
            activeSegmentCount = segCount
        }
        
        if segCount <= 1 {
            if activeBand != nil { activeBand = nil }
            return
        }
        
        let words = max(1, audioController.paragraphs.indices.contains(pIndex) ? audioController.paragraphs[pIndex].components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count : 1)
        let effectiveWPM = 160.0 * Double(audioController.playbackRate)
        let estimatedDuration = (Double(words) / effectiveWPM) * 60.0
        guard estimatedDuration > 0 else { return }
        
        let progress = CGFloat(max(0, min(1.0, accumulatedActiveTime / estimatedDuration)))
        
        let text = audioController.paragraphs.indices.contains(pIndex) ? audioController.paragraphs[pIndex] : ""
        let charCount = max(1, text.count)
        let charsPerChunk = Int(ceil(Double(charCount) / Double(segCount)))
        
        var weights: [Double] = []
        var currentIndex = text.startIndex
        for _ in 0..<segCount {
            if currentIndex >= text.endIndex {
                weights.append(1.0)
                continue
            }
            let nextIndex = text.index(currentIndex, offsetBy: charsPerChunk, limitedBy: text.endIndex) ?? text.endIndex
            let chunkText = text[currentIndex..<nextIndex]
            
            var weight = Double(chunkText.count)
            for char in chunkText {
                switch char {
                case ",": weight += 2
                case ":", ";": weight += 3
                case ".", "?", "!": weight += 5
                case "-", "(", ")": weight += 2
                case "_": weight += 6
                default: break
                }
            }
            weights.append(max(1.0, weight))
            currentIndex = nextIndex
        }
        
        let totalWeight = weights.reduce(0, +)
        var cumulative: [CGFloat] = [0.0]
        var sum = 0.0
        for w in weights {
            sum += w
            cumulative.append(CGFloat(sum / totalWeight))
        }
        cumulative[segCount] = 1.0
        
        var segIndex = segCount - 1
        for i in 0..<segCount {
            let start = cumulative[i]
            let end = cumulative[i+1]
            if progress >= start && progress < end {
                segIndex = i
                break
            }
        }
        if progress >= 1.0 { segIndex = segCount - 1 }
        
        if debugReadAlongSegments && currentSegmentIndex != segIndex && currentSegmentIndex == 0 {
            let wStrings = weights.map { String(format: "%.0f", $0) }.joined(separator: ",")
            print("[ReadAlong] weights p=\(pIndex) segs=\(segCount) values=[\(wStrings)]")
        }
        
        let paddingFraction = min(0.08, 0.5 / CGFloat(segCount))
        activeBand = computeActiveBand(segIndex: segIndex, segCount: segCount, paddingFraction: paddingFraction)
        
        if currentSegmentIndex != segIndex {
            if debugReadAlongSegments {
                let old = currentSegmentIndex ?? -1
                print("[ReadAlong] segment p=\(pIndex) \(old)->\(segIndex) progress=\(progress)")
            }
            currentSegmentIndex = segIndex
            
            let segKey = "\(pIndex)-\(segIndex)"
            if lastCenteredSegmentKey != segKey {
                if debugReadAlongSegments {
                    print("[ReadAlong] recenter p=\(pIndex) s=\(segIndex)")
                }
                lastCenteredSegmentKey = segKey
                let jumpDistance = pHeight / CGFloat(max(1, segCount))
                let duration = animationDuration(forDistance: jumpDistance)
                withAnimation(.easeInOut(duration: duration)) {
                    proxy.scrollTo(segKey, anchor: .center)
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
                StablePlayButton(isPlaying: audioController.isPlaying, isLoading: audioController.isLoading) {
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
    var activeBand: ClosedRange<CGFloat>? = nil
    var segmentCount: Int = 1

    var body: some View {
        let isActive = (index == currentIndex)
        HStack(alignment: .top, spacing: 8) {
            Color.clear
                .frame(width: 4)
                .overlay(
                    GeometryReader { geo in
                        let fullHeight = geo.size.height
                        ZStack(alignment: .top) {
                            if isActive {
                                if let band = activeBand {
                                    Rectangle()
                                        .fill(settings.currentTheme.textColor.opacity(0.6))
                                        .frame(width: 4, height: max(0, (band.upperBound - band.lowerBound) * fullHeight))
                                        .cornerRadius(2)
                                        .offset(y: band.lowerBound * fullHeight)
                                } else {
                                    Rectangle()
                                        .fill(settings.currentTheme.textColor.opacity(0.6))
                                        .frame(width: 4, height: fullHeight)
                                        .cornerRadius(2)
                                }
                            }
                            
                            VStack(spacing: 0) {
                                ForEach(0..<segmentCount, id: \.self) { sIndex in
                                    Color.clear
                                        .id("\(index)-\(sIndex)")
                                        .frame(height: fullHeight / CGFloat(max(1, segmentCount)))
                                }
                            }
                        }
                    }
                )
            
            Text(text)
                .padding(4)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: ParagraphHeightPreferenceKey.self, value: [index: geo.size.height])
                    }
                )
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

struct ViewportHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ParagraphHeightPreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// ZStack-based Button to prevent SF Symbol swapping flicker
// MARK: - Equatable to prevent redundancy
struct StablePlayButton: View, Equatable {
    let isPlaying: Bool
    let isLoading: Bool
    let action: () -> Void
    
    static func == (lhs: StablePlayButton, rhs: StablePlayButton) -> Bool {
        return lhs.isPlaying == rhs.isPlaying && lhs.isLoading == rhs.isLoading
    }
    
    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
                        .scaleEffect(1.5)
                        .frame(width: 60, height: 60)
                } else {
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

// MARK: - Voice Mode Sheet Content
struct VoiceModeSheetView: View {
    @EnvironmentObject var audioController: AudioController
    @Binding var isPresented: Bool
    let state: ReaderView.ReaderBannerState
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header icon
                Image(systemName: "waveform")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
                    .padding(.top, 20)
                
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text(message)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                Spacer()
                
                VStack(spacing: 12) {
                    buttons
                }
                .padding(.bottom, 30)
                .padding(.horizontal)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { isPresented = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    var title: String {
        switch state {
        case .basicNotSubscribed: return "Basic Audio"
        case .basicEnhancedAvailable: return "Enhanced Audio Available"
        case .basicTemporarilyUnavailable: return "Enhanced Temporarily Unavailable"
        case .basicEnhancedExhausted: return "Enhanced Audio Exhausted"
        case .enhanced: return "Enhanced Audio"
        }
    }
    
    var message: String {
        switch state {
        case .basicNotSubscribed:
            return "You are listening in Basic Audio. Enhanced Audio requires a subscription."
        case .basicEnhancedAvailable:
            return "Enhanced Audio is included for your account. You are currently using Basic Audio. You can stay in Basic to conserve Enhanced time or switch back now."
        case .basicTemporarilyUnavailable:
            return "Enhanced Audio is included for your account. It is temporarily unavailable right now. Playback has fallen back to Basic so reading can continue."
        case .basicEnhancedExhausted:
            // TODO: If the codebase already has access to the monthly reset / subscription anniversary date, show it.
            return "Your current Enhanced Audio time has been used up for this billing period. You can continue in Basic Audio for now.\n\nNew Enhanced Audio time will be added on your monthly renewal date."
        case .enhanced:
            return "You are currently listening in Enhanced Audio."
        }
    }
    
    @ViewBuilder
    var buttons: some View {
        switch state {
        case .basicNotSubscribed:
            Button("Keep Using Basic Audio") { isPresented = false }
                .buttonStyle(.bordered)
            Button("Upgrade") { 
                // TODO: Wire to billing flow
                isPresented = false 
            }
            .buttonStyle(.borderedProminent)
            
        case .basicEnhancedAvailable:
            Button("Switch to Enhanced Audio") {
                audioController.handleManualVoiceSwitch(to: .premium)
                isPresented = false
            }
            .buttonStyle(.borderedProminent)
            Button("Keep Using Basic Audio") { isPresented = false }
                .buttonStyle(.bordered)
            
        case .basicTemporarilyUnavailable:
            Button("Try Enhanced Again") {
                audioController.handleManualVoiceSwitch(to: .premium)
                isPresented = false
            }
            .buttonStyle(.borderedProminent)
            Button("Keep Using Basic Audio") { isPresented = false }
                .buttonStyle(.bordered)
            
        case .basicEnhancedExhausted:
            Button("Keep Using Basic Audio") { isPresented = false }
                .buttonStyle(.bordered)
            // TODO: If account type is Reader and upgrade info is available, offer Upgrade
            Button("Upgrade (Coming Soon)") {
                isPresented = false
            }
            .buttonStyle(.borderedProminent)
            
        case .enhanced:
            Button("Keep Using Enhanced Audio") { isPresented = false }
                .buttonStyle(.borderedProminent)
            Button("Switch to Basic Audio") {
                audioController.handleManualVoiceSwitch(to: .standard)
                isPresented = false
            }
            .buttonStyle(.bordered)
        }
    }
}
