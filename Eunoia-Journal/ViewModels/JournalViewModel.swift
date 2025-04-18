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
    @Published var errorMessage: String?
    @Published var currentEntry: JournalEntry?
    @Published var aiSuggestions: [String] = []
    @Published var learningNugget: LearningNugget?
    @Published var currentLearningText: String = ""
    
    private let firebaseService = FirebaseService.shared
    private let coreDataManager = CoreDataManager.shared
    private let learningNuggetService = LearningNuggetService.shared
    private let journalService = JournalService.shared
    private let imageService = ImageService.shared
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Eunoia", category: "JournalViewModel")
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        loadJournalEntries() // Load entries immediately
        setupAuthSubscription()
        setupNotificationObservers()
    }
    
    private func setupNotificationObservers() {
        // Beobachte App-Lebenszyklus-Benachrichtigungen
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                // App geht in den Hintergrund, entferne Subscriptions
                self?.cancellables.removeAll()
                print("🔄 JournalViewModel: Firestore-Subscriptions entfernt")
            }
            .store(in: &cancellables)
        
        // Beobachte die RefreshFirestoreSubscriptions-Benachrichtigung
        NotificationCenter.default.publisher(for: NSNotification.Name("RefreshFirestoreSubscriptions"))
            .sink { [weak self] _ in
                guard let self = self else { return }
                
                // Stelle sicher, dass wir einen authentifizierten Benutzer haben
                if let userId = Auth.auth().currentUser?.uid {
                    print("🔄 JournalViewModel: Baue Firestore-Subscriptions neu auf")
                    self.setupSubscriptions(for: userId)
                    self.loadJournalEntries()
                }
            }
            .store(in: &cancellables)
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
        
        // Prüfe, ob eine Netzwerkverbindung verfügbar ist
        if !NetworkMonitor.shared.isNetworkAvailable {
            // Lade lokale Daten aus CoreData, wenn keine Netzwerkverbindung verfügbar ist
            loadLocalJournalEntries(for: userId)
            
            // Überwache Netzwerkverbindung und aktualisiere Daten, wenn Verbindung hergestellt wird
            NetworkMonitor.shared.$isConnected
                .filter { $0 }
                .first()
                .sink { [weak self] _ in
                    self?.setupFirestoreSubscription(for: userId)
                }
                .store(in: &cancellables)
            
            return
        }
        
        // Wenn Netzwerkverbindung verfügbar ist, verwende Firestore
        setupFirestoreSubscription(for: userId)
    }
    
    private func loadLocalJournalEntries(for userId: String) {
        Task {
            do {
                let entries = try await coreDataManager.fetchJournalEntries(for: userId)
                
                // Debug-Informationen für lokale Einträge
                for entry in entries {
                    if let localPaths = entry.localImagePaths, !localPaths.isEmpty {
                        self.logger.debug("[LocalLoad] Eintrag mit lokalen Bildpfaden geladen: \(String(describing: entry.id))")
                        // Array als String mit Trennzeichen darstellen
                        let pathsString = localPaths.joined(separator: ", ")
                        self.logger.debug("[LocalLoad] Lokale Bildpfade: \(pathsString)")
                    }
                    
                    if let imageURLs = entry.imageURLs, !imageURLs.isEmpty {
                        self.logger.debug("[LocalLoad] Eintrag mit Cloud-URLs geladen: \(String(describing: entry.id))")
                        self.logger.debug("[LocalLoad] Anzahl URLs: \(imageURLs.count)")
                    }
                }
                
                DispatchQueue.main.async {
                    self.journalEntries = entries
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = error
                    self.logger.error("Failed to load local journal entries: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func setupFirestoreSubscription(for userId: String) {
        // Subscribe to real-time journal entry updates with retry logic
        firebaseService.observeJournalEntries(for: userId)
            .retry(3) // Retry up to 3 times on failure
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                guard let self = self else { return }
                if case .failure(let error) = completion {
                    self.logger.error("Failed to observe journal entries: \(error.localizedDescription)")
                    self.error = error
                    
                    // Wenn Fehler auftritt, versuche lokale Daten zu laden
                    self.loadLocalJournalEntries(for: userId)
                }
            } receiveValue: { [weak self] entries in
                guard let self = self else { return }
                
                // Debug-Informationen für Bildpfade
                for entry in entries {
                    if let localPaths = entry.localImagePaths, !localPaths.isEmpty {
                        self.logger.debug("[JournalViewModel] Eintrag empfangen mit lokalen Bildpfaden: \(String(describing: entry.id))")
                        // Array als String mit Trennzeichen darstellen
                        let pathsString = localPaths.joined(separator: ", ")
                        self.logger.debug("[JournalViewModel] Lokale Bildpfade: \(pathsString)")
                    }
                    
                    if let imageURLs = entry.imageURLs, !imageURLs.isEmpty {
                        self.logger.debug("[JournalViewModel] Eintrag empfangen mit Cloud-Bild-URLs: \(String(describing: entry.id))")
                        self.logger.debug("[JournalViewModel] Anzahl URLs: \(imageURLs.count)")
                    }
                }
                
                self.journalEntries = entries
                
                // Nach dem Laden der Einträge den Streak und das Startdatum berechnen und speichern
                let streakInfo = self.calculateCurrentStreakWithStartDate()
                UserDefaults.standard.set(streakInfo.streak, forKey: "journalStreak")
                
                if let startDate = streakInfo.startDate {
                    UserDefaults.standard.set(startDate, forKey: "journalStreakStartDate")
                }
                
                // Benachrichtigung für das Dashboard senden
                var userInfo: [String: Any] = ["streakCount": streakInfo.streak]
                if let startDate = streakInfo.startDate {
                    userInfo["streakStartDate"] = startDate
                }
                NotificationCenter.default.post(name: NSNotification.Name("StreakUpdated"), object: nil, userInfo: userInfo)
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
        
        // Prüfe, ob bereits ein Eintrag für heute existiert
        let today = Calendar.current.startOfDay(for: Date())
        if let existingEntry = journalEntries.first(where: { Calendar.current.isDate($0.date, inSameDayAs: today) }) {
            // Wenn ein Eintrag existiert, setze diesen als currentEntry und aktualisiere alle Felder
            currentEntry = existingEntry
            currentLearningText = existingEntry.learning
            return
        }
        
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
        
        // Prüfe, ob bereits ein anderer Eintrag für das gleiche Datum existiert
        let entryDate = Calendar.current.startOfDay(for: entry.date)
        if let existingEntry = journalEntries.first(where: { 
            Calendar.current.isDate($0.date, inSameDayAs: entryDate) && $0.id != entry.id 
        }) {
            // Wenn ein anderer Eintrag existiert, lösche diesen
            do {
                try deleteEntry(existingEntry)
            } catch {
                print("Error deleting existing entry: \(error)")
            }
        }
        
        // Set sync status based on network availability
        entryToSave.syncStatus = NetworkMonitor.shared.isConnected ? .synced : .pendingUpload
        
        // Debug-Informationen für Bilder
        if let imageURLs = entryToSave.imageURLs, !imageURLs.isEmpty {
            logger.debug("[JournalViewModel] Eintrag speichern mit \(imageURLs.count) Bild-URLs")
        }
        
        if let localPaths = entryToSave.localImagePaths, !localPaths.isEmpty {
            logger.debug("[JournalViewModel] Eintrag speichern mit \(localPaths.count) lokalen Bildpfaden")
        }
        
        // Save to Core Data first
        do {
            try coreDataManager.saveJournalEntry(entryToSave)
            
            // Update local array immediately
            DispatchQueue.main.async {
                if let index = self.journalEntries.firstIndex(where: { $0.id == entryToSave.id }) {
                    self.journalEntries[index] = entryToSave
                    
                    // Debug-Informationen für aktualisierte Einträge
                    if let id = entryToSave.id {
                        self.logger.debug("[JournalViewModel] Eintrag aktualisiert mit ID: \(id)")
                    }
                    
                    if let imageURLs = entryToSave.imageURLs, !imageURLs.isEmpty {
                        self.logger.debug("[JournalViewModel] Aktualisierter Eintrag hat \(imageURLs.count) Bild-URLs")
                    }
                    
                    if let localPaths = entryToSave.localImagePaths, !localPaths.isEmpty {
                        self.logger.debug("[JournalViewModel] Aktualisierter Eintrag hat \(localPaths.count) lokale Bildpfade")
                    }
                } else {
                    self.journalEntries.insert(entryToSave, at: 0)
                    self.logger.debug("[JournalViewModel] Neuer Eintrag in journalEntries eingefügt")
                }
                
                // Nach dem Speichern den Streak neu berechnen und speichern
                let streakInfo = self.calculateCurrentStreakWithStartDate()
                UserDefaults.standard.set(streakInfo.streak, forKey: "journalStreak")
                
                if let startDate = streakInfo.startDate {
                    UserDefaults.standard.set(startDate, forKey: "journalStreakStartDate")
                }
                
                // Benachrichtigung für das Dashboard senden
                var userInfo: [String: Any] = ["streakCount": streakInfo.streak]
                if let startDate = streakInfo.startDate {
                    userInfo["streakStartDate"] = startDate
                }
                NotificationCenter.default.post(name: NSNotification.Name("StreakUpdated"), object: nil, userInfo: userInfo)
            }
            
            // If online, sync with Firebase
            if NetworkMonitor.shared.isConnected {
                Task {
                    do {
                        try await firebaseService.saveJournalEntry(entryToSave)
                        self.logger.debug("[JournalViewModel] Eintrag erfolgreich mit Firebase synchronisiert")
                    } catch {
                        self.logger.error("[JournalViewModel] Error saving entry to Firebase: \(error)")
                    }
                }
            }
        } catch {
            self.logger.error("[JournalViewModel] Error saving entry to CoreData: \(error)")
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
        // Beende, wenn bereits ein Ladevorgang läuft
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        error = nil
        
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
                    self.isLoading = false
                    
                    if let serviceError = error as? ServiceError {
                        self.error = serviceError
                        
                        // Spezifische Fehlerbehandlung basierend auf dem Fehlertyp
                        switch serviceError {
                        case .apiQuotaExceeded:
                            self.errorMessage = "Das tägliche Limit für KI-Generierungen wurde erreicht. Bitte versuche es morgen erneut."
                            self.logger.error("API-Quota überschritten: \(serviceError.localizedDescription)")
                        case .aiServiceUnavailable:
                            self.errorMessage = "Der KI-Service ist derzeit nicht verfügbar. Bitte versuche es später erneut."
                            self.logger.error("KI-Service nicht verfügbar: \(serviceError.localizedDescription)")
                        case .networkError:
                            self.errorMessage = "Es konnte keine Verbindung zum Netzwerk hergestellt werden. Bitte überprüfe deine Internetverbindung."
                            self.logger.error("Netzwerkfehler: \(serviceError.localizedDescription)")
                        case .databaseError:
                            self.errorMessage = "Datenbankfehler: \(serviceError.localizedDescription)"
                            self.logger.error("Datenbankfehler: \(serviceError.localizedDescription)")
                        case .aiGeneration(let message):
                            self.errorMessage = "Beim Generieren des Learning Nuggets ist ein Fehler aufgetreten: \(message)"
                            self.logger.error("KI-Generierungsfehler: \(serviceError.localizedDescription)")
                        default:
                            self.errorMessage = "Beim Generieren des Learning Nuggets ist ein Fehler aufgetreten. Bitte versuche es erneut."
                            self.logger.error("Allgemeiner Fehler: \(serviceError.localizedDescription)")
                        }
                    } else {
                        self.error = error
                        self.errorMessage = "Beim Generieren des Learning Nuggets ist ein Fehler aufgetreten. Bitte versuche es erneut."
                        self.logger.error("Unbekannter Fehler bei der Generierung des Learning Nuggets: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    func addLearningNuggetToEntry() {
        guard var entry = currentEntry, let nugget = learningNugget else { return }
        
        // Aktualisiere den Eintrag nur mit dem Learning Nugget, behalte das original Learning-Feld bei
        entry = JournalEntry(
            id: entry.id,
            userId: entry.userId,
            date: entry.date,
            gratitude: entry.gratitude,
            highlight: entry.highlight,
            learning: entry.learning, // Behalte original learning bei, nicht mit nugget.content überschreiben
            learningNugget: nugget,
            lastModified: Date(),
            syncStatus: .pendingUpload,
            title: entry.title,
            content: entry.content,
            location: entry.location,
            imageURLs: entry.imageURLs,
            localImagePaths: entry.localImagePaths,
            images: entry.images
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
    
    // Erweiterte Methode, die sowohl die Streak-Länge als auch das Startdatum zurückgibt
    func calculateCurrentStreakWithStartDate() -> (streak: Int, startDate: Date?) {
        var streak = 0
        let calendar = Calendar.current
        var currentDate = calendar.startOfDay(for: Date())
        var streakStartDate: Date? = nil
        
        while true {
            let entriesForDate = entriesByDate(date: currentDate)
            if entriesForDate.isEmpty {
                break
            }
            
            streak += 1
            // Aktualisiere das Startdatum bei jedem gefundenen Tag
            streakStartDate = currentDate
            
            // Gehe einen Tag zurück
            currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate) ?? Date()
        }
        
        return (streak, streakStartDate)
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
    
    func addImage(to entry: JournalEntry, url: String?, localPath: String?) {
        var updatedEntry = entry
        let newImage = JournalEntry.JournalImage(url: url, localPath: localPath)
        
        if var images = updatedEntry.images {
            images.append(newImage)
            updatedEntry.images = images
        } else {
            updatedEntry.images = [newImage]
        }
        
        saveEntry(updatedEntry)
    }
    
    func removeImage(from entry: JournalEntry, at index: Int) {
        var updatedEntry = entry
        if var images = updatedEntry.images {
            images.remove(at: index)
            updatedEntry.images = images
            saveEntry(updatedEntry)
        }
    }
    
    func updateImage(in entry: JournalEntry, at index: Int, url: String?, localPath: String?) {
        var updatedEntry = entry
        if var images = updatedEntry.images {
            let currentImage = images[index]
            let updatedImage = JournalEntry.JournalImage(
                id: currentImage.id,
                url: url ?? currentImage.url,
                localPath: localPath ?? currentImage.localPath,
                uploadDate: Date()
            )
            images[index] = updatedImage
            updatedEntry.images = images
            saveEntry(updatedEntry)
        }
    }
    
    func saveEntryWithImages(_ entry: JournalEntry, images: [UIImage]) async throws -> JournalEntry {
        do {
            // Prüfe zuerst, ob für dieses Datum bereits ein Eintrag existiert (außer diesem)
            let entryDate = Calendar.current.startOfDay(for: entry.date)
            
            // Sichere alle Einträge für denselben Tag in einer Liste
            let entriesForSameDate = journalEntries.filter { 
                Calendar.current.isDate($0.date, inSameDayAs: entryDate) && $0.id != entry.id 
            }
            
            // Wenn ein anderer Eintrag für denselben Tag existiert, versuche diesen zu löschen
            for existingEntry in entriesForSameDate {
                logger.debug("[JournalViewModel] Gefunden: Bestehender Eintrag für denselben Tag mit ID: \(existingEntry.id ?? "unbekannt")")
                
                do {
                    logger.debug("[JournalViewModel] Lösche bestehenden Eintrag für denselben Tag mit ID: \(existingEntry.id ?? "unbekannt")")
                    try await deleteEntryWithImages(existingEntry)
                } catch {
                    // Wenn das Löschen fehlschlägt, loggen wir den Fehler, setzen aber den Prozess fort
                    logger.error("[JournalViewModel] Fehler beim Löschen des existierenden Eintrags: \(error.localizedDescription)")
                    logger.debug("[JournalViewModel] Fahre trotzdem mit dem Speichern des neuen Eintrags fort")
                    
                    // Lokale Kopie trotzdem entfernen, um Duplikate zu vermeiden
                    await MainActor.run {
                        journalEntries.removeAll { $0.id == existingEntry.id }
                    }
                }
            }
            
            // Bilder speichern und hochladen
            var updatedEntry: JournalEntry
            do {
                updatedEntry = try await journalService.saveJournalEntryWithImages(entry: entry, images: images)
            } catch {
                // Wenn der Cloud-Upload fehlschlägt, versuchen wir trotzdem, den Eintrag lokal zu speichern
                logger.error("[JournalViewModel] Fehler beim Speichern des Eintrags mit Bildern in der Cloud: \(error.localizedDescription)")
                
                // Speichere Bilder lokal
                var localImagePaths: [String] = entry.localImagePaths ?? []
                for (index, image) in images.enumerated() {
                    do {
                        if let entryId = entry.id {
                            let localPath = try await imageService.saveImageLocally(image, entryId: entryId)
                            // Vermeidung von Duplikaten
                            if !localImagePaths.contains(localPath) {
                                localImagePaths.append(localPath)
                                logger.debug("[JournalViewModel] Bild \(index) lokal gespeichert: \(localPath)")
                            }
                        }
                    } catch {
                        logger.error("[JournalViewModel] Fehler beim lokalen Speichern von Bild \(index): \(error.localizedDescription)")
                    }
                }
                
                // Aktualisiere den Eintrag mit lokalen Bildpfaden
                updatedEntry = JournalEntry(
                    id: entry.id,
                    userId: entry.userId,
                    date: entry.date,
                    gratitude: entry.gratitude,
                    highlight: entry.highlight,
                    learning: entry.learning,
                    learningNugget: entry.learningNugget,
                    lastModified: Date(),
                    syncStatus: .pendingUpload,
                    title: entry.title,
                    content: entry.content,
                    location: entry.location,
                    imageURLs: entry.imageURLs,
                    localImagePaths: Array(Set(localImagePaths)), // Verwende Set für Eindeutigkeit
                    images: entry.images
                )
                
                // Speichere den Eintrag lokal
                try coreDataManager.saveJournalEntry(updatedEntry)
                logger.debug("[JournalViewModel] Eintrag lokal gespeichert mit \(localImagePaths.count) Bildpfaden")
            }
            
            // Stelle sicher, dass currentEntry aktualisiert wird
            await MainActor.run {
                // Bestehende Einträge für denselben Tag entfernen
                journalEntries.removeAll { Calendar.current.isDate($0.date, inSameDayAs: entryDate) && $0.id != updatedEntry.id }
                
                self.currentEntry = updatedEntry
                
                // Aktualisiere auch den Eintrag in der journalEntries-Liste
                if let index = self.journalEntries.firstIndex(where: { $0.id == updatedEntry.id }) {
                    self.journalEntries[index] = updatedEntry
                    self.logger.debug("[JournalViewModel] Eintrag in Liste aktualisiert mit \(updatedEntry.imageURLs?.count ?? 0) Bild-URLs und \(updatedEntry.localImagePaths?.count ?? 0) lokalen Pfaden")
                } else {
                    self.journalEntries.insert(updatedEntry, at: 0)
                    self.logger.debug("[JournalViewModel] Neuer Eintrag mit Bildern zur Liste hinzugefügt")
                }
                
                // UI aktualisieren
                self.objectWillChange.send()
            }
            
            return updatedEntry
        } catch {
            self.logger.error("[JournalViewModel] Fehler beim Speichern des Eintrags mit Bildern: \(error.localizedDescription)")
            throw error
        }
    }
    
    func deleteEntryWithImages(_ entry: JournalEntry) async throws {
        // Speichere relevante Daten für den Fall, dass wir nur lokal löschen können
        let entryId = entry.id
        var failedCloudOperations = false
        var localSuccess = false
        
        do {
            // Lösche zuerst die Bilder, falls vorhanden
            if let imageUrls = entry.imageURLs {
                // Stelle sicher, dass keine nil-Werte in der URL-Liste vorhanden sind
                let validUrls = imageUrls.compactMap { $0 }
                if !validUrls.isEmpty {
                    do {
                        try await journalService.deleteCloudImages(urls: validUrls)
                    } catch {
                        logger.error("Fehler beim Löschen der Cloud-Bilder: \(error.localizedDescription)")
                        failedCloudOperations = true
                        // Wir fahren fort, trotz des Fehlers
                    }
                }
            }
            
            // Lösche lokale Bilder
            if let localPaths = entry.localImagePaths, !localPaths.isEmpty {
                do {
                    try await Task {
                        try await imageService.deleteLocalImages(paths: localPaths)
                    }.value
                } catch {
                    logger.error("Fehler beim Löschen der lokalen Bilder: \(error.localizedDescription)")
                    // Wir fahren fort, trotz des Fehlers
                }
            }
            
            // Dann lösche den Eintrag in Firebase
            if let id = entryId {
                do {
                    if NetworkMonitor.shared.isConnected {
                        try await journalService.deleteJournalEntry(withId: id)
                    } else {
                        failedCloudOperations = true
                    }
                } catch {
                    logger.error("Fehler beim Löschen des Eintrags in Firebase: \(error.localizedDescription)")
                    failedCloudOperations = true
                    // Wir versuchen trotzdem, den Eintrag lokal zu löschen
                }
                
                // Aktualisiere lokale Daten unabhängig vom Cloud-Ergebnis
                do {
                    // Lösche aus Core Data
                    try await coreDataManager.deleteJournalEntryAsync(withId: id)
                    localSuccess = true
                    
                    // Aktualisiere den lokalen Cache
                    await MainActor.run {
                        journalEntries.removeAll { $0.id == id }
                    }
                } catch {
                    logger.error("Fehler beim lokalen Löschen des Eintrags: \(error.localizedDescription)")
                    throw error // Hier werfen wir den Fehler, da lokales Löschen kritisch ist
                }
            }
            
            // Wenn die Cloud-Operationen fehlgeschlagen sind, markieren wir den lokalen Eintrag als pendingDelete
            if failedCloudOperations && localSuccess && NetworkMonitor.shared.isConnected {
                logger.warning("Cloud-Löschung fehlgeschlagen, aber lokaler Eintrag wurde entfernt. Der Eintrag wird bei der nächsten Synchronisierung gelöscht.")
                
                do {
                    try await queueEntryForDeletion(entryId: entryId)
                } catch {
                    logger.error("Fehler beim Queueing des Eintrags für spätere Löschung: \(error.localizedDescription)")
                }
            }
        } catch {
            logger.error("Fehler beim Löschen des Eintrags mit Bildern: \(error.localizedDescription)")
            throw error
        }
    }
    
    private func queueEntryForDeletion(entryId: String?) async throws {
        guard let id = entryId else { return }
        
        // Speichere die ID des zu löschenden Eintrags in UserDefaults
        var pendingDeletions = UserDefaults.standard.stringArray(forKey: "pendingEntryDeletions") ?? []
        if !pendingDeletions.contains(id) {
            pendingDeletions.append(id)
            UserDefaults.standard.set(pendingDeletions, forKey: "pendingEntryDeletions")
        }
    }
    
    func updateEntryWithImages(_ entry: JournalEntry, images: [UIImage]) async throws -> JournalEntry {
        // Stelle sicher, dass keine neue ID vergeben wird, wenn wir einen existierenden Eintrag aktualisieren
        var entryToUpdate = entry
        
        // Wenn der Eintrag keine ID hat, erstelle eine
        if entryToUpdate.id == nil {
            entryToUpdate = JournalEntry(
                id: UUID().uuidString,
                userId: entryToUpdate.userId,
                date: entryToUpdate.date,
                gratitude: entryToUpdate.gratitude,
                highlight: entryToUpdate.highlight,
                learning: entryToUpdate.learning,
                learningNugget: entryToUpdate.learningNugget,
                lastModified: Date(),
                syncStatus: .pendingUpload,
                title: entryToUpdate.title,
                content: entryToUpdate.content,
                location: entryToUpdate.location,
                imageURLs: entryToUpdate.imageURLs,
                localImagePaths: entryToUpdate.localImagePaths,
                images: entryToUpdate.images
            )
        }
        
        // Aktualisiere das Änderungsdatum
        entryToUpdate = JournalEntry(
            id: entryToUpdate.id,
            userId: entryToUpdate.userId,
            date: entryToUpdate.date,
            gratitude: entryToUpdate.gratitude,
            highlight: entryToUpdate.highlight,
            learning: entryToUpdate.learning,
            learningNugget: entryToUpdate.learningNugget,
            lastModified: Date(),
            syncStatus: .pendingUpload,
            title: entryToUpdate.title,
            content: entryToUpdate.content,
            location: entryToUpdate.location,
            imageURLs: entryToUpdate.imageURLs,
            localImagePaths: entryToUpdate.localImagePaths,
            images: entryToUpdate.images
        )
        
        // Verwende die existierende saveEntryWithImages-Methode
        return try await saveEntryWithImages(entryToUpdate, images: images)
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
            
            if let result = response.extractLearningContent() {
                let title = result.0
                let content = result.1
                
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
    
    private func deleteLocalImages(paths: [String]) {
        Task {
            do {
                try await imageService.deleteLocalImages(paths: paths)
            } catch {
                logger.error("Fehler beim Löschen der lokalen Bilder: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Neue Funktionen für Bildverwaltung
    
    /// Löscht ein einzelnes Bild aus dem Firebase Storage mit umfangreicher Protokollierung
    /// - Parameter url: Die URL des zu löschenden Bildes
    func deleteCloudImage(url: String) async throws {
        guard !url.isEmpty else {
            logger.warning("[JournalViewModel] ⚠️ Leere URL kann nicht gelöscht werden")
            throw NSError(domain: "JournalViewModel", code: 1001, userInfo: [
                NSLocalizedDescriptionKey: "Die URL ist leer und kann nicht gelöscht werden"
            ])
        }
        
        // Validiere die URL-Struktur für Firebase Storage
        if !url.contains("firebasestorage.googleapis.com") {
            logger.warning("[JournalViewModel] ⚠️ URL scheint keine Firebase Storage URL zu sein: \(url)")
            // Wir fahren trotzdem fort, da es auch eine URL zu einem anderen Storage-System sein könnte
        }
        
        logger.debug("[JournalViewModel] 🔄 Starte Löschung des Bildes aus Cloud Storage: \(url)")
        
        do {
            // Starte Timer für Performance-Messung
            let startTime = Date()
            
            // Verwende das ImageService zum Löschen des Bildes
            try await imageService.deleteImage(url: url)
            
            // Berechne die verstrichene Zeit
            let elapsedTime = Date().timeIntervalSince(startTime)
            logger.debug("[JournalViewModel] ✅ Bild erfolgreich aus Cloud Storage gelöscht: \(url) (Dauer: \(String(format: "%.2f", elapsedTime))s)")
            
            // Verifiziere Löschung, wenn möglich - in einem realen Szenario könntest du hier prüfen, ob das Bild wirklich gelöscht wurde
            logger.debug("[JournalViewModel] 🔍 Löschung erfolgreich abgeschlossen, Bild sollte nicht mehr in Storage verfügbar sein")
        } catch {
            // Detaillierte Fehlerprotokolle
            logger.error("[JournalViewModel] ❌ Fehler beim Löschen des Bildes aus Cloud Storage: \(error.localizedDescription)")
            
            // Kategorisiere und protokolliere spezifische Fehlertypen
            if let nsError = error as? NSError {
                switch nsError.code {
                case 404:
                    logger.error("[JournalViewModel] ❌ Bild wurde nicht gefunden (404): \(url)")
                case 403:
                    logger.error("[JournalViewModel] ❌ Keine Berechtigung zum Löschen (403): \(url)")
                case -1009:
                    logger.error("[JournalViewModel] ❌ Netzwerkfehler beim Löschen: \(url)")
                default:
                    logger.error("[JournalViewModel] ❌ Unbekannter Fehler (\(nsError.code)): \(url)")
                }
            }
            
            // Werfe den Fehler, damit die aufrufende Funktion ihn behandeln kann
            throw error
        }
    }
    
    /// Speichert einen Eintrag direkt in CoreData, ohne andere Aktionen
    /// - Parameter entry: Der zu speichernde Eintrag
    func persistChanges(entry: JournalEntry) throws {
        logger.debug("[JournalViewModel] Speichere Änderungen direkt in CoreData für Eintrag: \(entry.id ?? "unbekannt")")
        
        do {
            // Speichere den Eintrag in CoreData
            try coreDataManager.saveJournalEntry(entry)
            
            // Aktualisiere auch den Eintrag in der journalEntries-Liste
            if let index = self.journalEntries.firstIndex(where: { $0.id == entry.id }) {
                journalEntries[index] = entry
                logger.debug("[JournalViewModel] Eintrag in Liste aktualisiert")
            }
            
            // UI aktualisieren
            objectWillChange.send()
        } catch {
            logger.error("[JournalViewModel] Fehler beim direkten Speichern in CoreData: \(error.localizedDescription)")
            throw error
        }
    }
}

// MARK: - OpenAI Response Handling
// Die OpenAIResponse Struktur wurde in Models/OpenAIResponse.swift verschoben 
