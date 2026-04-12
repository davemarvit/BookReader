import SwiftUI
import RevenueCat

struct PlansView: View {
    @EnvironmentObject var audioController: AudioController
    
    @AppStorage("selectedTab") var selectedTab = 0
    @State private var showingSuccessModal = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose Your Plan")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        benefitRow("Listen to more books each month")
                        benefitRow("Unlimited library")
                        benefitRow("Faster reading speeds")
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal)
                
                // Plans List
                VStack(spacing: 12) {
                    avidReaderCard
                    readerCard
                    freeCard
                }
                .padding(.horizontal)
                
                // Footer
                VStack {
                    Divider()
                    NavigationLink(destination: ManageSubscriptionView()) {
                        Text("Manage Account")
                            .font(.headline)
                            .foregroundColor(.blue)
                            .padding()
                    }
                }
                .padding(.top, 16)
            }
            .padding(.vertical)
        }
        .navigationTitle("Plans")
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
                    selectedTab = 0
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(32)
            .interactiveDismissDisabled()
        }
        .onAppear {
            print("[VIEW] PlansView sees plan: \(audioController.entitlementManager.currentPlan)")
        }
    }
    
    private var freeCard: some View {
        planCard(
            title: "Free",
            price: "$0",
            features: [
                "Try ~1–2 chapters per month\n(20 minutes of enhanced audio)",
                "10-book library limit",
                "Speeds up to 1.5×"
            ],
            planType: .free
        )
    }
    
    private var readerCard: some View {
        planCard(
            title: "Reader",
            price: "$11.99 / month",
            features: [
                "Listen to ~1 book per month\n(10 hours of enhanced audio)",
                "Unlimited library",
                "Speeds up to 4×"
            ],
            planType: .reader
        )
    }
    
    private var avidReaderCard: some View {
        planCard(
            title: "Avid Reader",
            price: "$19.99 / month",
            features: [
                "Listen to ~2 books per month\n(20 hours of enhanced audio)",
                "Unlimited library",
                "Speeds up to 4×"
            ],
            planType: .avidReader
        )
    }
    
    private func benefitRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.blue)
                .font(.body)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private func planCard(title: String, price: String, features: [String], planType: Plan) -> some View {
        let currentPlan = audioController.entitlementManager.currentPlan
        let isCurrent = currentPlan == planType
        // Emphasize based on routing conditions
        let isUpgrade = (currentPlan == .free && planType != .free) || (currentPlan == .reader && planType == .avidReader)
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if planType == .avidReader {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(title)
                                .font(.system(size: 20, weight: .semibold))
                            
                            Text("· Best value")
                                .font(.system(size: 16))
                                .foregroundColor(.blue)
                        }
                    } else {
                        Text(title)
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    Text(price)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isCurrent {
                    Text("Current Plan")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .overlay(Capsule().stroke(Color.secondary.opacity(0.5), lineWidth: 1))
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(features, id: \.self) { feature in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.top, 5)
                        Text(feature)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .lineSpacing(2)
                    }
                }
            }
            
            if isUpgrade {
                let ctaText = "Upgrade"
                Button(action: {
                    let packageIdentifier: String?
                    if planType == .avidReader {
                        packageIdentifier = "avid_reader_monthly"
                    } else if planType == .reader {
                        packageIdentifier = "reader_monthly"
                    } else {
                        packageIdentifier = nil
                    }
                    
                    guard let packageIdentifier = packageIdentifier else { return }
                    
                    Task {
                        do {
                            print("Looking up package: \(packageIdentifier)")
                            let offerings = try await Purchases.shared.offerings()
                            guard let package = offerings.current?.availablePackages.first(where: { $0.identifier == packageIdentifier }) else {
                                print("Package lookup failure")
                                return
                            }
                            print("Purchasing package: \(packageIdentifier)")
                            let result = try await Purchases.shared.purchase(package: package)
                            print("Purchase success: \(packageIdentifier)")
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
                }) {
                    Text(ctaText)
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
                .padding(.top, 8)
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isCurrent ? Color.secondary.opacity(0.3) : Color.clear, lineWidth: 2)
        )
    }
}
