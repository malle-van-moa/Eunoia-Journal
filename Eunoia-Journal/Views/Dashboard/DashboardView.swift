import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @StateObject private var journalViewModel = JournalViewModel()
    @State private var showingMoodPicker = false
    @State private var showingJournalSheet = false
    @State private var showingLastEntries = false
    
    private let adaptiveColumns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        ScrollView {
            ZStack(alignment: .top) {
                // Background Image
                Image("watercolor_painting_mountains_lake")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 300)
                    .clipped()
                    .overlay(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.clear,
                                Color(UIColor.systemBackground)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Content
                VStack(spacing: 20) {
                    // Greeting Card
                    DashboardCard(
                        title: viewModel.greeting,
                        systemImage: "sun.max.fill",
                        gradient: Gradient(colors: [.orange.opacity(0.6), .yellow.opacity(0.6)])
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(viewModel.motivationalMessage)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            if let mood = viewModel.currentMood {
                                HStack {
                                    Text("Deine Stimmung:")
                                    Text(mood.rawValue)
                                        .font(.title2)
                                }
                            } else {
                                Button {
                                    showingMoodPicker = true
                                } label: {
                                    Text("Wie fühlst du dich heute?")
                                        .font(.subheadline)
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                    .background(Color(UIColor.systemBackground).opacity(0.8))
                    
                    // Progress Card
                    DashboardCard(
                        title: "Fortschritt",
                        systemImage: "flame.fill",
                        gradient: Gradient(colors: [.red.opacity(0.6), .orange.opacity(0.6)])
                    ) {
                        VStack(spacing: 16) {
                            StreakIndicatorView(
                                streakCount: viewModel.streakCount,
                                isAnimating: viewModel.isStreakAnimating
                            )
                            
                            WeekProgressView(
                                journaledDays: viewModel.journaledDaysThisWeek,
                                currentDay: viewModel.currentWeekday
                            ) { day in
                                viewModel.checkMissedDay(day)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .alert("Verpasster Tag", isPresented: $viewModel.showingMissedDayAlert) {
                        Button("Eintrag nachholen") {
                            showingJournalSheet = true
                        }
                        Button("Abbrechen", role: .cancel) {}
                    } message: {
                        if viewModel.lastStreakCount > 0 {
                            Text("Dein letzter Streak war \(viewModel.lastStreakCount) Tage. Lass uns neu starten!")
                        } else {
                            Text("Möchtest du einen Eintrag nachholen?")
                        }
                    }
                    
                    // Challenge Card
                    if let challenge = viewModel.dailyChallenge {
                        DashboardCard(
                            title: challenge.title,
                            systemImage: "trophy.fill",
                            gradient: Gradient(colors: [.green.opacity(0.6), .mint.opacity(0.6)])
                        ) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(challenge.description)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                if challenge.isCompleted {
                                    Label("Abgeschlossen", systemImage: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }
                    
                    // Main Functions Grid
                    LazyVGrid(columns: adaptiveColumns, spacing: 16) {
                        // Journal Card
                        DashboardCard(
                            title: "Journal",
                            systemImage: "book.fill",
                            gradient: Gradient(colors: [.blue.opacity(0.6), .cyan.opacity(0.6)])
                        ) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Starte deinen Tag mit Reflexion")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .onTapGesture {
                            showingJournalSheet = true
                        }
                        .onLongPressGesture {
                            showingLastEntries = true
                        }
                        
                        // Vision Board Card
                        NavigationLink {
                            VisionBoardView(viewModel: VisionBoardViewModel())
                        } label: {
                            DashboardCard(
                                title: "Vision Board",
                                systemImage: "star.fill",
                                gradient: Gradient(colors: [.purple.opacity(0.6), .pink.opacity(0.6)])
                            ) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Manifestiere deine Vision")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    // Scroll to top and reset any navigation
                    // This will be handled by the navigation stack
                } label: {
                    Text("Eunoia")
                        .font(.title2.bold())
                        .foregroundColor(.primary)
                }
            }
        }
        .sheet(isPresented: $showingMoodPicker) {
            MoodPickerView(selectedMood: Binding(
                get: { viewModel.currentMood ?? .neutral },
                set: { viewModel.updateMood($0) }
            ))
        }
        .sheet(isPresented: $showingJournalSheet) {
            NavigationView {
                JournalEntryView(viewModel: journalViewModel)
            }
        }
        .sheet(isPresented: $showingLastEntries) {
            LastEntriesView(entries: viewModel.lastJournalEntries)
        }
    }
}

// MARK: - Supporting Views

struct MoodPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedMood: Mood
    
    private let columns = [
        GridItem(.adaptive(minimum: 80, maximum: 100))
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Wie fühlst du dich heute?")
                        .font(.title2)
                        .padding()
                    
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(Array(Mood.allCases), id: \.self) { mood in
                            Button {
                                selectedMood = mood
                                dismiss()
                            } label: {
                                VStack(spacing: 4) {
                                    Text(mood.rawValue)
                                        .font(.system(size: 32))
                                    Text(mood.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.secondary.opacity(0.1))
                                )
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Stimmung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct LastEntriesView: View {
    @Environment(\.dismiss) private var dismiss
    let entries: [JournalEntry]
    
    var body: some View {
        NavigationView {
            List {
                if entries.isEmpty {
                    Text("Keine Einträge vorhanden")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(entries.indices, id: \.self) { index in
                        let entry = entries[index]
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(entry.date, style: .date)
                                    .font(.headline)
                                Spacer()
                                if entry.learningNugget != nil {
                                    Image(systemName: "lightbulb.fill")
                                        .foregroundColor(.yellow)
                                }
                            }
                            
                            if !entry.gratitude.isEmpty {
                                Text("Dankbarkeit: \(entry.gratitude)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            
                            if !entry.highlight.isEmpty {
                                Text("Highlight: \(entry.highlight)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            
                            if !entry.learning.isEmpty {
                                Text("Lernen: \(entry.learning)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Letzte Einträge")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            DashboardView()
        }
    }
} 