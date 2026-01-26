import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @ObservedObject var libraryManager: LibraryManager
    @ObservedObject var settings = SettingsManager.shared
    @State private var isImporterPresented = false
    
    // Shared Navigation Path
    @Binding var navigationPath: [NavigationDestination]
    
    init(libraryManager: LibraryManager = LibraryManager(), navigationPath: Binding<[NavigationDestination]> = .constant([])) {
        self.libraryManager = libraryManager
        self._navigationPath = navigationPath
    }
    
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
        // NavigationView removed to prevent nesting loops with HomeView
        List {
            ForEach(sortedBooks) { book in
                Button(action: {
                    openBook(book)
                }) {
                        BookRow(book: book, libraryManager: libraryManager)
                    }
                }
                .onDelete(perform: libraryManager.deleteBook)
            }
            .navigationTitle("My Library")
            
            // Hidden navigation link mechanism REMOVED in favor of shared path
            
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
                handleImport(result: result)
            }
        }
    
    func openBook(_ book: BookMetadata) {
        let url = libraryManager.getBookURL(for: book)
        // Ensure we load asynchronously if needed, but for now simple checks
        if let doc = DocumentParser.parse(url: url) {
            // Append to shared path -> Triggers HomeView's navigationDestination
            self.navigationPath.append(.reader(doc, book))
        }
    }
    
    func handleImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                // Task for async work
                Task {
                    await libraryManager.importBook(from: url)
                }
            }
        case .failure(let error):
            print("Import failed: \(error.localizedDescription)")
        }
    }
}

// Extracted Subview to help compiler
struct BookRow: View {
    let book: BookMetadata
    @ObservedObject var libraryManager: LibraryManager
    
    var body: some View {
        HStack {
            // Cover Image
            if let coverURL = libraryManager.getCoverURL(for: book) {
                AsyncImage(url: coverURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().frame(width: 50, height: 75)
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill).frame(width: 50, height: 75).cornerRadius(4).clipped()
                    case .failure:
                        fallbackCover
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                fallbackCover
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
            
            ProgressRing(progress: progress(for: book))
                .frame(width: 30, height: 30)
                .padding(.trailing, 8)
        }
    }
    
    var fallbackCover: some View {
        Image(systemName: "text.book.closed.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 50, height: 75)
            .foregroundColor(.gray)
    }
    
    func progress(for book: BookMetadata) -> CGFloat {
        let total = Double(max(book.totalParagraphs ?? 1, 1))
        let current = Double(book.lastParagraphIndex)
        return CGFloat(min(current / total, 1.0))
    }
}

struct ProgressRing: View {
    let progress: CGFloat
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 4)
                .opacity(0.3)
                .foregroundColor(.blue)
            
            Circle()
                .trim(from: 0.0, to: progress)
                .stroke(style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .foregroundColor(.blue)
                .rotationEffect(Angle(degrees: 270.0))
        }
    }
}
