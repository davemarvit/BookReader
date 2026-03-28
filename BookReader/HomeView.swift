import SwiftUI

struct HomeView: View {
    @ObservedObject var libraryManager: LibraryManager
    @EnvironmentObject var audioController: AudioController
    @Binding var selectedTab: Int
    @Binding var navigationPath: [NavigationDestination]
    
    var activeBook: BookMetadata? {
        if AppConfig.shared.isMonetizationBeta {
            // Primary source of truth: actively loaded in audio queue
            if let currentID = audioController.currentBookID,
               let book = libraryManager.books.first(where: { $0.id == currentID }) {
                return book
            }
            // Safe fallback to the last explicitly read/opened book:
            let readBooks = libraryManager.books.filter { book in
                let progressed = book.lastParagraphIndex > (book.initialParagraphIndex ?? 0)
                let openedLater = book.lastReadDate?.timeIntervalSince(book.dateAdded) ?? 0 > 10.0
                return progressed || openedLater
            }
            if readBooks.isEmpty { return nil }
            return readBooks.sorted {
                ($0.lastReadDate ?? Date.distantPast) > ($1.lastReadDate ?? Date.distantPast)
            }.first
        }
        return lastReadBook
    }
    
    var lastReadBook: BookMetadata? {
        if AppConfig.shared.isMonetizationBeta {
            // Filter out starter books that might have dirty lastReadDate == dateAdded from legacy imports.
            let readBooks = libraryManager.books.filter { book in
                let progressed = book.lastParagraphIndex > (book.initialParagraphIndex ?? 0)
                let openedLater = book.lastReadDate?.timeIntervalSince(book.dateAdded) ?? 0 > 10.0
                return progressed || openedLater
            }
            if readBooks.isEmpty { return nil } // True first boot -> show Welcome screen!
            return readBooks.sorted {
                ($0.lastReadDate ?? Date.distantPast) > ($1.lastReadDate ?? Date.distantPast)
            }.first
        }
        
        // Sort by lastReadDate (descending), fallback to dateAdded
        return libraryManager.books.sorted {
            ($0.lastReadDate ?? $0.dateAdded) > ($1.lastReadDate ?? $1.dateAdded)
        }.first
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            if AppConfig.shared.isMonetizationBeta {
                VStack {
                    if let book = activeBook {
                        // "Now Playing" layout
                        Spacer()
                        
                        Button(action: { openReader(book) }) {
                            VStack(spacing: 24) {
                                if let coverURL = libraryManager.getCoverURL(for: book) {
                                    LocalCoverView(coverURL: coverURL)
                                        .id(book.id)
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxHeight: 350)
                                        .shadow(radius: 10)
                                } else {
                                    Image("WakeUpImageMonetization")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxHeight: 350)
                                        .cornerRadius(12)
                                        .shadow(radius: 10)
                                }
                                
                                VStack(spacing: 6) {
                                    Text(book.title)
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                    
                                    if let author = book.author, !author.isEmpty {
                                        Text(author)
                                            .font(.title3)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Spacer()
                        
                        // Progress & Play controls wrapper (does not trigger book open)
                        VStack(spacing: 20) {
                            let total = book.totalParagraphs ?? 1
                            let progressIdx = audioController.currentBookID == book.id ? audioController.currentParagraphIndex : book.lastParagraphIndex
                            let rawProgress = Double(progressIdx) / Double(total > 0 ? total : 1)
                            let currentProgress = min(max(rawProgress, 0.0), 1.0)
                            
                            VStack(spacing: 8) {
                                ProgressView(value: currentProgress)
                                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                                    .padding(.horizontal, 40)
                                
                                HStack {
                                    Text("\(Int(currentProgress * 100))% read")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Button(action: { togglePlayback(for: book) }) {
                                Image(systemName: playbackIconName(for: book))
                                    .resizable()
                                    .frame(width: 80, height: 80)
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.bottom, 20)
                        
                    } else {
                        // Empty State
                        VStack(spacing: 16) {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 64))
                                .foregroundColor(.white.opacity(0.7))
                            
                            Text("No book playing")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text("Choose a book from your library")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                            
                            Button(action: {
                                selectedTab = 1
                            }) {
                                Text("Open Library")
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            .padding(.top, 16)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            ZStack {
                                Image("WakeUpImageMonetization")
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                Color.black.opacity(0.5)
                            }
                            .edgesIgnoringSafeArea(.all)
                        )
                    }
                }
                .navigationDestination(for: NavigationDestination.self) { destination in
                     if case let .reader(doc, book) = destination {
                         ReaderView(document: doc, bookID: book.id, libraryManager: libraryManager, onClose: { navigationPath = [] }, onOpenLibrary: { selectedTab = 1; navigationPath = [] })
                     }
                }
            } else {
                // Legacy Target View
                VStack {
                    Spacer().frame(height: 60)
                    if let book = lastReadBook {
                        Button(action: { openReader(book) }) {
                            VStack(spacing: 8) {
                                Text("Continue Reading")
                                    .font(.subheadline)
                                    .textCase(.uppercase)
                                    .tracking(2)
                                    .foregroundColor(.white.opacity(0.8))
                                
                                Text(book.title)
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(4)
                                    .minimumScaleFactor(0.8)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.black.opacity(0.4))
                                    .cornerRadius(10)
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.bottom, 40)
                        
                        Button(action: { togglePlayback(for: book) }) {
                            Image(systemName: playbackIconName(for: book))
                                .resizable()
                                .frame(width: 80, height: 80)
                                .foregroundColor(.white)
                                .shadow(radius: 10)
                        }
                    } else {
                        Text("Welcome to BookReader")
                            .font(.title)
                            .foregroundColor(.white)
                    }
                    Spacer()
                }
                .navigationDestination(for: NavigationDestination.self) { destination in
                     if case let .reader(doc, book) = destination {
                         ReaderView(document: doc, bookID: book.id, libraryManager: libraryManager, onClose: { navigationPath = [] }, onOpenLibrary: { navigationPath = [] })
                     }
                }
                .padding(.horizontal)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    ZStack {
                        if let book = lastReadBook, let coverURL = libraryManager.getCoverURL(for: book) {
                            LocalCoverView(coverURL: coverURL)
                                .id(book.id)
                                .aspectRatio(contentMode: .fit)
                        } else {
                            Image("WakeUpImage")
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                        Color.black.opacity(0.3)
                    }
                    .edgesIgnoringSafeArea(.all)
                )
            }
        }
        }

    
    func playbackIconName(for book: BookMetadata) -> String {
        if audioController.isPlaying && audioController.currentBookID == book.id {
            return "pause.circle.fill"
        } else {
            return "play.circle.fill"
        }
    }
    
    func togglePlayback(for book: BookMetadata) {
        if AppConfig.shared.isMonetizationBeta {
            if audioController.currentBookID == book.id {
                if audioController.isPlaying {
                    audioController.pause()
                } else {
                    audioController.play()
                }
            } else {
                if let doc = loadDocument(for: book) {
                    var coverImage: UIImage? = nil
                    if let coverURL = libraryManager.getCoverURL(for: book),
                       let data = try? Data(contentsOf: coverURL) {
                        coverImage = UIImage(data: data)
                    }
                    audioController.loadBook(text: doc.text, bookID: book.id, title: book.title, cover: coverImage, initialIndex: book.lastParagraphIndex)
                    if !audioController.isSessionActive {
                        audioController.restorePosition(index: book.lastParagraphIndex)
                    }
                    audioController.play()
                }
            }
        } else {
            if audioController.currentBookID == book.id {
                // Same book: Toggle
                if audioController.isPlaying {
                    audioController.pause()
                } else {
                    openReader(book)
                    audioController.play()
                }
            } else {
                // Different book: Load and Play
                openReader(book)
                audioController.play()
            }
        }
    }
    
    func openReader(_ book: BookMetadata) {
        if audioController.currentBookID != book.id {
            // Load logic is now integrated, or we can prep it first
            if let doc = loadDocument(for: book) {
                // Fetch Cover
                var coverImage: UIImage? = nil
                if let coverURL = libraryManager.getCoverURL(for: book),
                   let data = try? Data(contentsOf: coverURL) {
                    coverImage = UIImage(data: data)
                }
                audioController.loadBook(text: doc.text, bookID: book.id, title: book.title, cover: coverImage, initialIndex: book.lastParagraphIndex)
                if !audioController.isSessionActive {
                    audioController.restorePosition(index: book.lastParagraphIndex)
                }
                self.navigationPath = [.reader(doc, book)]
            }
        } else {
             // Already loaded? Re-parse logic might be needed if we don't persist 'doc'
             // Ideally we shouldn't re-parse if unnecessary.
             if let doc = loadDocument(for: book) {
                 self.navigationPath = [.reader(doc, book)]
             }
        }
    }
    
    func loadDocument(for book: BookMetadata) -> ParsedDocument? {
        let url = libraryManager.getBookURL(for: book)
        return DocumentParser.parse(url: url)
    }
    
    func loadBook(_ book: BookMetadata) {
        let url = libraryManager.getBookURL(for: book)
        if let doc = DocumentParser.parse(url: url) {
            // self.loadedDocument = doc // No longer needed for navigation, but doc is needed for audio
            // self.selectedBook = book // Removed as state is now managed via NavigationDestination
            
            // Fetch Cover
            var coverImage: UIImage? = nil
            if let coverURL = libraryManager.getCoverURL(for: book),
               let data = try? Data(contentsOf: coverURL) {
                coverImage = UIImage(data: data)
            }
            
            audioController.loadBook(text: doc.text, bookID: book.id, title: book.title, cover: coverImage, initialIndex: book.lastParagraphIndex)
            
        }
    }
}

struct LocalCoverView: View {
    let coverURL: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
            } else {
                Image(AppConfig.shared.isMonetizationBeta ? "WakeUpImageMonetization" : "WakeUpImage")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .onAppear {
            loadImage()
        }
        .onChange(of: coverURL) { _ in
            loadImage()
        }
    }

    private func loadImage() {
        // Load synchronously (it's a local file, usually fast enough) or async
        // For stability, simple sync load is often better for local covers on main thread than async flicker
        if let data = try? Data(contentsOf: coverURL),
           let uiImage = UIImage(data: data) {
            self.image = uiImage
        } else {
            // Keep default/nil
            self.image = nil
        }
    }
}

