import SwiftUI
import RevenueCat

@main
struct BookReaderApp: App {
    init() {
        Purchases.configure(withAPIKey: "appl_hTpIUdDDigzfdwnhmtiTDlpjRIJ")

        Purchases.shared.getOfferings { offerings, error in
            if let error = error {
                print("RC Error: \(error.localizedDescription)")
            } else {
                print("RC Offerings: \(String(describing: offerings))")
            }
        }
    }

    @StateObject private var libraryManager = LibraryManager()
    @StateObject private var audioController = AudioController()

    var body: some Scene {
        WindowGroup {
            ContentView(libraryManager: libraryManager)
                .environmentObject(audioController)
                .onAppear {
                    audioController.libraryManager = libraryManager
                    Purchases.shared.getCustomerInfo { info, error in
                        if let error = error {
                            print("RC CustomerInfo Error: \(error.localizedDescription)")
                        } else if let info = info {
                            audioController.entitlementManager.refreshFromRevenueCat(customerInfo: info)
                            print("RC CustomerInfo loaded. Active entitlements: \(info.entitlements.active.keys.sorted())")
                            print("RC current plan after refresh: \(audioController.entitlementManager.currentPlan)")
                        }
                    }
                }
                .onOpenURL { url in
                    _ = libraryManager.importBook(from: url)
                }
        }
    }
}
