import SwiftUI

@main
struct BookReaderApp: App {
    @StateObject private var libraryManager = LibraryManager()
    @StateObject private var audioController = AudioController()

    var body: some Scene {
        WindowGroup {
            ContentView(libraryManager: libraryManager)
                .environmentObject(audioController)
                .onAppear {
                    // Wire AudioController to LibraryManager so progress
                    // saves (and the pie chart updates) from the controller
                    // itself, regardless of which view is on screen.
                    audioController.libraryManager = libraryManager
                }
                .onOpenURL { url in
                    _ = libraryManager.importBook(from: url)
                }
        }
    }
}
