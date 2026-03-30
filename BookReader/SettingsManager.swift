import Foundation
import SwiftUI

enum ReaderTheme: String, CaseIterable, Identifiable {
    case system, light, dark, lowContrastDark, sepia
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .system: return "System Default"
        case .light: return "Light"
        case .dark: return "Dark (True Black)"
        case .lowContrastDark: return "Dark (Low Contrast)"
        case .sepia: return "Sepia"
        }
    }
    
    var backgroundColor: Color {
        switch self {
        case .system: return Color(UIColor.systemBackground)
        case .light: return .white
        case .dark: return .black
        case .lowContrastDark: return Color(red: 40/255, green: 40/255, blue: 40/255)
        case .sepia: return Color(red: 244/255, green: 236/255, blue: 216/255)
        }
    }
    
    var textColor: Color {
        switch self {
        case .system: return .primary
        case .light: return .black
        case .dark: return .white
        case .lowContrastDark: return Color(red: 200/255, green: 200/255, blue: 200/255)
        case .sepia: return Color(red: 94/255, green: 75/255, blue: 54/255)
        }
    }
}

enum ReaderFont: String, CaseIterable, Identifiable {
    case system, serif, rounded, monospaced, georgia, avenir
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .system: return "San Francisco (Default)"
        case .serif: return "New York (Serif)"
        case .rounded: return "SF Rounded"
        case .monospaced: return "SF Mono"
        case .georgia: return "Georgia"
        case .avenir: return "Avenir"
        }
    }
    
    func font(size: Double) -> Font {
        switch self {
        case .system: return .system(size: size, design: .default)
        case .serif: return .system(size: size, design: .serif)
        case .rounded: return .system(size: size, design: .rounded)
        case .monospaced: return .system(size: size, design: .monospaced)
        case .georgia: return .custom("Georgia", size: size)
        case .avenir: return .custom("AvenirNext-Regular", size: size)
        }
    }
}

class SettingsManager: ObservableObject {
    @AppStorage("googleAPIKey") var googleAPIKey: String = ""
    @AppStorage("selectedVoiceID") var selectedVoiceID: String = "en-US-Journey-D" // Default Google Voice
    @AppStorage("selectedAppleVoiceID") var selectedAppleVoiceID: String = "" // Default System Voice (empty = default)
    @AppStorage("preferredEngine") var preferredEngine: String = "apple" // apple, google
    @AppStorage("librarySortOption") var librarySortOption: String = "recent" // recent, title, author
    
    // Reader Appearance
    @AppStorage("readerFontSize") var readerFontSize: Double = 18.0
    @AppStorage("readerFont") var readerFont: String = "system"
    @AppStorage("readerTheme") var readerTheme: String = "system"
    
    static let shared = SettingsManager()
    
    var hasValidGoogleKey: Bool {
        return !googleAPIKey.isEmpty || !Secrets.googleAPIKey.isEmpty
    }
    
    // Helpers
    var currentFont: Font {
        let rFont = ReaderFont(rawValue: readerFont) ?? .system
        return rFont.font(size: readerFontSize)
    }
    
    var currentTheme: ReaderTheme {
        return ReaderTheme(rawValue: readerTheme) ?? .system
    }
    
    // MARK: - Playback Controller Helpers
    
    var preferredVoiceMode: VoiceMode {
        return preferredEngine == "google" ? .premium : .standard
    }
    
    var currentPremiumVoiceID: String {
        return selectedVoiceID
    }
    
    var currentStandardVoiceID: String {
        return selectedAppleVoiceID.isEmpty ? "apple-default" : selectedAppleVoiceID
    }
}
