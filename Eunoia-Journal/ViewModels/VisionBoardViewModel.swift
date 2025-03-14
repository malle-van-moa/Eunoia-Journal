import Foundation
import Combine
import FirebaseAuth
import UIKit

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
        case valueCompass = "Wertekompass"
        
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
            case .valueCompass:
                return "Erstelle deinen persönlichen Wertekompass"
            }
        }
    }
    
    init() {
        setupSubscriptions()
        setupNotificationObservers()
    }
    
    private func setupNotificationObservers() {
        // Beobachte App-Lebenszyklus-Benachrichtigungen
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                // App geht in den Hintergrund, entferne Subscriptions
                self?.cancellables.removeAll()
                print("🔄 VisionBoardViewModel: Firestore-Subscriptions entfernt")
            }
            .store(in: &cancellables)
        
        // Beobachte die RefreshFirestoreSubscriptions-Benachrichtigung
        NotificationCenter.default.publisher(for: NSNotification.Name("RefreshFirestoreSubscriptions"))
            .sink { [weak self] _ in
                guard let self = self else { return }
                
                // Stelle sicher, dass wir einen authentifizierten Benutzer haben
                if let userId = Auth.auth().currentUser?.uid {
                    print("🔄 VisionBoardViewModel: Baue Firestore-Subscriptions neu auf")
                    self.setupSubscriptions()
                    self.loadVisionBoard()
                }
            }
            .store(in: &cancellables)
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
            id: nil,
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
            syncStatus: .pendingUpload,
            valueCompass: nil
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
    
    func updateValueCompass(_ values: [RadarChartEntry]) {
        guard var board = visionBoard else { return }
        let compass = ValueCompass(values: values)
        board.valueCompass = compass
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
        let totalSteps = 5.0 // Total number of main sections including valueCompass
        
        if !board.personalValues.isEmpty { progress += 1.0 }
        if !board.goals.isEmpty { progress += 1.0 }
        if !board.lifestyleVision.isEmpty { progress += 1.0 }
        if !board.desiredPersonality.isEmpty { progress += 1.0 }
        if board.valueCompass != nil { progress += 1.0 }
        
        return progress / totalSteps
    }
    
    var errorMessage: String {
        error?.localizedDescription ?? ""
    }
} 