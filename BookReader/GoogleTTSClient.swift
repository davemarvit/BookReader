import Foundation

class GoogleTTSClient: ObservableObject {
    private let baseURL = "https://texttospeech.googleapis.com/v1/text:synthesize"
    private let settings = SettingsManager.shared
    
    func fetchAudio(text: String, voiceID: String, speed: Double = 1.0) async throws -> Data {
        // Use Settings key, fallback to Secrets if empty
        let apiKey = settings.googleAPIKey.isEmpty ? Secrets.googleAPIKey : settings.googleAPIKey
        
        guard let url = URL(string: "\(baseURL)?key=\(apiKey)") else {
            throw URLError(.badURL)
        }
        
        let body: [String: Any] = [
            "input": ["text": text],
            "voice": [
                "languageCode": "en-US",
                "name": voiceID
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
