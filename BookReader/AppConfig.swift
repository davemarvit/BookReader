import Foundation

struct AppConfig {
    static let shared = AppConfig()
    
    let isMonetizationBeta: Bool
    
    private init() {
        if let flag = Bundle.main.infoDictionary?["IsMonetizationBeta"] as? Bool {
            self.isMonetizationBeta = flag
        } else {
            self.isMonetizationBeta = false
        }
    }
}
