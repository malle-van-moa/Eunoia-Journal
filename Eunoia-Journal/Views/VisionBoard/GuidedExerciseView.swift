import SwiftUI

struct GuidedExerciseView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: VisionBoardViewModel
    let exercise: VisionBoardViewModel.GuidedExercise
    
    @State private var currentStep = 0
    @State private var showingConfirmation = false
    
    // Personal Values
    @State private var valueName = ""
    @State private var valueDescription = ""
    @State private var valueImportance = 3
    
    // Goals
    @State private var goalTitle = ""
    @State private var goalDescription = ""
    @State private var goalCategory: Goal.Category = .personal
    @State private var goalDate = Date()
    @State private var milestones: [String] = [""]
    
    // Lifestyle Vision
    @State private var dailyRoutine = ""
    @State private var livingEnvironment = ""
    @State private var workStyle = ""
    @State private var leisureActivities: [String] = [""]
    @State private var relationships = ""
    
    // Desired Personality
    @State private var corePrinciples: [String] = [""]
    @State private var strengths: [String] = [""]
    @State private var areasOfGrowth: [String] = [""]
    @State private var habits: [String] = [""]
    
    var body: some View {
        VStack {
            // Progress Bar
            ProgressView(value: Double(currentStep) / Double(totalSteps - 1))
                .progressViewStyle(LinearProgressViewStyle(tint: .purple))
                .padding()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Exercise Content
                    switch exercise {
                    case .values:
                        PersonalValuesExercise(
                            step: currentStep,
                            name: $valueName,
                            description: $valueDescription,
                            importance: $valueImportance
                        )
                    case .goals:
                        GoalsExercise(
                            step: currentStep,
                            title: $goalTitle,
                            description: $goalDescription,
                            category: $goalCategory,
                            date: $goalDate,
                            milestones: $milestones
                        )
                    case .lifestyle:
                        LifestyleExercise(
                            step: currentStep,
                            dailyRoutine: $dailyRoutine,
                            livingEnvironment: $livingEnvironment,
                            workStyle: $workStyle,
                            leisureActivities: $leisureActivities,
                            relationships: $relationships
                        )
                    case .personality:
                        PersonalityExercise(
                            step: currentStep,
                            corePrinciples: $corePrinciples,
                            strengths: $strengths,
                            areasOfGrowth: $areasOfGrowth,
                            habits: $habits
                        )
                    }
                }
                .padding()
            }
            
            // Navigation Buttons
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation {
                            currentStep -= 1
                        }
                    }
                }
                
                Spacer()
                
                Button(currentStep == totalSteps - 1 ? "Complete" : "Next") {
                    if currentStep == totalSteps - 1 {
                        completeExercise()
                    } else {
                        withAnimation {
                            currentStep += 1
                        }
                    }
                }
                .disabled(!isStepValid)
            }
            .padding()
        }
        .navigationTitle(exercise.rawValue)
        .navigationBarItems(trailing: Button("Cancel") {
            showingConfirmation = true
        })
        .alert("Cancel Exercise?", isPresented: $showingConfirmation) {
            Button("Yes", role: .destructive) {
                viewModel.currentExercise = nil
                dismiss()
            }
            Button("No", role: .cancel) {}
        } message: {
            Text("Your progress will be lost.")
        }
    }
    
    private var totalSteps: Int {
        switch exercise {
        case .values: return 3
        case .goals: return 5
        case .lifestyle: return 5
        case .personality: return 4
        }
    }
    
    private var isStepValid: Bool {
        switch exercise {
        case .values:
            switch currentStep {
            case 0: return !valueName.isEmpty
            case 1: return !valueDescription.isEmpty
            default: return true
            }
        case .goals:
            switch currentStep {
            case 0: return !goalTitle.isEmpty
            case 1: return !goalDescription.isEmpty
            case 2: return true
            case 3: return true
            default: return !milestones.contains("")
            }
        case .lifestyle:
            switch currentStep {
            case 0: return !dailyRoutine.isEmpty
            case 1: return !livingEnvironment.isEmpty
            case 2: return !workStyle.isEmpty
            case 3: return !leisureActivities.contains("")
            default: return !relationships.isEmpty
            }
        case .personality:
            switch currentStep {
            case 0: return !corePrinciples.contains("")
            case 1: return !strengths.contains("")
            case 2: return !areasOfGrowth.contains("")
            default: return !habits.contains("")
            }
        }
    }
    
    private func completeExercise() {
        switch exercise {
        case .values:
            let value = PersonalValue(
                name: valueName,
                description: valueDescription,
                importance: valueImportance
            )
            viewModel.addPersonalValue(value)
            
        case .goals:
            let goal = Goal(
                category: goalCategory,
                title: goalTitle,
                description: goalDescription,
                targetDate: goalDate,
                milestones: milestones.filter { !$0.isEmpty }.map { Milestone(description: $0, isCompleted: false) }
            )
            viewModel.addGoal(goal)
            
        case .lifestyle:
            let vision = LifestyleVision(
                dailyRoutine: dailyRoutine,
                livingEnvironment: livingEnvironment,
                workStyle: workStyle,
                leisureActivities: leisureActivities.filter { !$0.isEmpty },
                relationships: relationships
            )
            viewModel.updateLifestyleVision(vision)
            
        case .personality:
            let personality = DesiredPersonality(
                corePrinciples: corePrinciples.filter { !$0.isEmpty },
                strengths: strengths.filter { !$0.isEmpty },
                areasOfGrowth: areasOfGrowth.filter { !$0.isEmpty },
                habits: habits.filter { !$0.isEmpty }
            )
            viewModel.updateDesiredPersonality(personality)
        }
        
        viewModel.completeExercise()
        dismiss()
    }
}

// MARK: - Exercise Views

struct PersonalValuesExercise: View {
    let step: Int
    @Binding var name: String
    @Binding var description: String
    @Binding var importance: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch step {
            case 0:
                ExercisePrompt(
                    title: "Name Your Value",
                    description: "What personal value would you like to define?",
                    example: "Example: Authenticity, Growth, Compassion"
                )
                TextField("Value Name", text: $name)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
            case 1:
                ExercisePrompt(
                    title: "Describe Your Value",
                    description: "What does this value mean to you? How does it guide your actions?",
                    example: "Example: Being true to myself in all situations..."
                )
                TextEditor(text: $description)
                    .frame(height: 100)
                    .padding(8)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                
            case 2:
                ExercisePrompt(
                    title: "Rate Importance",
                    description: "How important is this value to you?",
                    example: "1 = Less Important, 5 = Most Important"
                )
                Stepper("Importance: \(importance)", value: $importance, in: 1...5)
                
            default:
                EmptyView()
            }
        }
    }
}

struct GoalsExercise: View {
    let step: Int
    @Binding var title: String
    @Binding var description: String
    @Binding var category: Goal.Category
    @Binding var date: Date
    @Binding var milestones: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch step {
            case 0:
                ExercisePrompt(
                    title: "Name Your Goal",
                    description: "What do you want to achieve?",
                    example: "Example: Run a Marathon"
                )
                TextField("Goal Title", text: $title)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
            case 1:
                ExercisePrompt(
                    title: "Describe Your Goal",
                    description: "Why is this goal important to you?",
                    example: "Example: To improve my health and prove to myself..."
                )
                TextEditor(text: $description)
                    .frame(height: 100)
                    .padding(8)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                
            case 2:
                ExercisePrompt(
                    title: "Choose Category",
                    description: "What area of life does this goal belong to?",
                    example: ""
                )
                Picker("Category", selection: $category) {
                    ForEach(Goal.Category.allCases, id: \.self) { category in
                        Text(category.rawValue.capitalized)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                
            case 3:
                ExercisePrompt(
                    title: "Set Target Date",
                    description: "When do you want to achieve this goal?",
                    example: ""
                )
                DatePicker("Target Date", selection: $date, displayedComponents: .date)
                
            case 4:
                ExercisePrompt(
                    title: "Define Milestones",
                    description: "What are the key steps to achieve this goal?",
                    example: "Example: Sign up for training program"
                )
                DynamicList(items: $milestones)
                
            default:
                EmptyView()
            }
        }
    }
}

struct LifestyleExercise: View {
    let step: Int
    @Binding var dailyRoutine: String
    @Binding var livingEnvironment: String
    @Binding var workStyle: String
    @Binding var leisureActivities: [String]
    @Binding var relationships: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch step {
            case 0:
                ExercisePrompt(
                    title: "Daily Routine",
                    description: "Describe your ideal daily routine",
                    example: "Example: Wake up early, meditate..."
                )
                TextEditor(text: $dailyRoutine)
                    .frame(height: 100)
                    .padding(8)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                
            case 1:
                ExercisePrompt(
                    title: "Living Environment",
                    description: "Describe your ideal living space and location",
                    example: "Example: Modern apartment with ocean view..."
                )
                TextEditor(text: $livingEnvironment)
                    .frame(height: 100)
                    .padding(8)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                
            case 2:
                ExercisePrompt(
                    title: "Work Style",
                    description: "How do you want to work?",
                    example: "Example: Remote work with flexible hours..."
                )
                TextEditor(text: $workStyle)
                    .frame(height: 100)
                    .padding(8)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                
            case 3:
                ExercisePrompt(
                    title: "Leisure Activities",
                    description: "What activities bring you joy?",
                    example: "Example: Hiking, Photography"
                )
                DynamicList(items: $leisureActivities)
                
            case 4:
                ExercisePrompt(
                    title: "Relationships",
                    description: "Describe your ideal relationships",
                    example: "Example: Deep friendships with like-minded people..."
                )
                TextEditor(text: $relationships)
                    .frame(height: 100)
                    .padding(8)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                
            default:
                EmptyView()
            }
        }
    }
}

struct PersonalityExercise: View {
    let step: Int
    @Binding var corePrinciples: [String]
    @Binding var strengths: [String]
    @Binding var areasOfGrowth: [String]
    @Binding var habits: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch step {
            case 0:
                ExercisePrompt(
                    title: "Core Principles",
                    description: "What principles do you want to live by?",
                    example: "Example: Always be honest"
                )
                DynamicList(items: $corePrinciples)
                
            case 1:
                ExercisePrompt(
                    title: "Strengths",
                    description: "What strengths do you want to develop?",
                    example: "Example: Leadership"
                )
                DynamicList(items: $strengths)
                
            case 2:
                ExercisePrompt(
                    title: "Areas of Growth",
                    description: "What areas would you like to improve?",
                    example: "Example: Public speaking"
                )
                DynamicList(items: $areasOfGrowth)
                
            case 3:
                ExercisePrompt(
                    title: "Habits",
                    description: "What habits will support your growth?",
                    example: "Example: Daily meditation"
                )
                DynamicList(items: $habits)
                
            default:
                EmptyView()
            }
        }
    }
}

// MARK: - Supporting Views

struct ExercisePrompt: View {
    let title: String
    let description: String
    let example: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            
            Text(description)
                .foregroundColor(.secondary)
            
            if !example.isEmpty {
                Text(example)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }
}

struct DynamicList: View {
    @Binding var items: [String]
    
    var body: some View {
        VStack {
            ForEach(items.indices, id: \.self) { index in
                HStack {
                    TextField("Enter item", text: $items[index])
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    if items.count > 1 {
                        Button(action: {
                            items.remove(at: index)
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            
            Button(action: {
                items.append("")
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Item")
                }
            }
            .foregroundColor(.blue)
        }
    }
}

struct DynamicInputField: View {
    let title: String
    @Binding var subject: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.headline)
            ZStack(alignment: .leading) {
                if subject.isEmpty {
                    Text("Enter your text here...")
                        .foregroundColor(.gray)
                        .padding(.horizontal, 4)
                }
                TextField("", text: $subject)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
        }
    }
}

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        overlay(
            ZStack(alignment: alignment) {
                if shouldShow {
                    placeholder()
                }
            }
        )
    }
}

#Preview {
    NavigationView {
        GuidedExerciseView(
            viewModel: VisionBoardViewModel(),
            exercise: .values
        )
    }
} 