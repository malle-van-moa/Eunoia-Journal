import Foundation
import Combine
import FirebaseAuth
import JournalingSuggestions
import OSLog
import UIKit

@available(iOS 17.0, *)
class JournalViewModel: ObservableObject {
    @Published var journalEntries: [JournalEntry] = []
    @Published var isLoading = false
    @Published var error: Error?
    @Published var currentEntry: JournalEntry?
    @Published var aiSuggestions: [String] = []
    @Published var learningNugget: LearningNugget?
    
    private let firebaseService = FirebaseService.shared
    private let coreDataManager = CoreDataManager.shared
    private let learningNuggetService = LearningNuggetService.shared
    private let journalService = JournalService.shared
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Eunoia", category: "JournalViewModel")
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        loadJournalEntries() // Load entries immediately
        setupAuthSubscription()
    }
    
    private func setupAuthSubscription() {
        // Listen for auth state changes
        Auth.auth().addStateDidChangeListener { [weak self] (_, user) in
            if let userId = user?.uid {
                self?.setupSubscriptions(for: userId)
                self?.loadJournalEntries()
            }
        }
    }
    
    private func setupSubscriptions(for userId: String) {
        // Cancel existing subscriptions
        cancellables.removeAll()
        
        // Subscribe to real-time journal entry updates
        firebaseService.observeJournalEntries(for: userId)
            .receive(on: DispatchQueue.main)
            .sink { completion in
                if case .failure(let error) = completion {
                    self.error = error
                }
            } receiveValue: { [weak self] entries in
                self?.handleNewEntries(entries)
            }
            .store(in: &cancellables)
            
        // Subscribe to network status changes
        NetworkMonitor.shared.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                if isConnected {
                    self?.syncPendingEntries()
                }
            }
            .store(in: &cancellables)
    }
    
    private func handleNewEntries(_ entries: [JournalEntry]) {
        // Sort entries by date
        let sortedEntries = entries.sorted(by: { $0.date > $1.date })
        
        // Update Core Data, preserving sync status for pending entries
        for entry in sortedEntries {
            if let existingEntry = journalEntries.first(where: { $0.id == entry.id }),
               existingEntry.syncStatus == .pendingUpload {
                var updatedEntry = entry
                updatedEntry.syncStatus = .pendingUpload
                coreDataManager.saveJournalEntry(updatedEntry)
            } else {
                coreDataManager.saveJournalEntry(entry)
            }
        }
        
        // Update UI
        DispatchQueue.main.async {
            self.journalEntries = sortedEntries
        }
    }
    
    private func syncPendingEntries() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        // Get entries that need syncing
        let pendingEntries = coreDataManager.fetchPendingEntries(for: userId)
        
        for entry in pendingEntries {
            Task {
                do {
                    try await firebaseService.saveJournalEntry(entry)
                    
                    DispatchQueue.main.async {
                        // Update local entry status
                        if let index = self.journalEntries.firstIndex(where: { $0.id == entry.id }) {
                            var updatedEntry = entry
                            updatedEntry.syncStatus = .synced
                            self.journalEntries[index] = updatedEntry
                            self.coreDataManager.saveJournalEntry(updatedEntry)
                        }
                    }
                } catch {
                    print("Failed to sync entry: \(error.localizedDescription)")
                    // Schedule retry after delay
                    try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                    try? await firebaseService.saveJournalEntry(entry)
                }
            }
        }
    }
    
    func loadJournalEntries() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        
        // First load from Core Data
        let localEntries = coreDataManager.fetchJournalEntries(for: userId)
        DispatchQueue.main.async {
            self.journalEntries = localEntries.sorted(by: { $0.date > $1.date })
        }
        
        // Then fetch from Firebase if online
        if NetworkMonitor.shared.isConnected {
            Task {
                do {
                    let entries = try await firebaseService.fetchJournalEntries(for: userId)
                    DispatchQueue.main.async {
                        self.handleNewEntries(entries)
                        self.isLoading = false
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.error = error
                        self.isLoading = false
                    }
                }
            }
        } else {
            isLoading = false
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
        var entryToSave = entry
        
        // Set sync status based on network availability
        entryToSave.syncStatus = NetworkMonitor.shared.isConnected ? .synced : .pendingUpload
        
        // Save to Core Data first
        coreDataManager.saveJournalEntry(entryToSave)
        
        // Update local array immediately
        DispatchQueue.main.async {
            if let index = self.journalEntries.firstIndex(where: { $0.id == entryToSave.id }) {
                self.journalEntries[index] = entryToSave
            } else {
                self.journalEntries.insert(entryToSave, at: 0)
            }
        }
        
        // If online, sync with Firebase
        if NetworkMonitor.shared.isConnected {
            Task {
                do {
                    try await firebaseService.saveJournalEntry(entryToSave)
                } catch {
                    DispatchQueue.main.async {
                        self.error = error
                        // Mark for retry and update UI
                        entryToSave.syncStatus = .pendingUpload
                        self.coreDataManager.saveJournalEntry(entryToSave)
                        if let index = self.journalEntries.firstIndex(where: { $0.id == entryToSave.id }) {
                            self.journalEntries[index] = entryToSave
                        }
                    }
                    
                    // Schedule retry after delay
                    try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                    if entryToSave.syncStatus == .pendingUpload {
                        try? await firebaseService.saveJournalEntry(entryToSave)
                    }
                }
            }
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
        Task {
            do {
                let nugget = try await learningNuggetService.generateLearningNugget(for: category)
                DispatchQueue.main.async {
                    self.learningNugget = nugget
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = error
                }
            }
        }
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
    
    @available(iOS 17.2, *)
    @MainActor
    func createEntryFromSuggestion(_ suggestion: JournalingSuggestion) async {
        do {
            isLoading = true
            _ = try await journalService.createEntryFromSuggestion(suggestion)
            loadJournalEntries() // Lade die Einträge neu nach dem Erstellen
        } catch {
            logger.error("Fehler beim Erstellen des Eintrags: \(error.localizedDescription)")
            self.error = error
        }
        isLoading = false
    }
    
    // MARK: - Image Handling
    
    func saveEntryWithImages(_ entry: JournalEntry, images: [UIImage]) async throws -> JournalEntry {
        // Wenn der Eintrag bereits Bilder hat, lösche diese zuerst
        if let existingUrls = entry.imageURLs {
            try await journalService.deleteImages(urls: existingUrls)
        }
        
        // Speichere den Eintrag mit den neuen Bildern
        return try await journalService.saveJournalEntryWithImages(entry, images: images)
    }
    
    func deleteEntryWithImages(_ entry: JournalEntry) async throws {
        // Lösche zuerst die Bilder, falls vorhanden
        if let imageUrls = entry.imageURLs {
            try await journalService.deleteImages(urls: imageUrls)
        }
        
        // Dann lösche den Eintrag
        if let id = entry.id {
            try await journalService.deleteJournalEntry(withId: id)
        }
    }
} 