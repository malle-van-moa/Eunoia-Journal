import Foundation
import Combine
import FirebaseAuth

class VisionBoardViewModel: ObservableObject {
    @Published var visionBoard: VisionBoard?
    @Published var isLoading = false
    @Published var error: Error?
    @Published var currentExercise: GuidedExercise?
    @Published var exerciseProgress: Double = 0.0
    
    private let firebaseService = FirebaseService.shared
    private let coreDataManager = CoreDataManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    enum GuidedExercise: String, CaseIterable {
        case values = "Personal Values"
        case goals = "Life Goals"
        case lifestyle = "Dream Lifestyle"
        case personality = "Ideal Self"
        
        var description: String {
            switch self {
            case .values:
                return "Discover and define your core personal values"
            case .goals:
                return "Set meaningful long-term goals for different life areas"
            case .lifestyle:
                return "Visualize your ideal daily life and environment"
            case .personality:
                return "Define the person you aspire to become"
            }
        }
    }
    
    init() {
        setupSubscriptions()
    }
    
    private func setupSubscriptions() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        // Subscribe to real-time vision board updates
        firebaseService.observeVisionBoard(for: userId)
            .receive(on: DispatchQueue.main)
            .sink { completion in
                if case .failure(let error) = completion {
                    self.error = error
                }
            } receiveValue: { [weak self] visionBoard in
                self?.visionBoard = visionBoard
            }
            .store(in: &cancellables)
    }
    
    func loadVisionBoard() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        
        // First load from Core Data
        visionBoard = coreDataManager.fetchVisionBoard(for: userId)
        
        // Then fetch from Firebase if online
        Task {
            do {
                let board = try await firebaseService.fetchVisionBoard(for: userId)
                DispatchQueue.main.async {
                    self.visionBoard = board
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = error
                    self.isLoading = false
                }
            }
        }
    }
    
    func createNewVisionBoard() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let newBoard = VisionBoard(
            id: UUID().uuidString,
            userId: userId,
            lastModified: Date(),
            personalValues: [],
            goals: [],
            lifestyleVision: LifestyleVision(
                dailyRoutine: "",
                livingEnvironment: "",
                workStyle: "",
                leisureActivities: [],
                relationships: ""
            ),
            desiredPersonality: DesiredPersonality(
                corePrinciples: [],
                strengths: [],
                areasOfGrowth: [],
                habits: []
            ),
            syncStatus: .pendingUpload
        )
        
        visionBoard = newBoard
    }
    
    func saveVisionBoard(_ board: VisionBoard) {
        // Save to Core Data first
        coreDataManager.saveVisionBoard(board)
        
        // If online, sync with Firebase
        if NetworkMonitor.shared.isConnected {
            Task {
                do {
                    try await firebaseService.saveVisionBoard(board)
                } catch {
                    DispatchQueue.main.async {
                        self.error = error
                    }
                }
            }
        }
        
        // Update local property
        visionBoard = board
    }
    
    // MARK: - Guided Exercises
    
    func startExercise(_ exercise: GuidedExercise) {
        currentExercise = exercise
        exerciseProgress = 0.0
    }
    
    func addPersonalValue(_ value: PersonalValue) {
        guard var board = visionBoard else { return }
        board.personalValues.append(value)
        board.lastModified = Date()
        board.syncStatus = .pendingUpload
        saveVisionBoard(board)
    }
    
    func addGoal(_ goal: Goal) {
        guard var board = visionBoard else { return }
        board.goals.append(goal)
        board.lastModified = Date()
        board.syncStatus = .pendingUpload
        saveVisionBoard(board)
    }
    
    func updateLifestyleVision(_ vision: LifestyleVision) {
        guard var board = visionBoard else { return }
        board.lifestyleVision = vision
        board.lastModified = Date()
        board.syncStatus = .pendingUpload
        saveVisionBoard(board)
    }
    
    func updateDesiredPersonality(_ personality: DesiredPersonality) {
        guard var board = visionBoard else { return }
        board.desiredPersonality = personality
        board.lastModified = Date()
        board.syncStatus = .pendingUpload
        saveVisionBoard(board)
    }
    
    func completeExercise() {
        currentExercise = nil
        exerciseProgress = 1.0
    }
    
    // MARK: - Progress Tracking
    
    var completionProgress: Double {
        guard let board = visionBoard else { return 0.0 }
        
        var progress = 0.0
        let totalSteps = 4.0 // Total number of main sections
        
        if !board.personalValues.isEmpty { progress += 1.0 }
        if !board.goals.isEmpty { progress += 1.0 }
        if !board.lifestyleVision.dailyRoutine.isEmpty { progress += 1.0 }
        if !board.desiredPersonality.corePrinciples.isEmpty { progress += 1.0 }
        
        return progress / totalSteps
    }
    
    var errorMessage: String {
        error?.localizedDescription ?? ""
    }
} 