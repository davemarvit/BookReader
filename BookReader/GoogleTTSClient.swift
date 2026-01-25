import Foundation

enum TTSVoice: String, CaseIterable, Identifiable {
    case standardMale = "en-US-Standard-A"
    case standardFemale = "en-US-Standard-B"
    case waveNetMale = "en-US-Wavenet-D"
    case waveNetFemale = "en-US-Wavenet-F"
    case neural2Female = "en-US-Neural2-F"
    case neural2Male = "en-US-Neural2-D"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .standardMale: return "Standard Male"
        case .standardFemale: return "Standard Female"
        case .waveNetMale: return "WaveNet Male (Premium)"
        case .waveNetFemale: return "WaveNet Female (Premium)"
        case .neural2Female: return "Neural2 Female (Premium)"
        case .neural2Male: return "Neural2 Male (Premium)"
        }
    }
}

class GoogleTTSClient: ObservableObject {
    private let baseURL = "https://texttospeech.googleapis.com/v1/text:synthesize"
    
    func fetchAudio(text: String, voice: TTSVoice = .neural2Female, speed: Double = 1.0) async throws -> Data {
        guard let url = URL(string: "\(baseURL)?key=\(Secrets.googleAPIKey)") else {
            throw URLError(.badURL)
        }
        
        let body: [String: Any] = [
            "input": ["text": text],
            "voice": [
                "languageCode": "en-US",
                "name": voice.rawValue
            ],
            "audioConfig": [
                "audioEncoding": "MP3",
                "speakingRate": speed
            ]
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: body)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode != 200 {
            if let errorText = String(data: data, encoding: .utf8) {
                print("TTS Error: \(errorText)")
            }
            throw URLError(.badServerResponse)
        }
        
        // Response format: { "audioContent": "base64string..." }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let base64String = json["audioContent"] as? String,
              let audioData = Data(base64Encoded: base64String) else {
            throw URLError(.cannotDecodeContentData)
        }
        
        return audioData
    }
}
