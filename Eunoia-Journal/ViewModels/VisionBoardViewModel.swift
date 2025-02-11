import Foundation
import Combine
import FirebaseAuth

class VisionBoardViewModel: ObservableObject {
    @Published var visionBoard: VisionBoard?
    @Published var isLoading = false
    @Published var error: Error?
    @Published var currentExercise: GuidedExercise?
    @Published var exerciseProgress: Double = 0.0
    
    private let visionBoardService = VisionBoardService.shared
    private var cancellables = Set<AnyCancellable>()
    
    enum GuidedExercise: String, CaseIterable {
        case values = "Persönliche Werte"
        case goals = "Lebensziele"
        case lifestyle = "Traumlebensstil"
        case personality = "Ideales Selbst"
        
        var description: String {
            switch self {
            case .values:
                return "Entdecke und definiere deine Kernwerte"
            case .goals:
                return "Setze bedeutungsvolle langfristige Ziele"
            case .lifestyle:
                return "Visualisiere deinen idealen Lebensstil"
            case .personality:
                return "Definiere die Person, die du werden möchtest"
            }
        }
    }
    
    init() {
        setupSubscriptions()
    }
    
    private func setupSubscriptions() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        // Subscribe to real-time vision board updates
        visionBoardService.observeVisionBoard(for: userId)
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
        
        Task {
            do {
                let board = try await visionBoardService.fetchVisionBoard(for: userId)
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
                workLife: "",
                relationships: "",
                hobbies: "",
                health: ""
            ),
            desiredPersonality: DesiredPersonality(
                traits: "",
                mindset: "",
                behaviors: "",
                skills: "",
                habits: "",
                growth: ""
            ),
            syncStatus: .pendingUpload
        )
        
        visionBoard = newBoard
        saveVisionBoard(newBoard)
    }
    
    func saveVisionBoard(_ board: VisionBoard) {
        Task {
            do {
                try await visionBoardService.saveVisionBoard(board)
                DispatchQueue.main.async {
                    self.visionBoard = board
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = error
                }
            }
        }
    }
    
    // MARK: - Section Updates
    
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
    
    // MARK: - Guided Exercises
    
    func startExercise(_ exercise: GuidedExercise) {
        currentExercise = exercise
        exerciseProgress = 0.0
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
        if !board.lifestyleVision.isEmpty { progress += 1.0 }
        if !board.desiredPersonality.isEmpty { progress += 1.0 }
        
        return progress / totalSteps
    }
    
    var errorMessage: String {
        error?.localizedDescription ?? ""
    }
} 