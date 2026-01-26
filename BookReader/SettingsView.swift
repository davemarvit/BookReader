import SwiftUI
import AVFoundation

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    
    @ObservedObject var stats = StatsManager.shared
    
    // Apple Voices (Computed to keep it dynamic)
    var appleVoices: [AVSpeechSynthesisVoice] {
        return AVSpeechSynthesisVoice.speechVoices().filter { $0.language.starts(with: "en") }
    }
    
    // A few curated voices for now
    let voices = [
        "en-US-Journey-D": "Google Journey (Male)",
        "en-US-Journey-F": "Google Journey (Female)",
        "en-US-Neural2-A": "Google Neural A (Male)",
        "en-US-Neural2-C": "Google Neural C (Female)",
        "en-US-Neural2-F": "Google Neural F (Female)"
    ]
    
    var sortedVoiceKeys: [String] {
        return voices.keys.sorted()
    }
    
    var body: some View {
        Form {
            Section(header: Text("Reading Stats")) {
                StatRow(label: "Today", value: stats.formatDuration(stats.timeToday))
                StatRow(label: "This Week", value: stats.formatDuration(stats.timeThisWeek))
                StatRow(label: "This Month", value: stats.formatDuration(stats.timeThisMonth))
                StatRow(label: "This Year", value: stats.formatDuration(stats.timeThisYear))
                StatRow(label: "All Time", value: stats.formatDuration(stats.timeEver))
            }
            
            Section(header: Text("Voice Settings")) {
                // Info Text
                Text(apiKeyStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
                
                SecureField("Google API Key", text: $settings.googleAPIKey)
                    .textContentType(.password)
                
                // Engine Selection
                Picker("Speech Engine", selection: $settings.preferredEngine) {
                    Text("Google Cloud (Premium)").tag("google")
                    Text("Apple System (Offline)").tag("apple")
                }
                .disabled(!settings.hasValidGoogleKey)
                
                if !settings.hasValidGoogleKey && settings.preferredEngine == "google" {
                    Text("Google Engine unavailable without API Key")
                        .font(.caption).foregroundColor(.red)
                }
                
                if settings.preferredEngine == "google" && settings.hasValidGoogleKey {
                    Picker("Google Voice", selection: $settings.selectedVoiceID) {
                        ForEach(sortedVoiceKeys, id: \.self) { (key: String) in
                            Text(voices[key] ?? key).tag(key)
                        }
                    }
                } else {
                    // Apple Voices
                    Picker("System Voice", selection: $settings.selectedAppleVoiceID) {
                        Text("Default").tag("")
                        ForEach(appleVoices, id: \.identifier) { (voice: AVSpeechSynthesisVoice) in
                            Text(voice.name).tag(voice.identifier)
                        }
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
            
            Section(footer: Text(apiKeyStatus)) {
                // Info footer
            }
        }
        .navigationTitle("Settings")
    }
    
    var apiKeyStatus: String {
        if !settings.googleAPIKey.isEmpty {
            return "Using User-Provided API Key"
        } else if !Secrets.googleAPIKey.isEmpty {
            return "Using Built-in API Key (Secrets)"
        } else {
            return "Enter a valid Google Cloud API Key to use high-quality voices."
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundColor(.secondary)
        }
    }
}
