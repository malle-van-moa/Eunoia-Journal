import SwiftUI

struct VisionBoardView: View {
    @ObservedObject var viewModel: VisionBoardViewModel
    @State private var showingExercisePicker = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Progress Overview
                ProgressOverviewCard(progress: viewModel.completionProgress)
                
                // Vision Board Sections
                if let board = viewModel.visionBoard {
                    // Personal Values Section
                    VisionBoardSection(
                        title: "Personal Values",
                        systemImage: "heart.fill",
                        color: .red
                    ) {
                        if board.personalValues.isEmpty {
                            EmptyStateButton(
                                title: "Define Your Values",
                                exercise: .values
                            ) {
                                viewModel.startExercise(.values)
                                showingExercisePicker = true
                            }
                        } else {
                            PersonalValuesView(values: board.personalValues)
                        }
                    }
                    
                    // Goals Section
                    VisionBoardSection(
                        title: "Life Goals",
                        systemImage: "target",
                        color: .orange
                    ) {
                        if board.goals.isEmpty {
                            EmptyStateButton(
                                title: "Set Your Goals",
                                exercise: .goals
                            ) {
                                viewModel.startExercise(.goals)
                                showingExercisePicker = true
                            }
                        } else {
                            GoalsView(goals: board.goals)
                        }
                    }
                    
                    // Lifestyle Vision Section
                    VisionBoardSection(
                        title: "Dream Lifestyle",
                        systemImage: "sun.max.fill",
                        color: .yellow
                    ) {
                        if board.lifestyleVision.dailyRoutine.isEmpty {
                            EmptyStateButton(
                                title: "Visualize Your Lifestyle",
                                exercise: .lifestyle
                            ) {
                                viewModel.startExercise(.lifestyle)
                                showingExercisePicker = true
                            }
                        } else {
                            LifestyleVisionView(vision: board.lifestyleVision)
                        }
                    }
                    
                    // Desired Personality Section
                    VisionBoardSection(
                        title: "Ideal Self",
                        systemImage: "person.fill",
                        color: .blue
                    ) {
                        if board.desiredPersonality.corePrinciples.isEmpty {
                            EmptyStateButton(
                                title: "Define Your Ideal Self",
                                exercise: .personality
                            ) {
                                viewModel.startExercise(.personality)
                                showingExercisePicker = true
                            }
                        } else {
                            DesiredPersonalityView(personality: board.desiredPersonality)
                        }
                    }
                } else {
                    Button(action: {
                        viewModel.createNewVisionBoard()
                    }) {
                        Text("Create Your Vision Board")
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
        .sheet(isPresented: $showingExercisePicker, onDismiss: {
            // Reset exercise when sheet is dismissed
            if viewModel.currentExercise == nil {
                showingExercisePicker = false
            }
        }) {
            if let exercise = viewModel.currentExercise {
                NavigationView {
                    GuidedExerciseView(viewModel: viewModel, exercise: exercise)
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct ProgressOverviewCard: View {
    let progress: Double
    
    var body: some View {
        VStack(spacing: 15) {
            Text("Vision Board Progress")
                .font(.headline)
            
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: .purple))
            
            Text("\(Int(progress * 100))% Complete")
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

struct PersonalValuesView: View {
    let values: [PersonalValue]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(values) { value in
                VStack(alignment: .leading) {
                    Text(value.name)
                        .font(.headline)
                    Text(value.description)
                        .foregroundColor(.secondary)
                    HStack {
                        ForEach(0..<5) { index in
                            Image(systemName: index < value.importance ? "star.fill" : "star")
                                .foregroundColor(.yellow)
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(8)
            }
        }
    }
}

struct GoalsView: View {
    let goals: [Goal]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(goals) { goal in
                VStack(alignment: .leading) {
                    HStack {
                        Text(goal.category.rawValue.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(categoryColor(for: goal.category).opacity(0.2))
                            .cornerRadius(8)
                        Spacer()
                        if let date = goal.targetDate {
                            Text(date, style: .date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Text(goal.title)
                        .font(.headline)
                    Text(goal.description)
                        .foregroundColor(.secondary)
                    
                    if !goal.milestones.isEmpty {
                        Text("Milestones")
                            .font(.subheadline)
                            .padding(.top, 5)
                        
                        ForEach(goal.milestones) { milestone in
                            HStack {
                                Image(systemName: milestone.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(milestone.isCompleted ? .green : .gray)
                                Text(milestone.description)
                                    .strikethrough(milestone.isCompleted)
                                Spacer()
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(8)
            }
        }
    }
    
    private func categoryColor(for category: Goal.Category) -> Color {
        switch category {
        case .health: return .green
        case .career: return .blue
        case .relationships: return .pink
        case .personal: return .purple
        case .financial: return .orange
        case .spiritual: return .yellow
        }
    }
}

struct LifestyleVisionView: View {
    let vision: LifestyleVision
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            VisionSection(title: "Daily Routine", text: vision.dailyRoutine)
            VisionSection(title: "Living Environment", text: vision.livingEnvironment)
            VisionSection(title: "Work Style", text: vision.workStyle)
            
            Text("Leisure Activities")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            FlowLayout(items: vision.leisureActivities) { activity in
                Text(activity)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(15)
            }
            
            VisionSection(title: "Relationships", text: vision.relationships)
        }
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
        }
    }
}

struct FlowLayout<T: Hashable, Content: View>: View {
    let items: [T]
    let content: (T) -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                content(item)
            }
        }
    }
}

struct DesiredPersonalityView: View {
    let personality: DesiredPersonality
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            PersonalitySection(title: "Core Principles", items: personality.corePrinciples)
            PersonalitySection(title: "Strengths", items: personality.strengths)
            PersonalitySection(title: "Areas of Growth", items: personality.areasOfGrowth)
            PersonalitySection(title: "Habits", items: personality.habits)
        }
    }
}

struct PersonalitySection: View {
    let title: String
    let items: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            ForEach(items, id: \.self) { item in
                Text("• \(item)")
            }
        }
    }
}

#Preview {
    NavigationView {
        VisionBoardView(viewModel: VisionBoardViewModel())
    }
} 