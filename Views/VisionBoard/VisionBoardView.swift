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
        .sheet(isPresented: $showingExercisePicker, onDismiss: {
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