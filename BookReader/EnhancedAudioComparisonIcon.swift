import SwiftUI

struct EnhancedAudioComparisonIcon: View {
    // Structural layout constraints
    // Enforces absolute deterministic center-to-center spacing
    private let barPitch: CGFloat = 8
    
    // Enhanced styling (Left)
    private let enhancedWidth: CGFloat = 4.5
    private let enhancedHeights: [CGFloat] = [
        3, 4, 6, 10, 16, 26, 40, 58, 80, 100, 75, 88, 55, 68, 42, 52, 34, 22, 14
    ]
    
    // Spans only the enhanced HStack segment so it terminates abruptly
    private let enhancedGradient = LinearGradient(
        stops: [
            .init(color: Color(red: 0.0, green: 0.8, blue: 1.0), location: 0.0), // Cyan
            .init(color: Color(red: 0.4, green: 0.7, blue: 1.0), location: 0.3), // Light Blue
            .init(color: Color(red: 1.0, green: 0.8, blue: 1.0), location: 0.5), // Pinkish Peak
            .init(color: Color(red: 0.8, green: 0.4, blue: 0.9), location: 0.8), // Purple
            .init(color: Color(red: 0.5, green: 0.2, blue: 0.8), location: 1.0)  // Deep Violet
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    // Basic styling (Right)
    private let basicWidth: CGFloat = 2.5
    private let basicHeights: [CGFloat] = [
        18, 26, 36, 22, 32, 50, 68, 40, 56, 30, 20, 14, 8, 4, 3, 2, 2
    ]
    private let basicColor = Color.gray.opacity(0.6)
    
    var body: some View {
        HStack(spacing: 0) {
            
            // 1. Enhanced Segment
            HStack(spacing: 0) {
                ForEach(0..<enhancedHeights.count, id: \.self) { index in
                    Capsule()
                        .frame(width: enhancedWidth, height: enhancedHeights[index])
                        .frame(width: barPitch) // Traps varying widths inside a constant grid column
                }
            }
            .foregroundStyle(enhancedGradient)
            .shadow(color: Color(red: 0.1, green: 0.8, blue: 1.0).opacity(0.3), radius: 6, x: -4, y: 0)
            .shadow(color: Color(red: 0.6, green: 0.2, blue: 0.8).opacity(0.4), radius: 8, x: 4, y: 0)
            
            // 2. Strict Abrupt Seam
            // Zero-spacing HStack between the two sides guarantees the distance between the last enhanced bar
            // and the first basic bar is perfectly identical to all other internal gaps.
            
            // 3. Basic Segment
            HStack(spacing: 0) {
                ForEach(0..<basicHeights.count, id: \.self) { index in
                    Capsule()
                        .fill(basicColor)
                        .frame(width: basicWidth, height: basicHeights[index])
                        .frame(width: barPitch)
                }
            }
            .shadow(color: Color.white.opacity(0.15), radius: 3)
        }
    }
}
