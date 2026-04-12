import SwiftUI
import RevenueCat

struct ManageSubscriptionView: View {
    @EnvironmentObject var audioController: AudioController
    
    var currentPlan: Plan {
        audioController.entitlementManager.currentPlan
    }
    
    var body: some View {
        Form {
            Section(header: Text("Current Subscription")) {
                LabeledContent("Plan", value: currentPlan.displayName)
                
                let monthlyAudio = currentPlan == .free ? "20 minutes/month" : (currentPlan == .reader ? "10 hours/month" : "20 hours/month")
                LabeledContent("Monthly Enhanced Audio", value: monthlyAudio)
                
                // Stub values for missing info safely
                LabeledContent("Enhanced Audio Remaining", value: "Not yet available")
                
                LabeledContent("Library", value: currentPlan == .free ? "Not yet available" : "Unlimited")
                
                let speedCap = currentPlan == .free ? "1.5×" : "4.0×"
                LabeledContent("Max Playback Speed", value: speedCap)
                
                LabeledContent("Renewal Date", value: "Not yet available")
            }
            
            Section(header: Text("Manage")) {
                if currentPlan == .free {
                    Button(action: {
                        Task {
                            do {
                                let offerings = try await Purchases.shared.offerings()
                                guard let package = offerings.current?.availablePackages.first(where: { $0.identifier == "avid_reader_monthly" }) else { return }
                                let result = try await Purchases.shared.purchase(package: package)
                                await MainActor.run {
                                    audioController.entitlementManager.refreshFromRevenueCat(customerInfo: result.customerInfo)
                                }
                            } catch { }
                        }
                    }) {
                        VStack(alignment: .leading) {
                            HStack(spacing: 6) {
                                Text("Upgrade to Avid Reader").foregroundColor(.blue)
                                Text("· (Best value)").foregroundColor(.blue)
                            }
                            Text("~2 books/month (20 hours of enhanced audio), unlimited library, playback up to 4x")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Button(action: {
                        Task {
                            do {
                                let offerings = try await Purchases.shared.offerings()
                                guard let package = offerings.current?.availablePackages.first(where: { $0.identifier == "reader_monthly" }) else { return }
                                let result = try await Purchases.shared.purchase(package: package)
                                await MainActor.run {
                                    audioController.entitlementManager.refreshFromRevenueCat(customerInfo: result.customerInfo)
                                }
                            } catch { }
                        }
                    }) {
                        VStack(alignment: .leading) {
                            Text("Upgrade to Reader").foregroundColor(.blue)
                            Text("~1 book per month (10 hours per month of enhanced audio), unlimited library, playback up to 4x")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                } else if currentPlan == .reader {
                    Button(action: {
                        Task {
                            do {
                                let offerings = try await Purchases.shared.offerings()
                                guard let package = offerings.current?.availablePackages.first(where: { $0.identifier == "avid_reader_monthly" }) else { return }
                                let result = try await Purchases.shared.purchase(package: package)
                                await MainActor.run {
                                    audioController.entitlementManager.refreshFromRevenueCat(customerInfo: result.customerInfo)
                                }
                            } catch { }
                        }
                    }) {
                        VStack(alignment: .leading) {
                            HStack(spacing: 6) {
                                Text("Upgrade to Avid Reader").foregroundColor(.blue)
                                Text("· (Best value)").foregroundColor(.blue)
                            }
                            Text("~2 books/month (20 hours of enhanced audio), unlimited library, playback up to 4x")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Button(action: {
                        if let window = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                            Task { try? await Purchases.shared.showManageSubscriptions(in: window) }
                        }
                    }) {
                        VStack(alignment: .leading) {
                            Text("Cancel Subscription").foregroundColor(.primary)
                            Text("Downgrades to Free at end of billing period")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                } else if currentPlan == .avidReader {
                    Button(action: {
                        if let window = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                            Task { try? await Purchases.shared.showManageSubscriptions(in: window) }
                        }
                    }) {
                        VStack(alignment: .leading) {
                            Text("Downgrade to Reader").foregroundColor(.blue)
                            Text("~1 book per month (10 hours per month of enhanced audio), unlimited library, playback up to 4x")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Button(action: {
                        if let window = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                            Task { try? await Purchases.shared.showManageSubscriptions(in: window) }
                        }
                    }) {
                        VStack(alignment: .leading) {
                            Text("Cancel Subscription").foregroundColor(.primary)
                            Text("Downgrades to Free at end of billing period")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Manage Account")
        .navigationBarTitleDisplayMode(.inline)
    }
}
