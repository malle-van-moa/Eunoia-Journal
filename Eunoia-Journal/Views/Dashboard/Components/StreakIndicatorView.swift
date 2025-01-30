import SwiftUI

struct StreakIndicatorView: View {
    let streakCount: Int
    let isAnimating: Bool
    
    @State private var scale: CGFloat = 1
    @State private var opacity: Double = 1
    @State private var rotation: Double = 0
    
    private var streakColor: Color {
        if streakCount >= 10 {
            return .yellow // Gold color for 10+ days
        } else if streakCount >= 3 {
            return .orange
        } else {
            return .blue
        }
    }
    
    var body: some View {
        // Streak Number
        Text("\(streakCount)")
            .font(.system(size: 48, weight: .bold, design: .rounded))
            .foregroundColor(streakColor)
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotation))
            .overlay(
                streakCount >= 10 ?
                Circle()
                    .fill(streakColor.opacity(0.2))
                    .blur(radius: 20)
                    .scaleEffect(1.2)
                : nil
            )
            .onChange(of: streakCount) {
                if isAnimating {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        scale = 1.2
                        opacity = 0.8
                        rotation = 5
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            scale = 1
                            opacity = 1
                            rotation = 0
                        }
                    }
                }
            }
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    VStack(spacing: 20) {
        StreakIndicatorView(streakCount: 1, isAnimating: true)
        StreakIndicatorView(streakCount: 5, isAnimating: true)
        StreakIndicatorView(streakCount: 12, isAnimating: true)
    }
    .padding()
} 