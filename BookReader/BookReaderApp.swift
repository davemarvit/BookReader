import SwiftUI
import RevenueCat

@main
struct BookReaderApp: App {
    init() {
 //       Purchases.configure(withAPIKey: "test_tHUwnlVAAiOTGzyqihAUYAqpvkM")
    }
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
