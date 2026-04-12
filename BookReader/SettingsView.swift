import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject var audioController: AudioController
    @ObservedObject var settings = SettingsManager.shared
    @Binding var selectedTab: Int
    @Binding var lastTab: Int

    @State private var showingPlans = false
    @State private var showingManage = false

    // Apple Voices (Computed to keep it dynamic)
    var appleVoices: [AVSpeechSynthesisVoice] {
        return AVSpeechSynthesisVoice.speechVoices().filter { $0.language.starts(with: "en") }
    }
    
    // A few curated voices for now
    let voices = [
        "en-US-Standard-A": "Google Standard A (Male, Basic)",
        "en-US-Standard-B": "Google Standard B (Female, Basic)",
        "en-US-Wavenet-D": "Google WaveNet D (Male, Premium)",
        "en-US-Wavenet-F": "Google WaveNet F (Female, Premium)",
        "en-US-Journey-D": "Google Journey D (Male, Ultra)",
        "en-US-Journey-F": "Google Journey F (Female, Ultra)",
        "en-US-Neural2-A": "Google Neural A (Male, Premium)",
        "en-US-Neural2-F": "Google Neural F (Female, Premium)",
        "en-US-Chirp-HD-D": "Experimental • Chirp HD (High Quality)",
        "en-US-Studio-M": "Experimental • Studio (Ultra Quality)"
    ]
    
    var sortedVoiceKeys: [String] {
        let all = voices.keys.sorted()
        let production = all.filter { !(voices[$0]?.starts(with: "Experimental") ?? false) }
        let experimental = all.filter { voices[$0]?.starts(with: "Experimental") ?? false }
        return production + experimental
    }
    
    var body: some View {
        Form {

            Section(header: Text("Account")) {
                NavigationLink("Upgrade", destination: PlansView(), isActive: $showingPlans)
                NavigationLink("Manage Account", destination: ManageSubscriptionView(), isActive: $showingManage)
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
            
            Section(header: Text("Debug Plan Override")) {
                Picker("Plan", selection: Binding(
                    get: { audioController.entitlementManager.currentPlan },
                    set: { audioController.entitlementManager.currentPlan = $0 }
                )) {
                    ForEach(Plan.allCases, id: \.self) { plan in
                        Text(plan.displayName).tag(plan)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            Section(footer: Text(apiKeyStatus)) {
                // Info footer
            }

        }

        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    selectedTab = lastTab
                }) {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: HelpView()) {
                    Text("Help")
                }
            }
        }
        .onChange(of: settings.activeRoute) { route in
            if route == .plans {
                showingPlans = true
                settings.activeRoute = nil
            } else if route == .manage {
                showingManage = true
                settings.activeRoute = nil
            }
        }
        .onChange(of: selectedTab) { _ in
            showingPlans = false
            showingManage = false
        }
        .onAppear {
            print("[VIEW] SettingsView sees plan: \(audioController.entitlementManager.currentPlan)")
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
