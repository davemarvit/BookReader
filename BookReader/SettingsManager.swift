import Foundation
import SwiftUI

class SettingsManager: ObservableObject {
    @AppStorage("googleAPIKey") var googleAPIKey: String = ""
    @AppStorage("selectedVoiceID") var selectedVoiceID: String = "en-US-Journey-D" // Default Google Voice
    @AppStorage("selectedAppleVoiceID") var selectedAppleVoiceID: String = "" // Default System Voice (empty = default)
    @AppStorage("preferredEngine") var preferredEngine: String = "google" // google, apple
    @AppStorage("librarySortOption") var librarySortOption: String = "recent" // recent, title, author
    
    static let shared = SettingsManager()
    
    var hasValidGoogleKey: Bool {
        return !googleAPIKey.isEmpty || !Secrets.googleAPIKey.isEmpty
    }
}
