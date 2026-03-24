import SwiftUI
import AVFoundation

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var stats = StatsManager.shared
    @State private var showingResetConfirmation = false
    
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
            Section(header: 
                HStack {
                    Text("Reading Stats")
                    Spacer()
                    Button(action: {
                        showingResetConfirmation = true
                    }) {
                        Text("Reset")
                            .foregroundColor(.red)
                            .textCase(.none)
                    }
                }
            ) {
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
            
            Section(header: Text("Reader Appearance")) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Font Size: \(Int(settings.readerFontSize))pt")
                    Slider(value: $settings.readerFontSize, in: 12...36, step: 1)
                }
                .padding(.vertical, 4)
                
                Picker("Font Family", selection: $settings.readerFont) {
                    ForEach(ReaderFont.allCases) { font in
                        Text(font.displayName).tag(font.id)
                    }
                }
                
                Picker("Reading Theme", selection: $settings.readerTheme) {
                    ForEach(ReaderTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme.id)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(alignment: .top, spacing: 0) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(settings.currentTheme.textColor.opacity(0.6))
                            .frame(width: 4)
                            .padding(.vertical, 6)
                            .padding(.trailing, 12)
                        
                        Text("It was a dark and stormy night; the rain fell in torrents—except at occasional intervals, when it was checked by a violent gust of wind.")
                            .font(settings.currentFont)
                            .foregroundColor(settings.currentTheme.textColor)
                            .lineSpacing(6)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(settings.currentTheme.backgroundColor)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                }
                .padding(.vertical, 8)
            }
            
            Section(footer: Text(apiKeyStatus)) {
                // Info footer
            }
        }
        .confirmationDialog("Reset Stats", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
            Button("Reset reading stats", role: .destructive) {
                stats.resetStats()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently clear all your historical reading times. This action cannot be undone.")
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: HelpView()) {
                    Text("Help")
                }
            }
        }
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
