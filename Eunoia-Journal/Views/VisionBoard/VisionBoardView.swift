import SwiftUI

struct VisionBoardView: View {
    @ObservedObject var viewModel: VisionBoardViewModel
    @State private var showingExercisePicker = false
    @State private var showingAddValue = false
    @State private var showingAddGoal = false
    @State private var showingEditLifestyle = false
    @State private var showingEditPersonality = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Progress Overview
                ProgressOverviewCard(progress: viewModel.completionProgress)
                
                // Vision Board Sections
                if let board = viewModel.visionBoard {
                    // Personal Values Section
                    VisionBoardSection(
                        title: "Persönliche Werte",
                        systemImage: "heart.fill",
                        color: .red
                    ) {
                        if board.personalValues.isEmpty {
                            EmptyStateButton(
                                title: "Definiere deine Werte",
                                exercise: .values
                            ) {
                                viewModel.startExercise(.values)
                                showingExercisePicker = true
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 15) {
                                ForEach(board.personalValues) { value in
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack {
                                            Text(value.name)
                                                .font(.headline)
                                            Spacer()
                                            HStack {
                                                ForEach(0..<value.importance, id: \.self) { _ in
                                                    Image(systemName: "star.fill")
                                                        .foregroundColor(.yellow)
                                                }
                                            }
                                        }
                                        if !value.description.isEmpty {
                                            Text(value.description)
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding()
                                    .background(Color(.systemBackground))
                                    .cornerRadius(10)
                                }
                                
                                Button(action: {
                                    showingAddValue = true
                                }) {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                        Text("Wert hinzufügen")
                                    }
                                }
                                .padding()
                            }
                        }
                    }
                    
                    // Goals Section
                    VisionBoardSection(
                        title: "Lebensziele",
                        systemImage: "target",
                        color: .orange
                    ) {
                        if board.goals.isEmpty {
                            EmptyStateButton(
                                title: "Setze deine Ziele",
                                exercise: .goals
                            ) {
                                viewModel.startExercise(.goals)
                                showingExercisePicker = true
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 15) {
                                ForEach(board.goals) { goal in
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack {
                                            Text(goal.title)
                                                .font(.headline)
                                            Spacer()
                                            Text(goal.category.rawValue)
                                                .font(.caption)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.orange.opacity(0.2))
                                                .cornerRadius(8)
                                        }
                                        if !goal.description.isEmpty {
                                            Text(goal.description)
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                        if let date = goal.targetDate {
                                            Text("Zieldatum: \(date.formatted(.dateTime.day().month().year()))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding()
                                    .background(Color(.systemBackground))
                                    .cornerRadius(10)
                                }
                                
                                Button(action: {
                                    showingAddGoal = true
                                }) {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                        Text("Ziel hinzufügen")
                                    }
                                }
                                .padding()
                            }
                        }
                    }
                    
                    // Lifestyle Vision Section
                    VisionBoardSection(
                        title: "Traumlebensstil",
                        systemImage: "sun.max.fill",
                        color: .yellow
                    ) {
                        if board.lifestyleVision.isEmpty {
                            EmptyStateButton(
                                title: "Visualisiere deinen Lebensstil",
                                exercise: .lifestyle
                            ) {
                                viewModel.startExercise(.lifestyle)
                                showingExercisePicker = true
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 15) {
                                if !board.lifestyleVision.dailyRoutine.isEmpty {
                                    VisionSection(title: "Tagesablauf", text: board.lifestyleVision.dailyRoutine)
                                }
                                if !board.lifestyleVision.livingEnvironment.isEmpty {
                                    VisionSection(title: "Wohnumgebung", text: board.lifestyleVision.livingEnvironment)
                                }
                                if !board.lifestyleVision.workLife.isEmpty {
                                    VisionSection(title: "Arbeitsleben", text: board.lifestyleVision.workLife)
                                }
                                if !board.lifestyleVision.relationships.isEmpty {
                                    VisionSection(title: "Beziehungen", text: board.lifestyleVision.relationships)
                                }
                                if !board.lifestyleVision.hobbies.isEmpty {
                                    VisionSection(title: "Hobbys & Freizeit", text: board.lifestyleVision.hobbies)
                                }
                                if !board.lifestyleVision.health.isEmpty {
                                    VisionSection(title: "Gesundheit & Wohlbefinden", text: board.lifestyleVision.health)
                                }
                                
                                Button(action: {
                                    showingEditLifestyle = true
                                }) {
                                    HStack {
                                        Image(systemName: "pencil.circle.fill")
                                        Text("Bearbeiten")
                                    }
                                }
                                .padding()
                            }
                        }
                    }
                    
                    // Desired Personality Section
                    VisionBoardSection(
                        title: "Ideales Selbst",
                        systemImage: "person.fill",
                        color: .blue
                    ) {
                        if board.desiredPersonality.isEmpty {
                            EmptyStateButton(
                                title: "Definiere dein ideales Selbst",
                                exercise: .personality
                            ) {
                                viewModel.startExercise(.personality)
                                showingExercisePicker = true
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 15) {
                                if !board.desiredPersonality.traits.isEmpty {
                                    VisionSection(title: "Charaktereigenschaften", text: board.desiredPersonality.traits)
                                }
                                if !board.desiredPersonality.mindset.isEmpty {
                                    VisionSection(title: "Denkweise & Einstellung", text: board.desiredPersonality.mindset)
                                }
                                if !board.desiredPersonality.behaviors.isEmpty {
                                    VisionSection(title: "Verhaltensweisen", text: board.desiredPersonality.behaviors)
                                }
                                if !board.desiredPersonality.skills.isEmpty {
                                    VisionSection(title: "Fähigkeiten & Kompetenzen", text: board.desiredPersonality.skills)
                                }
                                if !board.desiredPersonality.habits.isEmpty {
                                    VisionSection(title: "Gewohnheiten", text: board.desiredPersonality.habits)
                                }
                                if !board.desiredPersonality.growth.isEmpty {
                                    VisionSection(title: "Persönliche Entwicklung", text: board.desiredPersonality.growth)
                                }
                                
                                Button(action: {
                                    showingEditPersonality = true
                                }) {
                                    HStack {
                                        Image(systemName: "pencil.circle.fill")
                                        Text("Bearbeiten")
                                    }
                                }
                                .padding()
                            }
                        }
                    }
                } else {
                    Button(action: {
                        viewModel.createNewVisionBoard()
                    }) {
                        Text("Vision Board erstellen")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.purple)
                            .cornerRadius(10)
                    }
                    .padding()
                }
            }
            .padding()
        }
        .navigationTitle("Vision Board")
        .sheet(isPresented: $showingExercisePicker) {
            if let exercise = viewModel.currentExercise {
                NavigationView {
                    GuidedExerciseView(viewModel: viewModel, exercise: exercise)
                }
            }
        }
        .sheet(isPresented: $showingAddValue) {
            AddValueView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingAddGoal) {
            AddGoalView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingEditLifestyle) {
            EditLifestyleVisionView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingEditPersonality) {
            EditDesiredPersonalityView(viewModel: viewModel)
        }
    }
}

// MARK: - Supporting Views

struct ProgressOverviewCard: View {
    let progress: Double
    
    var body: some View {
        VStack(spacing: 15) {
            Text("Vision Board Fortschritt")
                .font(.headline)
            
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: .purple))
            
            Text("\(Int(progress * 100))% Vollständig")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
}

struct VisionBoardSection<Content: View>: View {
    let title: String
    let systemImage: String
    let color: Color
    let content: Content
    
    init(
        title: String,
        systemImage: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
                Spacer()
            }
            
            content
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
}

struct EmptyStateButton: View {
    let title: String
    let exercise: VisionBoardViewModel.GuidedExercise
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct VisionSection: View {
    let title: String
    let text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(text)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground))
                .cornerRadius(8)
        }
    }
}

#Preview {
    NavigationView {
        VisionBoardView(viewModel: VisionBoardViewModel())
    }
} 