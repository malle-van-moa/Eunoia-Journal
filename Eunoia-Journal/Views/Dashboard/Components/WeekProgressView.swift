import SwiftUI

struct WeekProgressView: View {
    let journaledDays: Set<Int> // 1-7, where 1 is Monday
    let currentDay: Int
    var onDayTapped: ((Int) -> Void)?
    
    private let weekdays = ["M", "D", "M", "D", "F", "S", "S"]
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(0..<7) { index in
                    let day = index + 1
                    DayIndicator(
                        label: weekdays[index],
                        isJournaled: journaledDays.contains(day),
                        isToday: day == currentDay
                    )
                    .onTapGesture {
                        onDayTapped?(day)
                    }
                    .frame(width: geometry.size.width / 7)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

struct DayIndicator: View {
    let label: String
    let isJournaled: Bool
    let isToday: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundColor(isToday ? .accentColor : .primary.opacity(0.7))
            
            Circle()
                .fill(isJournaled ? Color.accentColor : Color.secondary.opacity(0.2))
                .frame(width: 24, height: 24)
                .overlay(
                    Circle()
                        .strokeBorder(isToday ? Color.accentColor : .clear, lineWidth: 1.5)
                )
                .overlay(
                    Circle()
                        .fill(.white.opacity(0.2))
                        .blur(radius: isJournaled ? 4 : 0)
                )
                .animation(.easeInOut, value: isJournaled)
        }
        .contentShape(Rectangle())
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    WeekProgressView(
        journaledDays: [1, 2, 3, 5, 6, 7],
        currentDay: 4
    )
    .frame(height: 50)
    .padding()
} 