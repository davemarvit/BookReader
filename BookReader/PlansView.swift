import SwiftUI

struct PlansView: View {
    @EnvironmentObject var audioController: AudioController
    
    // Safety check fallback
    var currentPlan: Plan {
        audioController.entitlementManager.currentPlan
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose Your Plan")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        benefitRow("More enhanced audio time")
                        benefitRow("Unlimited library")
                        benefitRow("Faster reading speeds (up to 4×)")
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal)
                
                // Plans List
                VStack(spacing: 16) {
                    if currentPlan == .free {
                        readerCard
                        avidReaderCard
                        freeCard
                    } else {
                        avidReaderCard
                        readerCard
                        freeCard
                    }
                }
                .padding(.horizontal)
                
                // Footer
                VStack {
                    Divider()
                    NavigationLink(destination: ManageSubscriptionView()) {
                        Text("Manage Subscription")
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
    }
    
    private var freeCard: some View {
        planCard(
            title: "Free",
            price: "$0",
            features: [
                "20 minutes/month of enhanced audio",
                "10-book library limit",
                "Playback speed limited to 1.5×"
            ],
            planType: .free
        )
    }
    
    private var readerCard: some View {
        planCard(
            title: "Reader",
            price: "$7.99 / month",
            features: [
                "10 hours/month of enhanced audio",
                "Unlimited library",
                "Playback speeds up to 4×"
            ],
            planType: .reader
        )
    }
    
    private var avidReaderCard: some View {
        planCard(
            title: "Avid Reader",
            price: "$14.99 / month",
            features: [
                "25 hours/month of enhanced audio",
                "Unlimited library",
                "Playback speeds up to 4×"
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
        let isCurrent = currentPlan == planType
        // Emphasize based on routing conditions
        let isUpgrade = (currentPlan == .free && planType != .free) || (currentPlan == .reader && planType == .avidReader)
        
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.bold)
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
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.top, 6)
                        Text(feature)
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                }
            }
            
            if isUpgrade {
                let ctaText = "Upgrade"
                Button(action: {
                    // Route to purchase logic for planType.displayName
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
        .padding(20)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isCurrent ? Color.secondary.opacity(0.3) : Color.clear, lineWidth: 2)
        )
    }
}
