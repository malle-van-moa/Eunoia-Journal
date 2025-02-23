#if canImport(JournalingSuggestions)
import JournalingSuggestions
#endif
import Foundation
import Combine
import FirebaseAuth
import OSLog
import UIKit
import CoreData
import SwiftUI

@available(iOS 17.0, *)
class JournalViewModel: ObservableObject {
    @Published var journalEntries: [JournalEntry] = []
    @Published var isLoading = false
    @Published var error: Error?
    @Published var currentEntry: JournalEntry?
    @Published var aiSuggestions: [String] = []
    @Published var learningNugget: LearningNugget?
    @Published var currentLearningText: String = ""
    
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
            guard let self = self else { return }
            
            // Ensure we're on the main thread for UI updates
            DispatchQueue.main.async {
                if let userId = user?.uid {
                    self.setupSubscriptions(for: userId)
                    self.loadJournalEntries()
                } else {
                    // Clear subscriptions when user is not authenticated
                    self.cancellables.removeAll()
                    self.journalEntries = []
                }
            }
        }
    }
    
    private func setupSubscriptions(for userId: String) {
        // Cancel existing subscriptions
        cancellables.removeAll()
        
        // Subscribe to real-time journal entry updates with retry logic
        firebaseService.observeJournalEntries(for: userId)
            .retry(3) // Retry up to 3 times on failure
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                guard let self = self else { return }
                if case .failure(let error) = completion {
                    self.logger.error("Failed to observe journal entries: \(error.localizedDescription)")
                    self.error = error
                }
            } receiveValue: { [weak self] entries in
                guard let self = self else { return }
                self.journalEntries = entries
            }
            .store(in: &cancellables)
            
        // Subscribe to network status changes
        NetworkMonitor.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                if NetworkMonitor.shared.isConnected {
                    Task {
                        do {
                            try await self?.syncPendingEntries()
                        } catch {
                            self?.logger.error("Failed to sync pending entries: \(error.localizedDescription)")
                            self?.error = error
                        }
                    }
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
                do {
                    try coreDataManager.saveJournalEntry(updatedEntry)
                } catch {
                    logger.error("Error saving updated entry: \(error)")
                    self.error = error
                }
            } else {
                do {
                    try coreDataManager.saveJournalEntry(entry)
                } catch {
                    logger.error("Error saving new entry: \(error)")
                    self.error = error
                }
            }
        }
        
        // Update UI
        DispatchQueue.main.async {
            self.journalEntries = sortedEntries
        }
    }
    
    private func syncPendingEntries() async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let pendingEntries = try coreDataManager.fetchPendingEntries(for: userId)
        
        for entry in pendingEntries {
            do {
                try await firebaseService.saveJournalEntry(entry)
                
                // Update local entry status
                if let index = self.journalEntries.firstIndex(where: { $0.id == entry.id }) {
                    var updatedEntry = entry
                    updatedEntry.syncStatus = .synced
                    self.journalEntries[index] = updatedEntry
                    try await coreDataManager.saveJournalEntry(updatedEntry)
                }
            } catch {
                print("Error syncing entry with Firebase: \(error)")
                throw error
            }
        }
    }
    
    private func saveEntryLocally(_ entry: JournalEntry) throws {
        do {
            try coreDataManager.saveJournalEntry(entry)
            
            // Aktualisiere den currentEntry und UI sofort
            DispatchQueue.main.async {
                self.currentEntry = entry
                
                // Aktualisiere den Eintrag in der journalEntries Liste
                if let index = self.journalEntries.firstIndex(where: { $0.id == entry.id }) {
                    self.journalEntries[index] = entry
                }
                
                // Benachrichtige UI über Änderungen
                self.objectWillChange.send()
            }
        } catch {
            print("Error saving entry locally: \(error)")
            throw error
        }
    }
    
    func loadJournalEntries() {
        guard let userId = Auth.auth().currentUser?.uid else {
            self.error = ServiceError.userNotAuthenticated
            return
        }
        
        isLoading = true
        
        Task {
            do {
                // Lade zuerst lokale Einträge mit verbesserter Fehlerbehandlung
                let localEntries: [JournalEntry]
                do {
                    localEntries = try coreDataManager.fetchJournalEntries(for: userId)
                    await MainActor.run {
                        self.journalEntries = localEntries.sorted(by: { $0.date > $1.date })
                    }
                } catch {
                    logger.error("Fehler beim Laden lokaler Einträge: \(error.localizedDescription)")
                    throw error
                }
                
                // Wenn online, synchronisiere mit Firebase
                if NetworkMonitor.shared.isConnected {
                    do {
                        // Implementiere Retry-Logik für Firebase-Synchronisation
                        let maxRetries = 3
                        var retryCount = 0
                        var lastError: Error?
                        
                        while retryCount < maxRetries {
                            do {
                                let firebaseEntries = try await firebaseService.fetchJournalEntries(for: userId)
                                
                                // Merge Einträge mit Konfliktauflösung
                                let mergedEntries = try await mergeEntries(local: localEntries, remote: firebaseEntries)
                                
                                // Speichere merged Einträge in Core Data
                                for entry in mergedEntries {
                                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1s Pause zwischen Speicheroperationen
                                    try coreDataManager.saveJournalEntry(entry)
                                }
                                
                                await MainActor.run {
                                    self.journalEntries = mergedEntries.sorted(by: { $0.date > $1.date })
                                    self.error = nil
                                }
                                break // Erfolgreicher Sync, breche Retry-Schleife ab
                                
                            } catch {
                                lastError = error
                                retryCount += 1
                                if retryCount < maxRetries {
                                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retryCount)) * 1_000_000_000))
                                    continue
                                }
                                throw error
                            }
                        }
                        
                        if let error = lastError {
                            logger.error("Fehler beim Synchronisieren mit Firebase nach \(maxRetries) Versuchen: \(error.localizedDescription)")
                            throw error
                        }
                        
                    } catch {
                        await MainActor.run {
                            self.error = error
                            self.logger.error("Fehler beim Synchronisieren mit Firebase: \(error.localizedDescription)")
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    self.logger.error("Fehler beim Laden der Einträge: \(error.localizedDescription)")
                }
            }
            
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
    
    private func mergeEntries(local: [JournalEntry], remote: [JournalEntry]) async throws -> [JournalEntry] {
        var mergedEntries: [JournalEntry] = []
        var processedIds = Set<String>()
        
        // Verarbeite lokale Einträge
        for localEntry in local {
            guard let id = localEntry.id else { continue }
            
            if let remoteEntry = remote.first(where: { $0.id == id }) {
                // Konfliktauflösung basierend auf Zeitstempel
                if let localTimestamp = localEntry.serverTimestamp?.dateValue(),
                   let remoteTimestamp = remoteEntry.serverTimestamp?.dateValue() {
                    mergedEntries.append(localTimestamp > remoteTimestamp ? localEntry : remoteEntry)
                } else {
                    // Wenn keine Zeitstempel verfügbar, bevorzuge Remote
                    mergedEntries.append(remoteEntry)
                }
            } else {
                // Lokaler Eintrag existiert nicht remote
                if localEntry.syncStatus == .pendingUpload {
                    mergedEntries.append(localEntry)
                }
            }
            processedIds.insert(id)
        }
        
        // Füge neue Remote-Einträge hinzu
        for remoteEntry in remote {
            if let id = remoteEntry.id, !processedIds.contains(id) {
                mergedEntries.append(remoteEntry)
            }
        }
        
        return mergedEntries
    }
    
    @MainActor
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
        currentLearningText = ""
    }
    
    func saveEntry(_ entry: JournalEntry) {
        var entryToSave = entry
        
        // Wenn ein Learning vorhanden ist, aber kein LearningNugget, erstellen wir eines
        if !entry.learning.isEmpty && entry.learningNugget == nil {
            let nugget = LearningNugget(
                userId: entry.userId,
                category: .persönlichesWachstum,
                title: "Lernimpuls",
                content: entry.learning,
                isAddedToJournal: true
            )
            entryToSave.learningNugget = nugget
        }
        
        // Set sync status based on network availability
        entryToSave.syncStatus = NetworkMonitor.shared.isConnected ? .synced : .pendingUpload
        
        // Save to Core Data first
        do {
            try coreDataManager.saveJournalEntry(entryToSave)
            
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
                        print("Error saving entry to Firebase: \(error)")
                    }
                }
            }
        } catch {
            print("Error saving entry to CoreData: \(error)")
        }
    }
    
    func deleteEntry(_ entry: JournalEntry) {
        guard let id = entry.id else { return }
        
        Task {
            do {
                // Lösche zuerst aus Core Data
                try await coreDataManager.deleteJournalEntryAsync(withId: id)
                
                // Aktualisiere die UI im Hauptthread
                await MainActor.run {
                    journalEntries.removeAll { $0.id == id }
                }
                
                // Wenn online, lösche auch aus Firebase
                if NetworkMonitor.shared.isConnected {
                    do {
                        try await firebaseService.deleteJournalEntry(withId: id)
                    } catch {
                        // Logge den Firebase-Fehler, aber wirf ihn nicht
                        logger.error("Fehler beim Löschen in Firebase: \(error.localizedDescription)")
                    }
                }
            } catch {
                // Fehlerbehandlung im Hauptthread
                await MainActor.run {
                    self.error = error
                    self.logger.error("Fehler beim lokalen Löschen: \(error.localizedDescription)")
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
        isLoading = true
        
        Task {
            do {
                let nugget = try await learningNuggetService.generateLearningNugget(for: category)
                await MainActor.run {
                    self.learningNugget = nugget
                    self.isLoading = false
                    // Automatisch das Nugget zum Eintrag hinzufügen
                    self.addLearningNuggetToEntry()
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    self.isLoading = false
                    self.logger.error("Fehler bei der Generierung des Learning Nuggets: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func addLearningNuggetToEntry() {
        guard var entry = currentEntry, let nugget = learningNugget else { return }
        
        // Aktualisiere den Eintrag mit dem Learning Nugget und füge den Content zum Lernfeld hinzu
        entry = JournalEntry(
            id: entry.id,
            userId: entry.userId,
            date: entry.date,
            gratitude: entry.gratitude,
            highlight: entry.highlight,
            learning: nugget.content,
            learningNugget: nugget,
            lastModified: Date(),
            syncStatus: .pendingUpload,
            title: entry.title,
            content: entry.content,
            location: entry.location,
            imageURLs: entry.imageURLs,
            localImagePaths: entry.localImagePaths
        )
        
        // Aktualisiere den currentEntry und UI sofort
        DispatchQueue.main.async {
            self.currentEntry = entry
            
            // Aktualisiere den Eintrag in der journalEntries Liste
            if let index = self.journalEntries.firstIndex(where: { $0.id == entry.id }) {
                self.journalEntries[index] = entry
            }
            
            // Benachrichtige UI über Änderungen
            self.objectWillChange.send()
        }
        
        // Speichere in CoreData
        do {
            try coreDataManager.saveJournalEntry(entry)
            
            // Speichere in Firebase
            Task {
                do {
                    try await journalService.saveJournalEntry(entry)
                } catch {
                    self.logger.error("Error saving entry to Firebase: \(error)")
                    self.error = error
                }
            }
        } catch {
            self.logger.error("Error saving entry to CoreData: \(error)")
            self.error = error
        }
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
    
    #if canImport(JournalingSuggestions)
    @available(iOS 17.2, *)
    @MainActor
    func createEntryFromSuggestion(_ suggestion: JournalingSuggestion) async throws -> JournalEntry {
        isLoading = true
        
        do {
            let entry = try await journalService.createEntryFromSuggestion(suggestion)
            loadJournalEntries() // Lade die Einträge neu nach dem Erstellen
            isLoading = false
            return entry
        } catch {
            logger.error("Fehler beim Erstellen des Eintrags: \(error.localizedDescription)")
            self.error = error
            isLoading = false
            throw error
        }
    }
    #endif
    
    // MARK: - Image Handling
    
    func saveEntryWithImages(_ entry: JournalEntry, images: [UIImage]) async throws -> JournalEntry {
        // Wenn der Eintrag bereits Bilder hat, lösche diese zuerst
        if let existingUrls = entry.imageURLs {
            try await journalService.deleteCloudImages(urls: existingUrls)
        }
        
        // Lösche auch lokale Bilder, falls vorhanden
        if let localPaths = entry.localImagePaths {
            for path in localPaths {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        
        // Speichere den Eintrag mit den neuen Bildern
        let updatedEntry = try await journalService.saveJournalEntryWithImages(entry, images: images)
        
        // Aktualisiere den lokalen Cache
        await MainActor.run {
            if let index = journalEntries.firstIndex(where: { $0.id == updatedEntry.id }) {
                journalEntries[index] = updatedEntry
            }
        }
        
        return updatedEntry
    }
    
    func deleteEntryWithImages(_ entry: JournalEntry) async throws {
        // Lösche zuerst die Bilder, falls vorhanden
        if let imageUrls = entry.imageURLs {
            try await journalService.deleteCloudImages(urls: imageUrls)
        }
        
        // Lösche lokale Bilder
        if let localPaths = entry.localImagePaths {
            for path in localPaths {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        
        // Dann lösche den Eintrag
        if let id = entry.id {
            try await journalService.deleteJournalEntry(withId: id)
            
            // Aktualisiere den lokalen Cache
            await MainActor.run {
                journalEntries.removeAll { $0.id == id }
            }
        }
    }
    
    func updateEntryWithImages(_ entry: JournalEntry, images: [UIImage]) async throws -> JournalEntry {
        return try await saveEntryWithImages(entry, images: images)
    }
    
    func updateCurrentEntry(with nugget: LearningNugget) {
        guard var entry = currentEntry else { return }
        
        entry.learningNugget = nugget
        entry.learning = nugget.content
        entry.lastModified = Date()
        entry.syncStatus = .pendingUpload
        
        currentEntry = entry
        currentLearningText = nugget.content
        
        // Speichere den aktualisierten Eintrag
        saveEntry(entry)
    }
    
    func processOpenAIResponse(_ jsonResponse: String) async {
        logger.debug("Empfangene OpenAI-Antwort: \(jsonResponse)")
        
        guard let data = jsonResponse.data(using: .utf8) else {
            logger.error("Fehler: Konnte JSON-String nicht in Data konvertieren")
            await MainActor.run {
                self.error = NSError(domain: "OpenAIProcessing", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ungültiges Antwortformat"])
            }
            return
        }
        
        do {
            logger.debug("Versuche JSON zu decodieren...")
            let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            logger.debug("JSON erfolgreich decodiert. Erste Choice verfügbar: \(response.choices.first != nil)")
            
            if let (title, content) = response.extractLearningContent() {
                logger.debug("Learning Content erfolgreich extrahiert:")
                logger.debug("Titel: \(title)")
                logger.debug("Content: \(content)")
                
                await MainActor.run {
                    if let userId = self.currentEntry?.userId {
                        let learningNugget = LearningNugget(
                            userId: userId,
                            category: .persönlichesWachstum,
                            title: title,
                            content: content,
                            isAddedToJournal: true
                        )
                        
                        self.learningNugget = learningNugget
                        self.currentLearningText = content
                        self.updateCurrentEntry(with: learningNugget)
                        self.error = nil
                    } else {
                        self.error = NSError(domain: "OpenAIProcessing", code: -2, userInfo: [NSLocalizedDescriptionKey: "Kein aktiver Eintrag vorhanden"])
                    }
                }
            } else {
                logger.error("Konnte Learning Content nicht aus der Antwort extrahieren")
                await MainActor.run {
                    self.error = NSError(domain: "OpenAIProcessing", code: -3, userInfo: [NSLocalizedDescriptionKey: "Konnte Lerninhalte nicht aus der Antwort extrahieren"])
                }
            }
        } catch {
            logger.error("Fehler beim Decodieren der OpenAI-Antwort: \(error.localizedDescription)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    logger.error("Fehlender Schlüssel: \(key.stringValue) in \(context.codingPath)")
                case .typeMismatch(let type, let context):
                    logger.error("Typfehler: Erwarteter Typ \(type) in \(context.codingPath)")
                case .valueNotFound(let type, let context):
                    logger.error("Fehlender Wert: Typ \(type) in \(context.codingPath)")
                @unknown default:
                    logger.error("Unbekannter Decodierungsfehler")
                }
            }
            
            await MainActor.run {
                self.error = error
                // Debug-Logging der Rohdaten
                if let stringRepresentation = String(data: data, encoding: .utf8) {
                    logger.debug("Rohdaten der fehlgeschlagenen Antwort: \(stringRepresentation)")
                }
            }
        }
    }
}

// MARK: - OpenAI Response Handling
// Die OpenAIResponse Struktur wurde in Models/OpenAIResponse.swift verschoben 
