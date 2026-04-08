import Foundation
import Combine
import UIKit // For UIImage (if needed in future, but distinct from SwiftUI)

struct Chapter: Codable, Hashable, Identifiable {
    var id = UUID()
    let title: String
    let paragraphIndex: Int
}

struct BookMetadata: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var author: String?
    var filename: String // Relative to Documents/Books/
    var coverFilename: String? // Relative to Documents/Books/
    var lastParagraphIndex: Int
    var totalParagraphs: Int? // Optional for backward compatibility
    var lastReadDate: Date? // Date of last access
    var dateAdded: Date
    var fileType: String // "pdf", "epub", "txt"
    var notes: String? // User notes
    
    // Chapter Architecture
    var initialParagraphIndex: Int? = 0
    var chapters: [Chapter]? = nil
    
    // Extracted Document Metadata
    var summary: String? = nil
    var tags: [String]? = nil
}

class LibraryManager: ObservableObject {
    @Published var books: [BookMetadata] = []
    
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private var documentsDirectory: URL {
        return fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    private var booksDirectory: URL {
        return documentsDirectory.appendingPathComponent("Books", isDirectory: true)
    }
    
    private var metadataFile: URL {
        return documentsDirectory.appendingPathComponent("library.json")
    }
    
    init() {
        createDirectories()
        loadLibrary()
        loadStarterBooks()
    }
    
    private func createDirectories() {
        if !fileManager.fileExists(atPath: booksDirectory.path) {
            try? fileManager.createDirectory(at: booksDirectory, withIntermediateDirectories: true)
        }
    }
    
    func loadLibrary() {
        guard let data = try? Data(contentsOf: metadataFile),
              let loaded = try? decoder.decode([BookMetadata].self, from: data) else {
            return
        }
        self.books = loaded.sorted(by: { $0.dateAdded > $1.dateAdded })
    }
    
    func saveLibrary() {
        if let data = try? encoder.encode(books) {
            try? data.write(to: metadataFile)
        }
    }
    
    func importBook(from url: URL) -> BookMetadata? {
        // Security Access
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        
        let filename = url.lastPathComponent
        let destURL = booksDirectory.appendingPathComponent(filename)
        
        // Check if we are "importing" a file that is already in our library folder
        // (This happens if the user browses the "Books" folder in the file picker)
        let isSameFile = (url.standardizedFileURL == destURL.standardizedFileURL)
        
        if !isSameFile {
            // Copy File only if it's different
            do {
                if fileManager.fileExists(atPath: destURL.path) {
                    try fileManager.removeItem(at: destURL)
                }
                try fileManager.copyItem(at: url, to: destURL)
            } catch {
                print("Error copying file: \(error)")
                return nil
            }
        }
        
        // Parse for Metadata and Cover
        let tempDoc = DocumentParser.parse(url: destURL)
        var title = tempDoc?.title ?? filename
        if AppConfig.shared.isMonetizationBeta {
            title = title.replacingOccurrences(of: ".txt", with: "")
        }
        
        var coverFilename: String? = nil
        if let coverData = tempDoc?.coverImage {
            let coverName = UUID().uuidString + ".jpg"
            let coverURL = booksDirectory.appendingPathComponent(coverName)
            try? coverData.write(to: coverURL)
            coverFilename = coverName
        }
        
        // Clamp initialParagraphIndex so it never reaches or exceeds paragraphCount.
        // If the front-matter skipper over-classifies, this prevents false 100% progress.
        let paragraphCount = tempDoc?.paragraphCount ?? 0
        let rawInitialIdx = tempDoc?.initialParagraphIndex ?? 0
        let safeInitialIdx = paragraphCount > 0 ? min(rawInitialIdx, max(0, paragraphCount - 1)) : 0
        
        let newBook = BookMetadata(
            id: UUID(),
            title: title,
            author: tempDoc?.author,
            filename: filename,
            coverFilename: coverFilename,
            lastParagraphIndex: safeInitialIdx,
            totalParagraphs: paragraphCount,
            lastReadDate: nil,
            dateAdded: Date(),
            fileType: url.pathExtension.lowercased(),
            initialParagraphIndex: safeInitialIdx,
            chapters: tempDoc?.chapters,
            summary: tempDoc?.summary,
            tags: tempDoc?.tags
        )
        
        books.insert(newBook, at: 0)
        saveLibrary()
        return newBook
    }
    
    func remainingBookCapacity(maxBooks: Int?) -> Int {
        guard let maxLimit = maxBooks else { return Int.max } // nil means unlimited
        return Swift.max(0, maxLimit - books.count)
    }
    
    func getCoverURL(for book: BookMetadata) -> URL? {
        guard let filename = book.coverFilename else { return nil }
        return booksDirectory.appendingPathComponent(filename)
    }
    
    func deleteBook(at offsets: IndexSet) {
        offsets.forEach { index in
            let book = books[index]
            let fileURL = booksDirectory.appendingPathComponent(book.filename)
            try? fileManager.removeItem(at: fileURL)
            if let cover = book.coverFilename {
                let coverURL = booksDirectory.appendingPathComponent(cover)
                try? fileManager.removeItem(at: coverURL)
            }
        }
        books.remove(atOffsets: offsets)
        saveLibrary()
    }
    
    func deleteBook(id: UUID) {
        guard let idx = books.firstIndex(where: { $0.id == id }) else { return }
        let book = books[idx]
        let fileURL = booksDirectory.appendingPathComponent(book.filename)
        try? fileManager.removeItem(at: fileURL)
        if let cover = book.coverFilename {
            let coverURL = booksDirectory.appendingPathComponent(cover)
            try? fileManager.removeItem(at: coverURL)
        }
        books.remove(at: idx)
        saveLibrary()
    }
    
    func updateProgress(for bookID: UUID, index: Int) {
        if let idx = books.firstIndex(where: { $0.id == bookID }) {
            if books[idx].lastParagraphIndex != index {
                books[idx].lastParagraphIndex = index
                books[idx].lastReadDate = Date()
                saveLibrary()
            }
        }
    }
    
    func getBookURL(for book: BookMetadata) -> URL {
        return booksDirectory.appendingPathComponent(book.filename)
    }
    
    func updateCover(for book: BookMetadata, image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        
        let coverName = book.coverFilename ?? (UUID().uuidString + ".jpg")
        let coverURL = booksDirectory.appendingPathComponent(coverName)
        
        do {
            try data.write(to: coverURL)
            
            // Update metadata if filename was new
            if let idx = books.firstIndex(where: { $0.id == book.id }) {
                books[idx].coverFilename = coverName
                saveLibrary()
                
                // Force UI update
                objectWillChange.send()
            }
        } catch {
            print("Error saving cover image: \(error)")
        }
    }

    func deleteCover(for book: BookMetadata) {
        guard let filename = book.coverFilename else { return }
        let coverURL = booksDirectory.appendingPathComponent(filename)
        
        do {
            try fileManager.removeItem(at: coverURL)
            
            if let idx = books.firstIndex(where: { $0.id == book.id }) {
                books[idx].coverFilename = nil
                saveLibrary()
                objectWillChange.send()
            }
        } catch {
            print("Error deleting cover: \(error)")
        }
    }

    func updateTitle(for book: BookMetadata, title: String) {
        if let idx = books.firstIndex(where: { $0.id == book.id }) {
            books[idx].title = title
            saveLibrary()
            objectWillChange.send()
        }
    }
    
    func updateAuthor(for book: BookMetadata, author: String) {
        if let idx = books.firstIndex(where: { $0.id == book.id }) {
            books[idx].author = author
            saveLibrary()
            objectWillChange.send()
        }
    }
    
    func updateNotes(for book: BookMetadata, notes: String) {
        if let idx = books.firstIndex(where: { $0.id == book.id }) {
            books[idx].notes = notes
            saveLibrary()
            objectWillChange.send()
        }
    }
    
    func updateMetadataFields(for book: BookMetadata, summary: String?, tags: [String]?) {
        if let idx = books.firstIndex(where: { $0.id == book.id }) {
            books[idx].summary = summary
            books[idx].tags = tags
            saveLibrary()
            objectWillChange.send()
        }
    }
    
    // MARK: - Starter Library (First Launch Strategy)
    
    private func loadStarterBooks() {
        let hasLoaded = UserDefaults.standard.bool(forKey: "hasLoadedStarterBooks")
        if !hasLoaded {
            Task {
                await importStarterBook(name: "The Great Gatsby", textAsset: "Gatsby_Text", coverAsset: "Gatsby_Cover", author: "F. Scott Fitzgerald")
                await importStarterBook(name: "The Adventures of Sherlock Holmes", textAsset: "Holmes_Text", coverAsset: "Holmes_Cover", author: "Arthur Conan Doyle")
                await importStarterBook(name: "The Time Machine", textAsset: "TimeMachine_Text", coverAsset: "TimeMachine_Cover", author: "H.G. Wells")
                
                await MainActor.run {
                    UserDefaults.standard.set(true, forKey: "hasLoadedStarterBooks")
                }
            }
        }
    }
    
    private func importStarterBook(name: String, textAsset: String, coverAsset: String, author: String) async {
        guard let textDataAsset = NSDataAsset(name: textAsset) else {
            print("Failed to load data asset: \(textAsset)")
            return
        }
        
        let tempURL = fileManager.temporaryDirectory.appendingPathComponent("\(name).txt")
        do {
            try textDataAsset.data.write(to: tempURL)
        } catch {
            print("Failed to write temp file: \(error)")
            return
        }
        
        await MainActor.run {
            if let newBook = self.importBook(from: tempURL) {
                if let coverImage = UIImage(named: coverAsset) {
                    self.updateCover(for: newBook, image: coverImage)
                }
                self.updateAuthor(for: newBook, author: author)
            }
        }
    }
}
