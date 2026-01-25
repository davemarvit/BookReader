import Foundation
import SwiftUI

class SettingsManager: ObservableObject {
    @AppStorage("googleAPIKey") var googleAPIKey: String = ""
    @AppStorage("selectedVoiceID") var selectedVoiceID: String = "en-US-Journey-D" // Default Google Voice
    @AppStorage("librarySortOption") var librarySortOption: String = "recent" // recent, title, author
    
    static let shared = SettingsManager()
}
