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
                    audioController.libraryManager = libraryManager
                }
                .onOpenURL { url in
                    _ = libraryManager.importBook(from: url)
                }
        }
    }
}
