import Foundation

struct AppLogger {
    static func logEvent(_ event: String, metadata: [String: Any] = [:]) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        var logString = "[BookReader][\(timestamp)] \(event)"
        
        if !metadata.isEmpty {
            let metaString = metadata.map { "\($0.key)=\("\($0.value)".replacingOccurrences(of: " ", with: "_"))" }
                .joined(separator: " ")
            logString += " \(metaString)"
        }
        
        // Use print for minimal framework-free integration
        print(logString)
    }
}
