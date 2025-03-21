import SwiftUI

struct WeekProgressView: View {
    let journaledDays: Set<Int> // 1-7, where 1 is Monday
    let currentDay: Int
    var firstDayOfWeek: Int = 1 // Standardmäßig Montag (1)
    var onDayTapped: ((Int) -> Void)?
    
    private let weekdays = ["M", "D", "M", "D", "F", "S", "S"]
    
    // Gibt eine neu sortierte Liste der Wochentage zurück, beginnend mit firstDayOfWeek
    private var sortedWeekdayIndices: [Int] {
        // Tage von 0 bis 6 (für Array-Indexierung)
        let allDays = Array(0..<7)
        
        // Offset berechnen (firstDayOfWeek ist 1-7, daher -1 für 0-basierte Indizes)
        let offset = firstDayOfWeek - 1
        
        // Array rotieren
        return Array(allDays.dropFirst(offset) + allDays.prefix(offset))
    }
    
    // Konvertiert einen UI-Index (0-6) in einen tatsächlichen Wochentag (1-7)
    private func actualWeekday(for uiIndex: Int) -> Int {
        let dayOffset = sortedWeekdayIndices[uiIndex]
        let actualDay = dayOffset + 1 // Konvertieren zu 1-basiertem Wochentag
        return actualDay
    }
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(0..<7) { uiIndex in
                    let actualDay = actualWeekday(for: uiIndex)
                    let weekdayLabel = weekdays[sortedWeekdayIndices[uiIndex]]
                    
                    DayIndicator(
                        label: weekdayLabel,
                        isJournaled: journaledDays.contains(actualDay),
                        isToday: actualDay == currentDay
                    )
                    .onTapGesture {
                        onDayTapped?(actualDay)
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
        currentDay: 4,
        firstDayOfWeek: 3 // Start mit Mittwoch
    )
    .frame(height: 50)
    .padding()
} 