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

// MARK: - Error Types
enum StorageError: LocalizedError {
    case invalidImage
    case compressionFailed
    case uploadFailed(String)
    case downloadFailed(String)
    case quotaExceeded
    case networkError
    case invalidLocalPath
    case fileSystemError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Ungültiges Bildformat"
        case .compressionFailed:
            return "Bildkomprimierung fehlgeschlagen"
        case .uploadFailed(let message):
            return "Upload fehlgeschlagen: \(message)"
        case .downloadFailed(let message):
            return "Download fehlgeschlagen: \(message)"
        case .quotaExceeded:
            return "Speicherplatz-Limit überschritten"
        case .networkError:
            return "Netzwerkfehler"
        case .invalidLocalPath:
            return "Ungültiger lokaler Pfad"
        case .fileSystemError(let message):
            return "Dateisystem-Fehler: \(message)"
        }
    }
}

// MARK: - Helper Structures
private struct ProcessedImage {
    let data: Data
    let size: CGSize
    let filename: String
}

private struct ImageUploadResult {
    let localPath: String
    let cloudURL: String?
    let error: Error?
}

@available(iOS 17.0, *)
class JournalService {
    static let shared = JournalService()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Eunoia", category: "JournalService")
    private let networkMonitor = NetworkMonitor.shared
    private let db: Firestore
    private let coreDataManager = CoreDataManager.shared
    private var retryCount = 0
    private let maxRetries = 3
    private let pendingUploadsKey = "pendingImageUploads"
    
    // MARK: - Constants
    private struct Constants {
        static let maxImageDimension: CGFloat = 2048.0
        static let compressionQuality: CGFloat = 0.7
        static let maxFileSize: Int64 = 5 * 1024 * 1024 // 5MB
        static let baseRetryDelay: TimeInterval = 1.0
    }
    
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
                    var learningNugget: LearningNugget? = nil
                    if let nuggetData = data["learningNugget"] as? [String: Any],
                       let title = nuggetData["title"] as? String,
                       let content = nuggetData["content"] as? String {
                        // Extrahiere die Kategorie oder verwende einen Standardwert
                        let categoryRaw = nuggetData["category"] as? String ?? LearningNugget.Category.aiGenerated.rawValue
                        let category = LearningNugget.Category(rawValue: categoryRaw) ?? .aiGenerated
                        
                        learningNugget = LearningNugget(
                            userId: userId,
                            category: category,
                            title: title,
                            content: content,
                            isAddedToJournal: nuggetData["isAddedToJournal"] as? Bool ?? true
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
                        let documentId = document.documentID
                        
                        // Extrahiere die erforderlichen Felder mit Fehlerbehandlung
                        guard let dateTimestamp = data["date"] as? Timestamp else {
                            print("⚠️ Fehlendes Datum in Dokument: \(documentId)")
                            return nil
                        }
                        
                        guard let userId = data["userId"] as? String else {
                            print("⚠️ Fehlende userId in Dokument: \(documentId)")
                            return nil
                        }
                        
                        // Verwende Standardwerte für optionale Felder
                        let gratitude = data["gratitude"] as? String ?? ""
                        let highlight = data["highlight"] as? String ?? ""
                        let learning = data["learning"] as? String ?? ""
                        
                        // Extrahiere den Sync-Status mit Standardwert
                        let syncStatus = (data["syncStatus"] as? String).flatMap { SyncStatus(rawValue: $0) } ?? .synced
                        
                        // Extrahiere den Server-Timestamp
                        let serverTimestamp = data["serverTimestamp"] as? Timestamp
                        
                        // Extrahiere den lastModified-Timestamp oder verwende das Datum
                        let lastModifiedTimestamp = data["lastModified"] as? Timestamp ?? dateTimestamp
                        
                        // Extrahiere das Learning Nugget, falls vorhanden
                        var learningNugget: LearningNugget? = nil
                        if let nuggetData = data["learningNugget"] as? [String: Any],
                           let content = nuggetData["content"] as? String {
                            // Extrahiere die Kategorie oder verwende einen Standardwert
                            let categoryRaw = nuggetData["category"] as? String ?? LearningNugget.Category.aiGenerated.rawValue
                            let category = LearningNugget.Category(rawValue: categoryRaw) ?? .aiGenerated
                            let title = nuggetData["title"] as? String ?? "Lernimpuls"
                            
                            learningNugget = LearningNugget(
                                userId: userId,
                                category: category,
                                title: title,
                                content: content,
                                isAddedToJournal: nuggetData["isAddedToJournal"] as? Bool ?? true
                            )
                        }
                        
                        // Erstelle den JournalEntry mit den extrahierten Daten
                        return JournalEntry(
                            id: documentId,
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
        
        // Erstelle eine Referenz auf den Listener, um ihn später entfernen zu können
        var listenerReference: ListenerRegistration?
        
        // Erstelle einen Listener, der automatisch entfernt wird, wenn das Subject abgebrochen wird
        let cancellable = subject
            .handleEvents(receiveCancel: {
                // Entferne den Listener, wenn das Subject abgebrochen wird
                listenerReference?.remove()
                print("🔄 Firestore-Listener für Journal-Einträge wurde entfernt")
            })
            .eraseToAnyPublisher()
        
        // Erstelle die Firestore-Abfrage
        let query = db.collection("journalEntries")
            .whereField("userId", isEqualTo: userId)
        
        // Füge den Listener hinzu mit verbesserter Fehlerbehandlung
        listenerReference = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            // Behandle Netzwerkfehler speziell
            if let error = error {
                let nsError = error as NSError
                
                // Prüfe, ob es sich um einen Netzwerkfehler handelt
                if nsError.domain == "FIRFirestoreErrorDomain" && 
                   (nsError.code == 8 || // Fehlercode für "Unavailable"
                    nsError.localizedDescription.contains("Network connectivity changed")) {
                    
                    print("📡 Netzwerkverbindung unterbrochen. Firestore-Listener wird pausiert.")
                    
                    // Sende keine Fehlermeldung, da dies ein erwartetes Verhalten ist
                    // Stattdessen versuchen wir, lokale Daten zu verwenden
                    do {
                        // Versuche, lokale Daten aus dem Cache zu laden
                        let localEntries = try self.coreDataManager.fetchJournalEntries(for: userId)
                        subject.send(localEntries)
                    } catch {
                        print("⚠️ Konnte keine lokalen Daten laden: \(error.localizedDescription)")
                    }
                    
                    return
                } else {
                    // Bei anderen Fehlern senden wir den Fehler an den Subscriber
                    print("❌ Firestore-Fehler: \(error.localizedDescription)")
                    subject.send(completion: .failure(error))
                    return
                }
            }
            
            guard let documents = snapshot?.documents else {
                subject.send([])
                return
            }
            
            do {
                let entries = try documents.compactMap { document -> JournalEntry? in
                    let data = document.data()
                    let documentId = document.documentID
                    
                    // Extrahiere die erforderlichen Felder mit Fehlerbehandlung
                    guard let dateTimestamp = data["date"] as? Timestamp else {
                        print("⚠️ Fehlendes Datum in Dokument: \(documentId)")
                        return nil
                    }
                    
                    guard let userId = data["userId"] as? String else {
                        print("⚠️ Fehlende userId in Dokument: \(documentId)")
                        return nil
                    }
                    
                    // Verwende Standardwerte für optionale Felder
                    let gratitude = data["gratitude"] as? String ?? ""
                    let highlight = data["highlight"] as? String ?? ""
                    let learning = data["learning"] as? String ?? ""
                    
                    // Extrahiere den Sync-Status mit Standardwert
                    let syncStatus = (data["syncStatus"] as? String).flatMap { SyncStatus(rawValue: $0) } ?? .synced
                    
                    // Extrahiere den Server-Timestamp
                    let serverTimestamp = data["serverTimestamp"] as? Timestamp
                    
                    // Extrahiere den lastModified-Timestamp oder verwende das Datum
                    let lastModifiedTimestamp = data["lastModified"] as? Timestamp ?? dateTimestamp
                    
                    // Extrahiere das Learning Nugget, falls vorhanden
                    var learningNugget: LearningNugget? = nil
                    if let nuggetData = data["learningNugget"] as? [String: Any],
                       let content = nuggetData["content"] as? String {
                        // Extrahiere die Kategorie oder verwende einen Standardwert
                        let categoryRaw = nuggetData["category"] as? String ?? LearningNugget.Category.aiGenerated.rawValue
                        let category = LearningNugget.Category(rawValue: categoryRaw) ?? .aiGenerated
                        let title = nuggetData["title"] as? String ?? "Lernimpuls"
                        
                        learningNugget = LearningNugget(
                            userId: userId,
                            category: category,
                            title: title,
                            content: content,
                            isAddedToJournal: nuggetData["isAddedToJournal"] as? Bool ?? true
                        )
                    }
                    
                    // Erstelle den JournalEntry mit den extrahierten Daten
                    return JournalEntry(
                        id: documentId,
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
                print("⚠️ Fehler beim Verarbeiten der Journal-Einträge: \(error.localizedDescription)")
                subject.send(completion: .failure(error))
            }
        }
        
        return cancellable
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
    
    // MARK: - Image Processing
    private func processImage(_ image: UIImage, filename: String) throws -> ProcessedImage {
        // Skaliere das Bild wenn nötig
        let scaledImage: UIImage
        if image.size.width > Constants.maxImageDimension || image.size.height > Constants.maxImageDimension {
            let scale = Constants.maxImageDimension / max(image.size.width, image.size.height)
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            defer { UIGraphicsEndImageContext() }
            
            image.draw(in: CGRect(origin: .zero, size: newSize))
            guard let resizedImage = UIGraphicsGetImageFromCurrentImageContext() else {
                throw StorageError.compressionFailed
            }
            scaledImage = resizedImage
        } else {
            scaledImage = image
        }
        
        // Komprimiere das Bild
        guard let imageData = scaledImage.jpegData(compressionQuality: Constants.compressionQuality),
              !imageData.isEmpty,
              imageData.count <= Constants.maxFileSize else {
            throw StorageError.compressionFailed
        }
        
        return ProcessedImage(data: imageData, size: scaledImage.size, filename: filename)
    }
    
    // MARK: - Local Storage
    private func saveImageLocally(_ processedImage: ProcessedImage, entryId: String) async throws -> String {
        let fileManager = FileManager.default
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw StorageError.fileSystemError("Dokumentenverzeichnis nicht verfügbar")
        }
        
        let sanitizedEntryId = entryId.replacingOccurrences(of: "/", with: "_")
        let journalImagesPath = documentsPath.appendingPathComponent("journal_images")
            .appendingPathComponent(sanitizedEntryId)
        
        do {
            try fileManager.createDirectory(at: journalImagesPath, withIntermediateDirectories: true, attributes: nil)
            let imagePath = journalImagesPath.appendingPathComponent(processedImage.filename)
            
            try processedImage.data.write(to: imagePath)
            
            // Validiere die geschriebene Datei
            guard let writtenData = try? Data(contentsOf: imagePath),
                  !writtenData.isEmpty,
                  UIImage(data: writtenData) != nil else {
                try? fileManager.removeItem(at: imagePath)
                throw StorageError.fileSystemError("Validierung der geschriebenen Datei fehlgeschlagen")
            }
            
            return imagePath.path
        } catch {
            throw StorageError.fileSystemError(error.localizedDescription)
        }
    }
    
    // MARK: - Cloud Storage
    private func uploadImageToCloud(_ processedImage: ProcessedImage, entryId: String) async throws -> String {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw StorageError.uploadFailed("Kein authentifizierter Benutzer")
        }
        
        let storage = Storage.storage()
        let sanitizedEntryId = entryId.replacingOccurrences(of: "/", with: "_")
        let imagePath = "journal_images/\(userId)/\(sanitizedEntryId)/\(processedImage.filename)"
        let imageRef = storage.reference().child(imagePath)
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        metadata.customMetadata = [
            "uploadDate": ISO8601DateFormatter().string(from: Date()),
            "entryId": entryId,
            "userId": userId,
            "width": String(format: "%.0f", processedImage.size.width),
            "height": String(format: "%.0f", processedImage.size.height)
        ]
        
        do {
            _ = try await imageRef.putDataAsync(processedImage.data, metadata: metadata)
            let downloadURL = try await imageRef.downloadURL()
            return downloadURL.absoluteString
        } catch let error as NSError {
            switch error.code {
            case StorageErrorCode.quotaExceeded.rawValue:
                throw StorageError.quotaExceeded
            case StorageErrorCode.retryLimitExceeded.rawValue:
                throw StorageError.networkError
            default:
                throw StorageError.uploadFailed(error.localizedDescription)
            }
        }
    }
    
    // MARK: - Image Management
    func saveJournalEntryWithImages(_ entry: JournalEntry, images: [UIImage]) async throws -> JournalEntry {
        guard let entryId = entry.id else {
            throw StorageError.uploadFailed("Entry ID fehlt")
        }
        
        var updatedEntry = entry
        var localPaths: [String] = []
        var cloudUrls: [String] = []
        var errors: [Error] = []
        
        // Verarbeite jedes Bild
        for (index, image) in images.enumerated() {
            do {
                let filename = "\(UUID().uuidString)_\(index).jpg"
                let processedImage = try processImage(image, filename: filename)
                
                // Speichere lokal
                let localPath = try await saveImageLocally(processedImage, entryId: entryId)
                localPaths.append(localPath)
                
                // Upload zur Cloud wenn online
                if NetworkMonitor.shared.isConnected {
                    let cloudUrl = try await uploadImageToCloud(processedImage, entryId: entryId)
                    cloudUrls.append(cloudUrl)
                }
            } catch {
                errors.append(error)
                logger.error("Fehler bei Bild \(index): \(error.localizedDescription)")
            }
        }
        
        // Aktualisiere den Entry basierend auf den Ergebnissen
        if !localPaths.isEmpty {
            updatedEntry.localImagePaths = localPaths
        }
        
        if !cloudUrls.isEmpty {
            updatedEntry.imageURLs = cloudUrls
            updatedEntry.syncStatus = .synced
        } else if NetworkMonitor.shared.isConnected {
            updatedEntry.syncStatus = .pendingUpload
            await addToPendingUploads(paths: localPaths, entryId: entryId)
        }
        
        // Speichere den aktualisierten Entry
        try await saveJournalEntry(updatedEntry)
        
        // Wenn es Fehler gab, aber einige Bilder erfolgreich waren, logge die Fehler
        if !errors.isEmpty {
            logger.error("Einige Bilder konnten nicht verarbeitet werden: \(errors.count) Fehler")
        }
        
        return updatedEntry
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
                throw StorageError.uploadFailed("Fehler beim Löschen: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Pending Uploads
    private struct PendingImageUpload: Codable {
        let localPath: String
        let entryId: String
        let createdAt: Date
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
                guard let imageData = try? Data(contentsOf: URL(fileURLWithPath: upload.localPath)),
                      let image = UIImage(data: imageData) else {
                    continue
                }
                
                let filename = URL(fileURLWithPath: upload.localPath).lastPathComponent
                let processedImage = try processImage(image, filename: filename)
                let cloudUrl = try await uploadImageToCloud(processedImage, entryId: upload.entryId)
                
                if let entry = try? await getJournalEntry(withId: upload.entryId) {
                    var updatedEntry = entry
                    updatedEntry.imageURLs = (updatedEntry.imageURLs ?? []) + [cloudUrl]
                    updatedEntry.syncStatus = .synced
                    try? await saveJournalEntry(updatedEntry)
                }
            } catch {
                logger.error("Fehler beim Verarbeiten ausstehender Uploads: \(error.localizedDescription)")
            }
        }
        
        UserDefaults.standard.removeObject(forKey: pendingUploadsKey)
    }
    
    private func getJournalEntry(withId id: String) async throws -> JournalEntry? {
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
