import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @ObservedObject var libraryManager: LibraryManager
    @ObservedObject var settings = SettingsManager.shared
    @EnvironmentObject var audioController: AudioController
    @State private var isImporterPresented = false
    
    @Binding var navigationPath: [NavigationDestination]
    
    @AppStorage("hasSeenLibraryWelcome") private var hasSeenLibraryWelcome = false
    
    // Deletion State
    @State private var showingDeleteConfirmation = false
    @State private var bookToDelete: UUID?
    @State private var searchText = ""
    
    
    func getProgress(for book: BookMetadata) -> Double {
        // Use live controller position for the book currently loaded in the player
        if audioController.currentBookID == book.id {
            return audioController.progress
        }
        // Fall back to persisted position for all other books
        guard let total = book.totalParagraphs, total > 0 else { return 0 }
        let progress = Double(book.lastParagraphIndex) / Double(total)
        return min(max(progress, 0), 1.0)
    }
    
    var sortedBooks: [BookMetadata] {
        let filtered = searchText.isEmpty ? libraryManager.books : libraryManager.books.filter { book in
            book.title.localizedCaseInsensitiveContains(searchText) ||
            (book.author?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            (book.tags?.contains { $0.localizedCaseInsensitiveContains(searchText) } ?? false)
        }
        
        switch settings.librarySortOption {
        case "title":
            return filtered.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case "author":
            return filtered.sorted {
                let a1 = $0.author ?? ""
                let a2 = $1.author ?? ""
                if a1.isEmpty && a2.isEmpty { return $0.title < $1.title }
                if a1.isEmpty { return false } // No author goes last
                if a2.isEmpty { return true }
                return a1.localizedCaseInsensitiveCompare(a2) == .orderedAscending
            }
        case "most_read":
            return filtered.sorted { getProgress(for: $0) > getProgress(for: $1) }
        case "least_read":
            return filtered.sorted { getProgress(for: $0) < getProgress(for: $1) }
        default: // "recent"
            return filtered.sorted { ($0.lastReadDate ?? $0.dateAdded) > ($1.lastReadDate ?? $1.dateAdded) }
        }
    }
    
    var body: some View {
        List {
            if AppConfig.shared.isMonetizationBeta && !hasSeenLibraryWelcome {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Welcome — Your library is ready")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Tap any book to start listening, or tap + to add your own books.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                }
            }
            
            ForEach(sortedBooks) { book in
                BookRow(
                    book: book,
                    libraryManager: libraryManager,
                    progress: getProgress(for: book),
                    onTapMain: {
                        print("LibraryView onTapMain: \(book.title) id=\(book.id)")
                        hideWelcomeHint()
                        openBook(book)
                    },
                    onTapProgress: {
                        print("LibraryView onTapProgress: \(book.title) id=\(book.id)")
                        hideWelcomeHint()
                        openMetadata(book)
                    }
                )
            }
            .onDelete { indexSet in
                // Resolve the UUID immediately
                if let first = indexSet.first {
                    bookToDelete = sortedBooks[first].id
                    showingDeleteConfirmation = true
                }
            }
        }
        .simultaneousGesture(DragGesture().onChanged { value in
            if abs(value.translation.height) > 10 {
                hideWelcomeHint()
            }
        })
        .navigationTitle("My Library")
        .searchable(text: $searchText, prompt: "Search title, author, or tags")
        .confirmationDialog("Delete Book?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let id = bookToDelete {
                    libraryManager.deleteBook(id: id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove the book and your reading progress from this device.")
        }
        // Hidden navigation link mechanism REMOVED in favor of shared path
        
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Menu {
                        Picker("Sort By", selection: $settings.librarySortOption) {
                            Text("Most Recent").tag("recent")
                            Text("Title").tag("title")
                            Text("Author").tag("author")
                            Text("Most Read").tag("most_read")
                            Text("Least Read").tag("least_read")
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    
                    Button(action: { 
                        isImporterPresented = true
                        hideWelcomeHint()
                    }) {
                        Image(systemName: "plus")
                    }
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
        .navigationDestination(for: NavigationDestination.self) { destination in
            let _ = print("LibraryView navigationDestination resolver fired")
            if case let .reader(doc, book) = destination {
                ReaderView(
                    document: doc,
                    bookID: book.id,
                    libraryManager: libraryManager,
                    onClose: {
                        self.navigationPath.removeAll()
                    },
                    onOpenLibrary: {
                        self.navigationPath.removeAll()
                    }
                )
            } else if case let .metadata(book) = destination {
                let _ = print("LibraryView navigationDestination resolver: handling .metadata")
                MetadataView(libraryManager: libraryManager, book: book)
            }
        }
        .onAppear {
            if AppConfig.shared.isMonetizationBeta && !hasSeenLibraryWelcome {
                // State automatically handles welcome banner
            }
        }
    }
    
    func hideWelcomeHint() {
        if AppConfig.shared.isMonetizationBeta && !hasSeenLibraryWelcome {
            hasSeenLibraryWelcome = true
        }
    }
    
    func openMetadata(_ book: BookMetadata) {
        print("LibraryView openMetadata: entering for \(book.title)")
        print("LibraryView navigationPath.count before append: \(navigationPath.count)")
        self.navigationPath.append(.metadata(book))
        print("LibraryView navigationPath.count after append: \(navigationPath.count)")
    }
    
    func openBook(_ book: BookMetadata) {
        print("LibraryView openBook: entering for \(book.title)")
        let url = libraryManager.getBookURL(for: book)
        // Ensure we load asynchronously if needed, but for now simple checks
        if let doc = DocumentParser.parse(url: url) {
            print("LibraryView openBook: DocumentParser.parse succeeded")
            print("LibraryView navigationPath.count before append: \(navigationPath.count)")
            self.navigationPath.append(.reader(doc, book))
            print("LibraryView navigationPath.count after append: \(navigationPath.count)")
        } else {
            print("LibraryView openBook: DocumentParser.parse failed")
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

struct BookRow: View {
    let book: BookMetadata
    @ObservedObject var libraryManager: LibraryManager
    let progress: Double
    let onTapMain: () -> Void
    let onTapProgress: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onTapMain) {
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
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: onTapProgress) {
                ProgressRing(progress: CGFloat(progress))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(BorderlessButtonStyle())
        }
    }
    
    var fallbackCover: some View {
        Image(systemName: "text.book.closed.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 50, height: 75)
            .foregroundColor(.gray)
    }
}

struct ProgressRing: View {
    let progress: CGFloat
    
    var body: some View {
        ZStack {
            // Background circle outline
            Circle()
                .stroke(lineWidth: 2.0)
                .opacity(0.3)
                .foregroundColor(.blue)
                .padding(4)
            
            // Filled slice representing progress
            if progress > 0 {
                PieSlice(startAngle: .degrees(-90), endAngle: .degrees(-90 + Double(progress) * 360))
                    .foregroundColor(.blue)
                    .padding(4)
            }
        }
    }
}

struct PieSlice: Shape {
    var startAngle: Angle
    var endAngle: Angle

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(startAngle.radians, endAngle.radians) }
        set {
            startAngle = Angle(radians: newValue.first)
            endAngle = Angle(radians: newValue.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        
        path.move(to: center)
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.closeSubpath()
        
        return path
    }
}
