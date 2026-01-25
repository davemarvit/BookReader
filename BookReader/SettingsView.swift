import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    
    // A few curated voices for now
    let voices = [
        "en-US-Journey-D": "Google Journey (Male)",
        "en-US-Journey-F": "Google Journey (Female)",
        "en-US-Neural2-A": "Google Neural A (Male)",
        "en-US-Neural2-C": "Google Neural C (Female)",
        "en-US-Neural2-F": "Google Neural F (Female)"
    ]
    
    var body: some View {
        Form {
            Section(header: Text("Google Cloud TTS")) {
                SecureField("API Key", text: $settings.googleAPIKey)
                    .textContentType(.password)
                
                Picker("Voice", selection: $settings.selectedVoiceID) {
                    ForEach(voices.keys.sorted(), id: \.self) { key in
                        Text(voices[key] ?? key).tag(key)
                    }
                }
            }
            
            Section(header: Text("Library")) {
                Picker("Sort Order", selection: $settings.librarySortOption) {
                    Text("Most Recent").tag("recent")
                    Text("Title").tag("title")
                    Text("Author").tag("author")
                }
            }
            
            Section(footer: Text("Enter a valid Google Cloud API Key to use high-quality voices.")) {
                // Info footer
            }
        }
        .navigationTitle("Settings")
    }
}
