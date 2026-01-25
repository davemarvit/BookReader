import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @ObservedObject var libraryManager: LibraryManager
    @ObservedObject var settings = SettingsManager.shared
    @State private var isImporterPresented = false
    
    init(libraryManager: LibraryManager = LibraryManager()) {
        self.libraryManager = libraryManager
    }
    @State private var selectedBook: BookMetadata?
    @State private var navigateToReader = false
    @State private var loadedDocument: ParsedDocument?
    
    var sortedBooks: [BookMetadata] {
        switch settings.librarySortOption {
        case "title":
            return libraryManager.books.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case "author":
            return libraryManager.books.sorted {
                let a1 = $0.author ?? ""
                let a2 = $1.author ?? ""
                if a1.isEmpty && a2.isEmpty { return $0.title < $1.title }
                if a1.isEmpty { return false } // No author goes last
                if a2.isEmpty { return true }
                return a1.localizedCaseInsensitiveCompare(a2) == .orderedAscending
            }
        default: // "recent"
            return libraryManager.books.sorted { ($0.lastReadDate ?? $0.dateAdded) > ($1.lastReadDate ?? $1.dateAdded) }
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(sortedBooks) { book in
                    Button(action: {
                        openBook(book)
                    }) {
                        HStack {
                            // Cover Image
                            // Cover Image
                            if let coverURL = libraryManager.getCoverURL(for: book) {
                                AsyncImage(url: coverURL) { phase in
                                    switch phase {
                                    case .empty:
                                        ProgressView()
                                            .frame(width: 50, height: 75)
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 50, height: 75)
                                            .cornerRadius(4)
                                            .clipped()
                                    case .failure:
                                        Image(systemName: "text.book.closed.fill")
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 50, height: 75)
                                            .foregroundColor(.gray)
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                            } else {
                                Image(systemName: "text.book.closed.fill")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 50, height: 75)
                                    .foregroundColor(.gray)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(book.title)
                                    .font(.headline)
                                    .lineLimit(2)
                                    .foregroundColor(.primary)
                                
                                if let author = book.author, !author.isEmpty {
                                    Text(author)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            // Progress Circle
                            ZStack {
                                Circle()
                                    .stroke(lineWidth: 4)
                                    .opacity(0.3)
                                    .foregroundColor(.blue)
                                
                                Circle()
                                    .trim(from: 0.0, to: CGFloat(min(Double(book.lastParagraphIndex) / Double(max(book.totalParagraphs ?? 1, 1)), 1.0)))
                                    .stroke(style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                                    .foregroundColor(.blue)
                                    .rotationEffect(Angle(degrees: 270.0))
                            }
                            .frame(width: 30, height: 30)
                            .padding(.trailing, 8)
                        }
                    }
                }
                .onDelete(perform: libraryManager.deleteBook)
            }
            .navigationTitle("My Library")
            
            // Hidden navigation link
            .background(
                NavigationLink(isActive: $navigateToReader, destination: {
                    if let doc = loadedDocument, let book = selectedBook {
                        ReaderView(document: doc, bookID: book.id, libraryManager: libraryManager)
                    }
                }) { EmptyView() }
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gear")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { isImporterPresented = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [UTType.pdf, UTType.plainText, UTType.epub, UTType(filenameExtension: "epub")!],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    for url in urls {
                        _ = libraryManager.importBook(from: url)
                    }
                case .failure(let error):
                    print("Import failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func openBook(_ book: BookMetadata) {
        let url = libraryManager.getBookURL(for: book)
        if let doc = DocumentParser.parse(url: url) {
            self.loadedDocument = doc
            self.selectedBook = book
            self.navigateToReader = true
        }
    }
}
