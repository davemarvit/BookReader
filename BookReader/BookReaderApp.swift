import SwiftUI

@main
struct BookReaderApp: App {
    // We need a shared LibraryManager to handle the import
    @StateObject private var libraryManager = LibraryManager()
    @StateObject private var audioController = AudioController()

    var body: some Scene {
        WindowGroup {
            HomeView(libraryManager: libraryManager)
                .environmentObject(audioController)
                .onOpenURL { url in
                    // Handle incoming file
                    _ = libraryManager.importBook(from: url)
                }
        }
    }
}
