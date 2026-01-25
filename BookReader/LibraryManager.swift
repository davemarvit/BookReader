import Foundation
import Combine
import UIKit // For UIImage (if needed in future, but distinct from SwiftUI)

struct BookMetadata: Codable, Identifiable, Hashable {
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
        let title = tempDoc?.title ?? filename
        
        var coverFilename: String? = nil
        if let coverData = tempDoc?.coverImage {
            let coverName = UUID().uuidString + ".jpg"
            let coverURL = booksDirectory.appendingPathComponent(coverName)
            try? coverData.write(to: coverURL)
            coverFilename = coverName
        }
        
        let newBook = BookMetadata(
            id: UUID(),
            title: title,
            author: tempDoc?.author,
            filename: filename,
            coverFilename: coverFilename,
            lastParagraphIndex: 0,
            totalParagraphs: tempDoc?.paragraphCount ?? 0,
            lastReadDate: Date(),
            dateAdded: Date(),
            fileType: url.pathExtension.lowercased()
        )
        
        books.insert(newBook, at: 0)
        saveLibrary()
        return newBook
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
    
    func updateProgress(for bookID: UUID, index: Int) {
        if let idx = books.firstIndex(where: { $0.id == bookID }) {
            books[idx].lastParagraphIndex = index
            books[idx].lastReadDate = Date()
            saveLibrary()
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
}
