import SwiftUI

struct HomeView: View {
    @ObservedObject var libraryManager: LibraryManager
    @EnvironmentObject var audioController: AudioController
    
    @State private var navigateToLibrary = false
    @State private var navigateToReader = false
    @State private var selectedBook: BookMetadata?
    @State private var loadedDocument: ParsedDocument?
    
    var lastReadBook: BookMetadata? {
        // Sort by lastReadDate (descending), fallback to dateAdded
        return libraryManager.books.sorted {
            ($0.lastReadDate ?? $0.dateAdded) > ($1.lastReadDate ?? $1.dateAdded)
        }.first
    }
    
    var body: some View {
        NavigationView {
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
                                .padding(.horizontal)
                        }
                        .padding(.bottom, 40)
                        
                        Button(action: {
                            playBook(book)
                        }) {
                            Image(systemName: "play.circle.fill")
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
                        navigateToLibrary = true
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
                
                // Navigation Links
                NavigationLink(isActive: $navigateToLibrary, destination: {
                    LibraryView(libraryManager: libraryManager)
                }) { EmptyView() }
                
                NavigationLink(isActive: $navigateToReader, destination: {
                    if let doc = loadedDocument, let book = selectedBook {
                        ReaderView(document: doc, bookID: book.id, libraryManager: libraryManager)
                    }
                }) { EmptyView() }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    func playBook(_ book: BookMetadata) {
        let url = libraryManager.getBookURL(for: book)
        if let doc = DocumentParser.parse(url: url) {
            self.loadedDocument = doc
            self.selectedBook = book
            
            // Load and Play
            audioController.loadBook(text: doc.text, bookID: book.id)
            
            // Restore position if needed (check if we are already at that point?)
            // If loadBook had to load (was different book), index is 0.
            // If it was same book, index remains.
            // But we want to ensure we are at the saved 'lastParagraphIndex' if we are starting fresh session.
            
            if !audioController.isSessionActive {
                audioController.restorePosition(index: book.lastParagraphIndex)
            }
            // For now, reload to be safe.
            
            audioController.play()
            self.navigateToReader = true
        }
    }
}
