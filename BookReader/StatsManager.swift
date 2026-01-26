import Foundation
import Combine

class StatsManager: ObservableObject {
    static let shared = StatsManager()
    
    // Storage Keys
    private let kDailyProgress = "stats_dailyProgress"
    private let kTotalTime = "stats_totalTime"
    
    // Data: [DateString (YYYY-MM-DD): Seconds]
    @Published var dailyProgress: [String: TimeInterval] = [:]
    @Published var totalReadingTime: TimeInterval = 0
    
    private init() {
        loadStats()
    }
    
    // MARK: - Persistence
    
    private func loadStats() {
        totalReadingTime = UserDefaults.standard.double(forKey: kTotalTime)
        if let data = UserDefaults.standard.dictionary(forKey: kDailyProgress) as? [String: TimeInterval] {
            dailyProgress = data
        }
    }
    
    private func saveStats() {
        UserDefaults.standard.set(totalReadingTime, forKey: kTotalTime)
        UserDefaults.standard.set(dailyProgress, forKey: kDailyProgress)
    }
    
    // MARK: - Tracking
    
    func logReadingTime(seconds: TimeInterval) {
        guard seconds > 0 else { return }
        
        // Update Total
        totalReadingTime += seconds
        
        // Update Daily
        let today = formatDate(Date())
        let current = dailyProgress[today] ?? 0
        dailyProgress[today] = current + seconds
        
        saveStats()
    }
    
    // MARK: - Querying
    
    var timeToday: TimeInterval {
        let today = formatDate(Date())
        return dailyProgress[today] ?? 0
    }
    
    var timeThisWeek: TimeInterval {
        // Simple approximation: Sum of last 7 days keys
        // For strict "This Week" (since Sunday), requires Calendar math.
        // User asked for "This Week" (Rolling or Calendar?).
        // Let's do Rolling 7 Days for utility.
        var total: TimeInterval = 0
        let calendar = Calendar.current
        for i in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: -i, to: Date()) {
                let key = formatDate(date)
                total += dailyProgress[key] ?? 0
            }
        }
        return total
    }
    
    var timeThisMonth: TimeInterval {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: Date())
        
        return dailyProgress.filter { key, _ in
            // Key is YYYY-MM-DD
            // Check if key starts with YYYY-MM
            let prefix = String(format: "%04d-%02d", components.year!, components.month!)
            return key.hasPrefix(prefix)
        }.values.reduce(0, +)
    }
    
    var timeThisYear: TimeInterval {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: Date())
        let prefix = String(format: "%04d", year)
        
        return dailyProgress.filter { key, _ in
            return key.hasPrefix(prefix)
        }.values.reduce(0, +)
    }
    
    var timeEver: TimeInterval {
        return totalReadingTime
    }
    
    // Helpers
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "0m"
    }
}
