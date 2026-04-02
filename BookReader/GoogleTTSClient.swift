//  GoogleTTSClient.swift

import Foundation

enum GoogleTTSError: Error, LocalizedError {
    case badURL
    case invalidAPIKey
    case quotaExceeded
    case billingIssue
    case timeout
    case badResponse(statusCode: Int, message: String?)
    case decodeFailure
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "The API endpoint URL is invalid."
        case .invalidAPIKey:
            return "The provided Google API key is invalid or unauthorized."
        case .quotaExceeded:
            return "The premium TTS quota has been exceeded."
        case .billingIssue:
            return "There is a billing issue with the Google Cloud account."
        case .timeout:
            return "The premium audio request timed out."
        case .badResponse(let statusCode, let message):
            return "Server returned status \(statusCode): \(message ?? "Unknown error")"
        case .decodeFailure:
            return "Failed to decode the audio response from the server."
        case .network(let error):
            return error.localizedDescription
        }
    }
}

final class GoogleTTSClient: ObservableObject {
    private let baseURL = "https://texttospeech.googleapis.com/v1/text:synthesize"
    private let settings = SettingsManager.shared

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        return URLSession(configuration: config)
    }()

    func fetchAudio(text: String, voiceID: String, speed: Double = 1.0) async throws -> Data {
        print("GOOGLE_TTS: entered fetchAudio voiceID=\(voiceID) textLength=\(text.count)")
        let apiKey = settings.googleAPIKey.isEmpty ? Secrets.googleAPIKey : settings.googleAPIKey

        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GoogleTTSError.invalidAPIKey
        }

        guard var components = URLComponents(string: baseURL) else {
            throw GoogleTTSError.badURL
        }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        guard let url = components.url else {
            throw GoogleTTSError.badURL
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

        let jsonData: Data
        do {
            print("GOOGLE_TTS: building request body")
            jsonData = try JSONSerialization.data(withJSONObject: body)
            print("GOOGLE_TTS: request body serialized")
        } catch {
            throw GoogleTTSError.network(error)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let data: Data
        let response: URLResponse
        do {
            print("GOOGLE_TTS: about to call session.data")
            let result = try await session.data(for: request)
            data = result.0
            response = result.1
            print("GOOGLE_TTS: session.data returned")
        } catch let error as URLError {
            print("GOOGLE_TTS: session.data threw URLError \(error.code.rawValue) \(error.localizedDescription)")
            if error.code == .timedOut {
                throw GoogleTTSError.timeout
            } else {
                throw GoogleTTSError.network(error)
            }
        } catch {
            print("GOOGLE_TTS: session.data threw non-URLError \(error)")
            throw GoogleTTSError.network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleTTSError.badResponse(statusCode: 0, message: "Invalid response type")
        }

        print("GOOGLE_TTS: HTTP status \(httpResponse.statusCode)")

        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8)
            let lowercasedError = errorText?.lowercased() ?? ""

            let isBillingError = lowercasedError.contains("billing")
            let isQuotaError = lowercasedError.contains("quota")
                || lowercasedError.contains("resource_exhausted")
                || httpResponse.statusCode == 429
            let isAuthError = lowercasedError.contains("api_key_invalid")
                || lowercasedError.contains("api key not valid")
                || lowercasedError.contains("unauthorized")
                || httpResponse.statusCode == 401
                || httpResponse.statusCode == 403

            if isBillingError {
                throw GoogleTTSError.billingIssue
            } else if isQuotaError {
                throw GoogleTTSError.quotaExceeded
            } else if isAuthError {
                throw GoogleTTSError.invalidAPIKey
            } else {
                throw GoogleTTSError.badResponse(statusCode: httpResponse.statusCode, message: errorText)
            }
        }

        do {
            print("GOOGLE_TTS: decoding audioContent")
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let base64String = json["audioContent"] as? String,
                let audioData = Data(base64Encoded: base64String)
            else {
                throw GoogleTTSError.decodeFailure
            }
            print("GOOGLE_TTS: returning audio data bytes=\(audioData.count)")
            return audioData
        } catch let error as GoogleTTSError {
            throw error
        } catch {
            throw GoogleTTSError.decodeFailure
        }
    }
}
