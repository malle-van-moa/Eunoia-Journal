import SwiftUI

struct StreakIndicatorView: View {
    let streakCount: Int
    let isAnimating: Bool
    
    @State private var scale: CGFloat = 1
    @State private var opacity: Double = 1
    @State private var rotation: Double = 0
    
    private var streakColor: Color {
        if streakCount >= 30 {
            return .purple // Königlich für 30+ Tage
        } else if streakCount >= 15 {
            return .yellow // Gold für 15+ Tage
        } else if streakCount >= 7 {
            return .orange // Orange für 7+ Tage
        } else if streakCount >= 3 {
            return .green // Grün für 3-6 Tage
        } else {
            return .accentColor // Akzentfarbe für 0-2 Tage
        }
    }
    
    var body: some View {
        ZStack {
            // Hintergrund für höhere Streaks
            if streakCount >= 7 {
                RoundedRectangle(cornerRadius: 12)
                    .fill(streakColor.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(streakColor.opacity(0.3), lineWidth: 1)
                    )
            }
            
            // Streak-Anzeige - neu gestaltet für bessere Zentrierung und Höhennutzung
            HStack {
                Spacer()
                VStack(spacing: 0) {
                    Text("\(streakCount)")
                        .font(.system(size: 50, weight: .bold, design: .rounded))
                        .foregroundColor(streakColor)
                        .scaleEffect(scale)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .padding(.bottom, 0)
                        .padding(.top, -8)
                    
                    Text(streakCount == 1 ? "Tag" : "Tage")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer().frame(minHeight: 24)
                }
                .padding(.horizontal, 8)
                .padding(.top, -6)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        StreakIndicatorView(streakCount: 0, isAnimating: true)
        StreakIndicatorView(streakCount: 1, isAnimating: true)
        StreakIndicatorView(streakCount: 5, isAnimating: true)
        StreakIndicatorView(streakCount: 10, isAnimating: true)
        StreakIndicatorView(streakCount: 20, isAnimating: true)
        StreakIndicatorView(streakCount: 40, isAnimating: true)
    }
    .frame(height: 60)
    .padding()
} 