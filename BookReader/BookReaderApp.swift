import SwiftUI

@main
struct BookReaderApp: App {
    // We need a shared LibraryManager to handle the import
    @StateObject private var libraryManager = LibraryManager()

    var body: some Scene {
        WindowGroup {
            LibraryView(libraryManager: libraryManager)
                .onOpenURL { url in
                    // Handle incoming file
                    _ = libraryManager.importBook(from: url)
                }
        }
    }
}
