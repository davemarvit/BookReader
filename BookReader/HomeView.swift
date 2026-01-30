import SwiftUI

struct HomeView: View {
    @ObservedObject var libraryManager: LibraryManager
    @EnvironmentObject var audioController: AudioController
    
    @State private var navigationPath: [NavigationDestination] = []
    
    var lastReadBook: BookMetadata? {
        // Sort by lastReadDate (descending), fallback to dateAdded
        return libraryManager.books.sorted {
            ($0.lastReadDate ?? $0.dateAdded) > ($1.lastReadDate ?? $1.dateAdded)
        }.first
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                // Background Image
                Image("WakeUpImage")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .edgesIgnoringSafeArea(.all)
                
                // Dark Overlay
                Color.black.opacity(0.3)
                    .edgesIgnoringSafeArea(.all)
                
                VStack {
                    // Removed top Spacer() to move content up
                    // Add some top padding to clear status bar/notch naturally or use a fixed Spacer
                    Spacer().frame(height: 60)
                    
                    if let book = lastReadBook {
                        // Book Title & Info (Clickable to Open Reader)
                        Button(action: {
                            openReader(book)
                        }) {
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
                                    .fixedSize(horizontal: false, vertical: true) // Allow unlimited height for text
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.bottom, 40)
                        
                        // Play/Pause Button (Toggles Audio)
                        Button(action: {
                            togglePlayback(for: book)
                        }) {
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
                    
                    Button(action: {
                        navigationPath = [.library]
                    }) {
                        Text("My Library")
                            .font(.headline)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 24)
                            .background(Color.white.opacity(0.2))
                            .foregroundColor(.white)
                            .cornerRadius(20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .padding(.bottom, 50)
                }
            }
            .navigationDestination(for: NavigationDestination.self) { destination in
                 switch destination {
                 case .library:
                     LibraryView(libraryManager: libraryManager, navigationPath: $navigationPath)
                         .navigationBarBackButtonHidden(false)
                 case .reader(let doc, let book):
                     ReaderView(
                         document: doc,
                         bookID: book.id,
                         libraryManager: libraryManager,
                         onClose: {
                             // Pop to Home
                             navigationPath = []
                         },
                         onOpenLibrary: {
                             // Swap to Library (Atomic)
                             navigationPath = [.library]
                         }
                     )
                 }
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
        if audioController.currentBookID == book.id {
            // Same book: Toggle
            if audioController.isPlaying {
                audioController.pause()
            } else {
                audioController.play()
            }
        } else {
            // Different book: Load and Play
            loadBook(book)
            audioController.play()
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
            
            if !audioController.isSessionActive {
                audioController.restorePosition(index: book.lastParagraphIndex)
            }
        }
    }
}
