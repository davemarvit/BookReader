import SwiftUI
import RevenueCat

struct ManageSubscriptionView: View {
    @EnvironmentObject var audioController: AudioController
    
    @State private var showingSuccessModal = false
    
    var body: some View {
        let currentPlan = audioController.entitlementManager.currentPlan
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
                        purchasePackage(identifier: "avid_reader_monthly")
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
                        purchasePackage(identifier: "reader_monthly")
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
                        purchasePackage(identifier: "avid_reader_monthly")
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
                        openManagementURL()
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
                        openManagementURL()
                    }) {
                        VStack(alignment: .leading) {
                            Text("Downgrade to Reader").foregroundColor(.blue)
                            Text("~1 book per month (10 hours per month of enhanced audio), unlimited library, playback up to 4x")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Button(action: {
                        openManagementURL()
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
        .sheet(isPresented: $showingSuccessModal) {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.green)
                    .padding(.bottom, 8)
                
                let currentPlan = audioController.entitlementManager.currentPlan
                Text(currentPlan == .avidReader ? "Welcome to Avid Reader" : "Welcome to Reader")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(currentPlan == .avidReader ? 
                    "You now have up to 20 hours of enhanced audio each month, an unlimited library, and playback speeds up to 4x." :
                    "You now have up to 10 hours of enhanced audio each month, an unlimited library, and playback speeds up to 4x.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                Button("Start Listening") {
                    showingSuccessModal = false
                    SettingsManager.shared.activeRoute = nil
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(32)
            .interactiveDismissDisabled()
        }
        .onAppear {
            print("[VIEW] ManageSubscriptionView sees plan: \(audioController.entitlementManager.currentPlan)")
        }
    }
    
    private func purchasePackage(identifier: String) {
        Task {
            do {
                let offerings = try await Purchases.shared.offerings()
                guard let package = offerings.current?.availablePackages.first(where: { $0.identifier == identifier }) else {
                    print("Package lookup failure: \(identifier)")
                    return
                }
                let result = try await Purchases.shared.purchase(package: package)
                print("Purchase success: \(identifier)")
                print("Active Entitlements: \(result.customerInfo.entitlements.active.keys.sorted())")
                await MainActor.run {
                    audioController.entitlementManager.refreshFromRevenueCat(customerInfo: result.customerInfo)
                    let resolvedPlan = audioController.entitlementManager.currentPlan
                    print("Resolved Plan: \(resolvedPlan)")
                    self.showingSuccessModal = true
                }
            } catch {
                print("Purchase failure: \(error.localizedDescription)")
            }
        }
    }
    
    private func openManagementURL() {
        Task {
            do {
                let customerInfo = try await Purchases.shared.customerInfo()
                guard let url = customerInfo.managementURL else {
                    print("Missing management URL")
                    return
                }
                await MainActor.run {
                    UIApplication.shared.open(url, options: [:]) { success in
                        if !success {
                            print("Management URL open failure")
                        }
                    }
                }
            } catch {
                print("Management URL open failure: \(error.localizedDescription)")
            }
        }
    }
}
