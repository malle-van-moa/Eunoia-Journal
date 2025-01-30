import SwiftUI

struct WeekProgressView: View {
    let journaledDays: Set<Int> // 1-7, where 1 is Monday
    let currentDay: Int
    var onDayTapped: ((Int) -> Void)?
    
    private let weekdays = ["M", "D", "M", "D", "F", "S", "S"]
    
    var body: some View {
        HStack(spacing: 12) {
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
            }
        }
        .padding(.vertical, 8)
    }
}

struct DayIndicator: View {
    let label: String
    let isJournaled: Bool
    let isToday: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Circle()
                .fill(isJournaled ? Color.blue : Color.secondary.opacity(0.2))
                .frame(width: 24, height: 24)
                .overlay(
                    Circle()
                        .strokeBorder(isToday ? Color.accentColor : .clear, lineWidth: 2)
                )
                .overlay(
                    Circle()
                        .fill(.white.opacity(0.2))
                        .blur(radius: isJournaled ? 4 : 0)
                )
                .animation(.easeInOut, value: isJournaled)
        }
        .overlay(
            Group {
                if isToday {
                    Circle()
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 4)
                        .frame(width: 36, height: 36)
                        .blur(radius: 4)
                }
            }
        )
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    WeekProgressView(
        journaledDays: [1, 2, 3, 5, 6, 7],
        currentDay: 4
    )
    .padding()
} 