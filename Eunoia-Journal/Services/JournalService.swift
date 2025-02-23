#if canImport(JournalingSuggestions)
import JournalingSuggestions
#endif
import Foundation
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth
import Combine
import OSLog
import FirebaseStorage
import UIKit
import PhotosUI

// Definiere StorageHandle als Typealias
typealias StorageHandle = Int

@available(iOS 17.0, *)
class JournalService {
    static let shared = JournalService()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Eunoia", category: "JournalService")
    private let networkMonitor = NetworkMonitor.shared
    private let db: Firestore
    private let coreDataManager = CoreDataManager.shared
    private var retryCount = 0
    private let maxRetries = 3
    
    private init() {
        // Konfiguriere Firestore
        let settings = FirestoreSettings()
        settings.isPersistenceEnabled = true
        
        // Cache-Größe als NSNumber (100 MB)
        let cacheSize: Int64 = 100 * 1024 * 1024
        settings.cacheSettings = PersistentCacheSettings(sizeBytes: NSNumber(value: cacheSize))
        
        let db = Firestore.firestore()
        db.settings = settings
        self.db = db
        
        #if DEBUG
        logger.info("Firestore konfiguriert mit Persistence und \(cacheSize / 1024 / 1024) MB Cache")
        #endif
    }
    
    private func handleFirestoreError(_ error: Error) async throws {
        if let firestoreError = error as NSError? {
            switch firestoreError.code {
            case 8: // RESOURCE_EXHAUSTED
                if retryCount < maxRetries {
                    retryCount += 1
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retryCount)) * 1_000_000_000))
                    // Operation wird automatisch wiederholt
                } else {
                    throw FirebaseError.resourceExhausted
                }
            case 14: // UNAVAILABLE
                if !networkMonitor.isNetworkAvailable {
                    throw NetworkError.noConnection
                }
            default:
                throw error
            }
        }
    }
    
    // MARK: - Journal Entries
    
    func saveJournalEntry(_ entry: JournalEntry) async throws {
        guard let id = entry.id else {
            throw FirebaseError.invalidData("Entry ID is missing")
        }
        
        // Speichere zuerst lokal mit Fehlerbehandlung
        do {
            try coreDataManager.saveJournalEntry(entry)
        } catch {
            logger.error("Fehler beim lokalen Speichern: \(error.localizedDescription)")
            throw FirebaseError.storageError("Lokales Speichern fehlgeschlagen: \(error.localizedDescription)")
        }
        
        // Wenn offline, beende hier
        guard networkMonitor.isNetworkAvailable else {
            logger.info("Offline mode: Entry saved locally")
            return
        }
        
        do {
            var dict: [String: Any] = [
                "userId": entry.userId,
                "date": Timestamp(date: entry.date),
                "gratitude": entry.gratitude,
                "highlight": entry.highlight,
                "learning": entry.learning,
                "lastModified": Timestamp(date: entry.lastModified),
                "syncStatus": entry.syncStatus.rawValue,
                "serverTimestamp": FieldValue.serverTimestamp()
            ]
            
            // Optional fields mit Validierung
            if let title = entry.title, !title.isEmpty { dict["title"] = title }
            if let content = entry.content, !content.isEmpty { dict["content"] = content }
            if let location = entry.location, !location.isEmpty { dict["location"] = location }
            if let learningNugget = entry.learningNugget {
                dict["learningNugget"] = [
                    "category": learningNugget.category.rawValue,
                    "content": learningNugget.content,
                    "isAddedToJournal": learningNugget.isAddedToJournal
                ]
            }
            if let imageURLs = entry.imageURLs, !imageURLs.isEmpty { dict["imageURLs"] = imageURLs }
            
            // Implementiere Retry-Logik mit exponentieller Verzögerung
            var attempt = 0
            var lastError: Error?
            
            while attempt < self.maxRetries {
                do {
                    try await self.db.collection("journalEntries").document(id).setData(dict)
                    self.retryCount = 0 // Reset retry count after successful operation
                    return
                } catch {
                    lastError = error
                    attempt += 1
                    
                    if attempt < self.maxRetries {
                        // Exponential backoff: 0.5s, 1s, 2s
                        let delay = Double(pow(2.0, Double(attempt - 1))) * 0.5
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                }
            }
            
            // Wenn alle Versuche fehlgeschlagen sind
            self.logger.error("Alle Speicherversuche fehlgeschlagen nach \(self.maxRetries) Versuchen")
            throw lastError ?? FirebaseError.storageError("Unbekannter Fehler beim Speichern")
            
        } catch {
            logger.error("Error saving entry: \(error.localizedDescription)")
            throw FirebaseError.storageError("Firebase Speicherfehler: \(error.localizedDescription)")
        }
    }
    
    func fetchJournalEntries(for userId: String) async throws -> [JournalEntry] {
        do {
            // First try with server timestamp ordering
            do {
                let snapshot = try await db.collection("journalEntries")
                    .whereField("userId", isEqualTo: userId)
                    .order(by: "serverTimestamp", descending: true)
                    .getDocuments()
                
                return try snapshot.documents.compactMap { document -> JournalEntry? in
                    let data = document.data()
                    
                    // Extract timestamps
                    guard let dateTimestamp = data["date"] as? Timestamp,
                          let lastModifiedTimestamp = data["lastModified"] as? Timestamp,
                          let userId = data["userId"] as? String,
                          let gratitude = data["gratitude"] as? String,
                          let highlight = data["highlight"] as? String,
                          let learning = data["learning"] as? String,
                          let syncStatusRaw = data["syncStatus"] as? String,
                          let syncStatus = SyncStatus(rawValue: syncStatusRaw) else {
                        return nil
                    }
                    
                    // Handle optional learning nugget
                    var learningNugget: LearningNugget?
                    if let nuggetData = data["learningNugget"] as? [String: Any],
                       let categoryRaw = nuggetData["category"] as? String,
                       let category = LearningNugget.Category(rawValue: categoryRaw),
                       let content = nuggetData["content"] as? String,
                       let isAddedToJournal = nuggetData["isAddedToJournal"] as? Bool {
                        learningNugget = LearningNugget(
                            userId: userId,
                            category: category,
                            title: "Lernimpuls",
                            content: content,
                            isAddedToJournal: isAddedToJournal
                        )
                    }
                    
                    // Handle server timestamp
                    let serverTimestamp = data["serverTimestamp"] as? Timestamp
                    
                    return JournalEntry(
                        id: document.documentID,
                        userId: userId,
                        date: dateTimestamp.dateValue(),
                        gratitude: gratitude,
                        highlight: highlight,
                        learning: learning,
                        learningNugget: learningNugget,
                        lastModified: lastModifiedTimestamp.dateValue(),
                        syncStatus: syncStatus,
                        serverTimestamp: serverTimestamp
                    )
                }
            } catch let error as NSError {
                // Check if error is due to missing index
                if error.domain == "FIRFirestoreErrorDomain" && error.code == 9 {
                    // Fallback to client-side sorting if index is missing
                    let snapshot = try await db.collection("journalEntries")
                        .whereField("userId", isEqualTo: userId)
                        .getDocuments()
                    
                    return try snapshot.documents.compactMap { document -> JournalEntry? in
                        let data = document.data()
                        
                        // Extract timestamps
                        guard let dateTimestamp = data["date"] as? Timestamp,
                              let lastModifiedTimestamp = data["lastModified"] as? Timestamp,
                              let userId = data["userId"] as? String,
                              let gratitude = data["gratitude"] as? String,
                              let highlight = data["highlight"] as? String,
                              let learning = data["learning"] as? String,
                              let syncStatusRaw = data["syncStatus"] as? String,
                              let syncStatus = SyncStatus(rawValue: syncStatusRaw) else {
                            return nil
                        }
                        
                        // Handle optional learning nugget
                        var learningNugget: LearningNugget?
                        if let nuggetData = data["learningNugget"] as? [String: Any],
                           let categoryRaw = nuggetData["category"] as? String,
                           let category = LearningNugget.Category(rawValue: categoryRaw),
                           let content = nuggetData["content"] as? String,
                           let isAddedToJournal = nuggetData["isAddedToJournal"] as? Bool {
                            learningNugget = LearningNugget(
                                userId: userId,
                                category: category,
                                title: "Lernimpuls",
                                content: content,
                                isAddedToJournal: isAddedToJournal
                            )
                        }
                        
                        // Handle server timestamp
                        let serverTimestamp = data["serverTimestamp"] as? Timestamp
                        
                        return JournalEntry(
                            id: document.documentID,
                            userId: userId,
                            date: dateTimestamp.dateValue(),
                            gratitude: gratitude,
                            highlight: highlight,
                            learning: learning,
                            learningNugget: learningNugget,
                            lastModified: lastModifiedTimestamp.dateValue(),
                            syncStatus: syncStatus,
                            serverTimestamp: serverTimestamp
                        )
                    }.sorted { $0.date > $1.date }
                } else {
                    throw error
                }
            }
        } catch {
            throw FirebaseError.fetchFailed("Failed to fetch entries: \(error.localizedDescription)")
        }
    }
    
    func deleteJournalEntry(withId id: String) async throws {
        try await db.collection("journalEntries").document(id).delete()
    }
    
    func observeJournalEntries(for userId: String) -> AnyPublisher<[JournalEntry], Error> {
        let subject = PassthroughSubject<[JournalEntry], Error>()
        
        let query = db.collection("journalEntries")
            .whereField("userId", isEqualTo: userId)
        
        query.addSnapshotListener { snapshot, error in
            if let error = error {
                subject.send(completion: .failure(error))
                return
            }
            
            guard let documents = snapshot?.documents else {
                subject.send([])
                return
            }
            
            do {
                let entries = try documents.compactMap { document -> JournalEntry? in
                    let data = document.data()
                    
                    // Extract timestamps
                    guard let dateTimestamp = data["date"] as? Timestamp,
                          let lastModifiedTimestamp = data["lastModified"] as? Timestamp,
                          let userId = data["userId"] as? String,
                          let gratitude = data["gratitude"] as? String,
                          let highlight = data["highlight"] as? String,
                          let learning = data["learning"] as? String,
                          let syncStatusRaw = data["syncStatus"] as? String,
                          let syncStatus = SyncStatus(rawValue: syncStatusRaw) else {
                        return nil
                    }
                    
                    // Handle optional learning nugget
                    var learningNugget: LearningNugget?
                    if let nuggetData = data["learningNugget"] as? [String: Any],
                       let categoryRaw = nuggetData["category"] as? String,
                       let category = LearningNugget.Category(rawValue: categoryRaw),
                       let content = nuggetData["content"] as? String,
                       let isAddedToJournal = nuggetData["isAddedToJournal"] as? Bool {
                        learningNugget = LearningNugget(
                            userId: userId,
                            category: category,
                            title: "Lernimpuls",
                            content: content,
                            isAddedToJournal: isAddedToJournal
                        )
                    }
                    
                    // Handle server timestamp
                    let serverTimestamp = data["serverTimestamp"] as? Timestamp
                    
                    return JournalEntry(
                        id: document.documentID,
                        userId: userId,
                        date: dateTimestamp.dateValue(),
                        gratitude: gratitude,
                        highlight: highlight,
                        learning: learning,
                        learningNugget: learningNugget,
                        lastModified: lastModifiedTimestamp.dateValue(),
                        syncStatus: syncStatus,
                        serverTimestamp: serverTimestamp
                    )
                }.sorted { $0.date > $1.date }
                
                subject.send(entries)
            } catch {
                subject.send(completion: .failure(error))
            }
        }
        
        return subject.eraseToAnyPublisher()
    }
    
    #if canImport(JournalingSuggestions)
    @available(iOS 17.2, *)
    func createEntryFromSuggestion(_ suggestion: JournalingSuggestion) async throws -> JournalEntry {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw FirebaseError.invalidData("User ID ist nicht verfügbar")
        }
        
        var locationString: String? = nil
        
        // Verbesserte Standortabfrage
        do {
            let locationManager = LocationManager.shared
            
            // Prüfe zuerst den Autorisierungsstatus
            let authStatus = locationManager.authorizationStatus
            
            switch authStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                // Nur wenn bereits autorisiert, starte die Standortabfrage
                locationManager.startUpdatingLocation()
                do {
                    locationString = try await withTimeout(seconds: 5) {
                        try await locationManager.getCurrentLocationString()
                    }
                } catch {
                    logger.warning("Timeout bei Standortabfrage: \(error.localizedDescription)")
                }
            case .notDetermined:
                // Beantrage Berechtigung und warte maximal 3 Sekunden
                locationManager.requestAuthorization()
                for _ in 0..<6 {
                    if locationManager.authorizationStatus != .notDetermined {
                        break
                    }
                    try await Task.sleep(nanoseconds: 500_000_000)
                }
                
                if locationManager.authorizationStatus == .authorizedWhenInUse || 
                   locationManager.authorizationStatus == .authorizedAlways {
                    locationManager.startUpdatingLocation()
                    do {
                        locationString = try await withTimeout(seconds: 5) {
                            try await locationManager.getCurrentLocationString()
                        }
                    } catch {
                        logger.warning("Timeout bei Standortabfrage nach Autorisierung: \(error.localizedDescription)")
                    }
                }
            case .restricted:
                logger.warning("Standortzugriff ist eingeschränkt")
            case .denied:
                logger.warning("Standortzugriff wurde verweigert")
            @unknown default:
                logger.warning("Unbekannter Autorisierungsstatus")
            }
        } catch {
            logger.warning("Fehler bei Standortabfrage: \(error)")
        }
        
        // Erstelle einen neuen Eintrag
        let entry = JournalEntry(
            id: UUID().uuidString,
            userId: userId,
            date: Date(),
            gratitude: "",
            highlight: suggestion.title,
            learning: "",
            learningNugget: nil,
            lastModified: Date(),
            syncStatus: .pendingUpload,
            title: suggestion.title,
            content: suggestion.title,
            location: locationString
        )
        
        // Speichere zuerst in CoreData
        do {
            try await Task.sleep(nanoseconds: 100_000_000) // Kleine Verzögerung für bessere Stabilität
            try coreDataManager.saveJournalEntry(entry)
            
            // Wenn online, speichere auch in Firebase
            if NetworkMonitor.shared.isConnected {
                try await saveJournalEntry(entry)
            }
            
            return entry
        } catch {
            logger.error("Fehler beim Speichern des Eintrags: \(error.localizedDescription)")
            throw JournalError.saveError(error.localizedDescription)
        }
    }
    
    // Hilfsfunktion für Timeout
    func withTimeout<T>(seconds: Double, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NSError(domain: "TimeoutError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Operation timeout"])
            }
            
            for try await result in group {
                group.cancelAll()
                return result
            }
            
            throw NSError(domain: "TimeoutError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No result received"])
        }
    }
    #endif
    
    // MARK: - Image Management
    
    private struct PendingImageUpload: Codable {
        let localPath: String
        let entryId: String
        let createdAt: Date
    }
    
    private let imageQueue = DispatchQueue(label: "com.eunoia.imageProcessing")
    private let pendingUploadsKey = "pendingImageUploads"
    
    func saveJournalEntryWithImages(_ entry: JournalEntry, images: [UIImage]) async throws -> JournalEntry {
        guard let entryId = entry.id else {
            throw FirebaseError.invalidData("Entry ID fehlt")
        }
        
        var updatedEntry = entry
        
        // Speichere Bilder lokal
        let localPaths = try await saveImagesLocally(images, for: entryId)
        updatedEntry.localImagePaths = localPaths
        
        // Speichere den Eintrag zuerst mit lokalen Pfaden
        try await saveJournalEntry(updatedEntry)
        
        // Versuche Cloud-Upload nur wenn online
        if NetworkMonitor.shared.isConnected {
            do {
                let cloudUrls = try await uploadImagesToCloud(localPaths, for: entryId)
                updatedEntry.imageURLs = cloudUrls
                updatedEntry.syncStatus = .synced
                
                // Aktualisiere den Eintrag mit den Cloud-URLs
                try await saveJournalEntry(updatedEntry)
            } catch {
                logger.error("Fehler beim Cloud-Upload: \(error.localizedDescription)")
                updatedEntry.syncStatus = .pendingUpload
                // Speichere den aktualisierten Status
                try await saveJournalEntry(updatedEntry)
                throw error
            }
        } else {
            updatedEntry.syncStatus = .pendingUpload
            try await saveJournalEntry(updatedEntry)
        }
        
        return updatedEntry
    }
    
    private func saveImagesLocally(_ images: [UIImage], for entryId: String) async throws -> [String] {
        var localPaths: [String] = []
        
        let fileManager = FileManager.default
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw FirebaseError.storageError("Dokumentenverzeichnis nicht verfügbar")
        }
        
        // Sanitize entry ID
        let sanitizedEntryId = entryId.replacingOccurrences(of: "/", with: "_")
        let journalImagesPath = documentsPath.appendingPathComponent("journal_images").appendingPathComponent(sanitizedEntryId)
        
        do {
            // Erstelle Verzeichnis mit expliziter Fehlerbehandlung
            try fileManager.createDirectory(at: journalImagesPath, withIntermediateDirectories: true, attributes: nil)
            
            for (index, image) in images.enumerated() {
                let filename = "\(UUID().uuidString)_\(index).jpg"
                let imagePath = journalImagesPath.appendingPathComponent(filename)
                
                // Komprimiere und validiere das Bild
                guard let imageData = image.jpegData(compressionQuality: 0.7),
                      !imageData.isEmpty else {
                    self.logger.error("Bildkomprimierung fehlgeschlagen für Bild \(index)")
                    continue
                }
                
                do {
                    try imageData.write(to: imagePath)
                    
                    // Validiere geschriebene Datei
                    guard let writtenData = try? Data(contentsOf: imagePath),
                          !writtenData.isEmpty,
                          UIImage(data: writtenData) != nil else {
                        self.logger.error("Validierung der geschriebenen Datei fehlgeschlagen: \(imagePath.path)")
                        try? fileManager.removeItem(at: imagePath)
                        continue
                    }
                    
                    localPaths.append(imagePath.path)
                    self.logger.info("Bild erfolgreich lokal gespeichert: \(imagePath.path)")
                } catch {
                    self.logger.error("Fehler beim Speichern des Bildes \(index): \(error.localizedDescription)")
                    continue
                }
            }
        } catch {
            throw FirebaseError.storageError("Fehler beim Erstellen des Bildverzeichnisses: \(error.localizedDescription)")
        }
        
        guard !localPaths.isEmpty else {
            throw FirebaseError.storageError("Keine Bilder konnten gespeichert werden")
        }
        
        return localPaths
    }
    
    private let uploadSemaphore = DispatchSemaphore(value: 1)
    
    private func uploadImagesToCloud(_ localPaths: [String], for entryId: String) async throws -> [String] {
        var cloudUrls: [String] = []
        
        for path in localPaths {
            let fileManager = FileManager.default
            let imageUrl = URL(fileURLWithPath: path)
            
            guard fileManager.fileExists(atPath: path),
                  let imageData = try? Data(contentsOf: imageUrl),
                  !imageData.isEmpty,
                  UIImage(data: imageData) != nil else {
                throw FirebaseError.storageError("Ungültige oder fehlende Bilddatei: \(path)")
            }
            
            let filename = imageUrl.lastPathComponent
            let sanitizedEntryId = entryId.replacingOccurrences(of: "/", with: "_")
            
            guard let userId = Auth.auth().currentUser?.uid else {
                throw FirebaseError.storageError("Kein authentifizierter Benutzer")
            }
            
            // Erstelle Storage-Referenz
            let storage = Storage.storage()
            let storageRef = storage.reference()
            
            // Vereinfachte Verzeichnisstruktur
            let imagePath = "journal_images/\(userId)/\(sanitizedEntryId)/\(filename)"
            let imageRef = storageRef.child(imagePath)
            
            // Erstelle Metadata
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            metadata.customMetadata = [
                "uploadDate": ISO8601DateFormatter().string(from: Date()),
                "entryId": entryId,
                "userId": userId
            ]
            
            do {
                // Direkter Upload mit Fortschrittsüberwachung
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    var retryCount = 0
                    let maxRetries = 3
                    var isCompleted = false
                    
                    func retryUpload() {
                        if isCompleted {
                            return
                        }
                        
                        if retryCount >= maxRetries {
                            isCompleted = true
                            continuation.resume(throwing: FirebaseError.storageError("Upload fehlgeschlagen nach \(maxRetries) Versuchen"))
                            return
                        }
                        
                        retryCount += 1
                        self.logger.info("Upload-Versuch \(retryCount) von \(maxRetries)")
                        
                        // Erstelle Upload-Task
                        let uploadTask = imageRef.putData(imageData, metadata: metadata)
                        
                        uploadTask.observe(.success) { _ in
                            if !isCompleted {
                                isCompleted = true
                                uploadTask.removeAllObservers()
                                continuation.resume()
                            }
                        }
                        
                        uploadTask.observe(.failure) { snapshot in
                            if isCompleted {
                                return
                            }
                            
                            uploadTask.removeAllObservers()
                            
                            if let error = snapshot.error as NSError? {
                                self.logger.error("Upload-Fehler: \(error.localizedDescription)")
                                
                                // Spezifische Fehlerbehandlung
                                if error.domain == StorageErrorDomain {
                                    switch error.code {
                                    case StorageErrorCode.retryLimitExceeded.rawValue,
                                         StorageErrorCode.quotaExceeded.rawValue,
                                         StorageErrorCode.unauthenticated.rawValue:
                                        isCompleted = true
                                        continuation.resume(throwing: error)
                                        return
                                    default:
                                        // Exponentieller Backoff für Retry
                                        let delay = pow(2.0, Double(retryCount - 1))
                                        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                                            retryUpload()
                                        }
                                    }
                                } else {
                                    // Exponentieller Backoff für Retry
                                    let delay = pow(2.0, Double(retryCount - 1))
                                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                                        retryUpload()
                                    }
                                }
                            } else {
                                isCompleted = true
                                continuation.resume(throwing: FirebaseError.storageError("Unbekannter Upload-Fehler"))
                            }
                        }
                        
                        uploadTask.observe(.progress) { snapshot in
                            if !isCompleted, let progress = snapshot.progress {
                                let percentComplete = Double(progress.completedUnitCount) / Double(progress.totalUnitCount) * 100
                                self.logger.info("Upload-Fortschritt: \(Int(percentComplete))%")
                            }
                        }
                        
                        // Starte Upload
                        uploadTask.resume()
                    }
                    
                    // Starte den ersten Upload-Versuch
                    retryUpload()
                }
                
                // Nach erfolgreichem Upload, hole die Download-URL
                let downloadURL = try await imageRef.downloadURL()
                cloudUrls.append(downloadURL.absoluteString)
                self.logger.info("Bild erfolgreich hochgeladen: \(downloadURL.absoluteString)")
                
            } catch {
                self.logger.error("Fehler beim Upload: \(error.localizedDescription)")
                // Lösche bereits hochgeladene Bilder bei Fehler
                if !cloudUrls.isEmpty {
                    try? await deleteCloudImages(urls: cloudUrls)
                }
                throw error
            }
        }
        
        if cloudUrls.isEmpty {
            throw FirebaseError.storageError("Keine Bilder konnten hochgeladen werden")
        }
        
        return cloudUrls
    }
    
    func deleteCloudImages(urls: [String]) async throws {
        let storage = Storage.storage()
        
        for url in urls {
            do {
                guard let storageRef = try? storage.reference(forURL: url) else {
                    logger.warning("Ungültige Storage-Referenz für URL: \(url)")
                    continue
                }
                
                try await storageRef.delete()
                logger.info("Bild erfolgreich gelöscht: \(url)")
            } catch {
                logger.error("Fehler beim Löschen des Bildes: \(error.localizedDescription)")
            }
        }
    }
    
    private func addToPendingUploads(paths: [String], entryId: String) async {
        let pendingUploads = paths.map { PendingImageUpload(localPath: $0, entryId: entryId, createdAt: Date()) }
        
        if let data = try? JSONEncoder().encode(pendingUploads) {
            UserDefaults.standard.set(data, forKey: pendingUploadsKey)
        }
    }
    
    func processPendingUploads() async {
        guard NetworkMonitor.shared.isConnected,
              let data = UserDefaults.standard.data(forKey: pendingUploadsKey),
              let pendingUploads = try? JSONDecoder().decode([PendingImageUpload].self, from: data) else {
            return
        }
        
        for upload in pendingUploads {
            do {
                let urls = try await uploadImagesToCloud([upload.localPath], for: upload.entryId)
                if let entry = try? await getJournalEntry(withId: upload.entryId) {
                    var updatedEntry = entry
                    updatedEntry.imageURLs = (updatedEntry.imageURLs ?? []) + urls
                    updatedEntry.localImagePaths = []
                    try? await saveJournalEntry(updatedEntry)
                }
            } catch {
                logger.error("Fehler beim Verarbeiten ausstehender Uploads: \(error.localizedDescription)")
            }
        }
        
        // Lösche verarbeitete Uploads
        UserDefaults.standard.removeObject(forKey: pendingUploadsKey)
    }
    
    private struct ProcessedImage {
        let data: Data
        let size: CGSize
    }
    
    func getJournalEntry(withId id: String) async throws -> JournalEntry? {
        let document = try await db.collection("journalEntries").document(id).getDocument()
        guard let data = document.data() else { return nil }
        
        // Extract timestamps
        guard let dateTimestamp = data["date"] as? Timestamp,
              let lastModifiedTimestamp = data["lastModified"] as? Timestamp,
              let userId = data["userId"] as? String,
              let gratitude = data["gratitude"] as? String,
              let highlight = data["highlight"] as? String,
              let learning = data["learning"] as? String,
              let syncStatusRaw = data["syncStatus"] as? String,
              let syncStatus = SyncStatus(rawValue: syncStatusRaw) else {
            return nil
        }
        
        // Extract optional fields
        let imageURLs = data["imageURLs"] as? [String]
        let localImagePaths = data["localImagePaths"] as? [String]
        let title = data["title"] as? String
        let content = data["content"] as? String
        let location = data["location"] as? String
        
        return JournalEntry(
            id: document.documentID,
            userId: userId,
            date: dateTimestamp.dateValue(),
            gratitude: gratitude,
            highlight: highlight,
            learning: learning,
            lastModified: lastModifiedTimestamp.dateValue(),
            syncStatus: syncStatus,
            title: title,
            content: content,
            location: location,
            imageURLs: imageURLs,
            localImagePaths: localImagePaths
        )
    }
    
    // MARK: - Error Types
    
    enum FirebaseError: LocalizedError {
        case invalidData(String)
        case saveFailed(String)
        case fetchFailed(String)
        case syncFailed(String)
        case storageError(String)
        case resourceExhausted
        
        var errorDescription: String? {
            switch self {
            case .invalidData(let message),
                 .saveFailed(let message),
                 .fetchFailed(let message),
                 .syncFailed(let message),
                 .storageError(let message):
                return message
            case .resourceExhausted:
                return "Resource exhausted"
            }
        }
    }
} 
