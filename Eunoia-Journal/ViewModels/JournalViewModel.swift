import Foundation
import Combine
import FirebaseAuth

class JournalViewModel: ObservableObject {
    @Published var journalEntries: [JournalEntry] = []
    @Published var isLoading = false
    @Published var error: Error?
    @Published var currentEntry: JournalEntry?
    @Published var aiSuggestions: [String] = []
    @Published var learningNugget: LearningNugget?
    
    private let firebaseService = FirebaseService.shared
    private let coreDataManager = CoreDataManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupSubscriptions()
    }
    
    private func setupSubscriptions() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        // Subscribe to real-time journal entry updates
        firebaseService.observeJournalEntries(for: userId)
            .receive(on: DispatchQueue.main)
            .sink { completion in
                if case .failure(let error) = completion {
                    self.error = error
                }
            } receiveValue: { [weak self] entries in
                self?.journalEntries = entries.sorted(by: { $0.date > $1.date })
            }
            .store(in: &cancellables)
    }
    
    func loadJournalEntries() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        
        // First load from Core Data
        journalEntries = coreDataManager.fetchJournalEntries(for: userId)
        
        // Then fetch from Firebase if online
        Task {
            do {
                let entries = try await firebaseService.fetchJournalEntries(for: userId)
                DispatchQueue.main.async {
                    self.journalEntries = entries.sorted(by: { $0.date > $1.date })
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
    
    func createNewEntry() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let newEntry = JournalEntry(
            id: UUID().uuidString,
            userId: userId,
            date: Date(),
            gratitude: "",
            highlight: "",
            learning: "",
            learningNugget: nil,
            lastModified: Date(),
            syncStatus: .pendingUpload
        )
        
        currentEntry = newEntry
    }
    
    func saveEntry(_ entry: JournalEntry) {
        // Save to Core Data first
        coreDataManager.saveJournalEntry(entry)
        
        // If online, sync with Firebase
        if NetworkMonitor.shared.isConnected {
            Task {
                do {
                    try await firebaseService.saveJournalEntry(entry)
                } catch {
                    DispatchQueue.main.async {
                        self.error = error
                    }
                }
            }
        }
        
        // Update local array
        if let index = journalEntries.firstIndex(where: { $0.id == entry.id }) {
            journalEntries[index] = entry
        } else {
            journalEntries.insert(entry, at: 0)
        }
    }
    
    func deleteEntry(_ entry: JournalEntry) {
        // Remove from local array
        journalEntries.removeAll { $0.id == entry.id }
        
        // Delete from Firebase if online
        if NetworkMonitor.shared.isConnected {
            Task {
                do {
                    if let id = entry.id {
                        try await firebaseService.deleteJournalEntry(withId: id)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.error = error
                    }
                }
            }
        }
    }
    
    // MARK: - AI Features
    
    func generateReflectionSuggestions(for field: String) {
        // TODO: Implement AI suggestion generation
        // This would integrate with OpenAI or another AI service
        aiSuggestions = [
            "Think about a moment that made you smile today...",
            "Consider a challenge you overcame...",
            "Reflect on something new you discovered..."
        ]
    }
    
    func generateLearningNugget(for category: LearningNugget.Category) {
        // TODO: Implement AI learning nugget generation
        // This would integrate with OpenAI or another AI service
        learningNugget = LearningNugget(
            category: category,
            content: "Did you know? The average person spends 6 months of their lifetime waiting for red lights to turn green.",
            isAddedToJournal: false
        )
    }
    
    func addLearningNuggetToEntry() {
        guard var entry = currentEntry, let nugget = learningNugget else { return }
        entry.learningNugget = nugget
        currentEntry = entry
    }
    
    // MARK: - Search and Filtering
    
    func searchEntries(query: String) -> [JournalEntry] {
        guard !query.isEmpty else { return journalEntries }
        
        return journalEntries.filter { entry in
            entry.gratitude.localizedCaseInsensitiveContains(query) ||
            entry.highlight.localizedCaseInsensitiveContains(query) ||
            entry.learning.localizedCaseInsensitiveContains(query)
        }
    }
    
    func entriesByDate(date: Date) -> [JournalEntry] {
        let calendar = Calendar.current
        return journalEntries.filter { entry in
            calendar.isDate(entry.date, inSameDayAs: date)
        }
    }
    
    // MARK: - Streaks and Gamification
    
    func calculateCurrentStreak() -> Int {
        var streak = 0
        let calendar = Calendar.current
        var currentDate = calendar.startOfDay(for: Date())
        
        while true {
            let entriesForDate = entriesByDate(date: currentDate)
            if entriesForDate.isEmpty {
                break
            }
            streak += 1
            currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate) ?? Date()
        }
        
        return streak
    }
    
    var errorMessage: String {
        error?.localizedDescription ?? ""
    }
} 