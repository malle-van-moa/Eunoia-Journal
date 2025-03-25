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

// MARK: - Helper Structures
private struct ProcessedImage {
    let data: Data
    let size: CGSize
    let filename: String
}

// Verwende die ImageUploadResult Struktur aus ImageService
private typealias ImageUploadResult = ImageService.ImageUploadResult

@available(iOS 17.0, *)
class JournalService {
    static let shared = JournalService()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Eunoia", category: "JournalService")
    private let networkMonitor = NetworkMonitor.shared
    private let db: Firestore
    private let coreDataManager = CoreDataManager.shared
    private let imageService = ImageService.shared
    private var retryCount = 0
    private let maxRetries = 3
    private let pendingUploadsKey = "pendingImageUploads"
    private let storageManager = StorageManager.shared
    
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
            
            // WICHTIG: Speichere auch lokale Pfade
            if let localImagePaths = entry.localImagePaths, !localImagePaths.isEmpty { dict["localImagePaths"] = localImagePaths }
            
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
                    
                    // Extrahiere Bild-URLs und lokale Pfade
                    let imageURLs = data["imageURLs"] as? [String]
                    let localImagePaths = data["localImagePaths"] as? [String]
                    
                    if localImagePaths != nil {
                        self.logger.debug("Gefundene lokale Bildpfade für Eintrag \(document.documentID): \(String(describing: localImagePaths))")
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
                        serverTimestamp: serverTimestamp,
                        imageURLs: imageURLs,
                        localImagePaths: localImagePaths
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
                        
                        // Extrahiere Bild-URLs und lokale Pfade
                        let imageURLs = data["imageURLs"] as? [String]
                        let localImagePaths = data["localImagePaths"] as? [String]
                        
                        if localImagePaths != nil {
                            self.logger.debug("Gefundene lokale Bildpfade für Eintrag \(documentId): \(String(describing: localImagePaths))")
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
                            serverTimestamp: serverTimestamp,
                            title: data["title"] as? String,
                            content: data["content"] as? String,
                            location: data["location"] as? String,
                            imageURLs: imageURLs,
                            localImagePaths: localImagePaths
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
                    
                    // Extrahiere Bild-URLs und lokale Pfade
                    let imageURLs = data["imageURLs"] as? [String]
                    let localImagePaths = data["localImagePaths"] as? [String]
                    
                    if localImagePaths != nil {
                        self.logger.debug("Gefundene lokale Bildpfade für Eintrag \(documentId): \(String(describing: localImagePaths))")
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
                        serverTimestamp: serverTimestamp,
                        title: data["title"] as? String,
                        content: data["content"] as? String,
                        location: data["location"] as? String,
                        imageURLs: imageURLs,
                        localImagePaths: localImagePaths
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
        
        // Erstelle einen neuen Eintrag mit sicherer Optional-Behandlung
        let defaultTitle = "Neuer Eintrag"
        let entryTitle = suggestion.title
        
        let entry = JournalEntry(
            id: UUID().uuidString,
            userId: userId,
            date: Date(),
            gratitude: "",
            highlight: entryTitle,
            learning: "",
            learningNugget: nil,
            lastModified: Date(),
            syncStatus: .pendingUpload,
            title: entryTitle,
            content: entryTitle,
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
                throw FirebaseError.storageError("Fehler bei der Bildkomprimierung")
            }
            scaledImage = resizedImage
        } else {
            scaledImage = image
        }
        
        // Komprimiere das Bild
        guard let imageData = scaledImage.jpegData(compressionQuality: Constants.compressionQuality),
              !imageData.isEmpty,
              imageData.count <= Constants.maxFileSize else {
            throw FirebaseError.storageError("Fehler bei der Bildkomprimierung")
        }
        
        return ProcessedImage(data: imageData, size: scaledImage.size, filename: filename)
    }
    
    // MARK: - Local Storage
    func saveImageLocally(_ image: UIImage, entryId: String) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.7) else {
            throw FirebaseError.storageError("Fehler beim Komprimieren des Bildes")
        }
        
        do {
            // Erstelle einen eindeutigen Dateinamen
            let uniqueID = UUID().uuidString
            let filename = "journal_image_\(entryId)_\(uniqueID).jpg"
            
            // Verwende das Documents-Verzeichnis für persistente Speicherung
            guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw FirebaseError.storageError("Konnte kein Documents-Verzeichnis finden")
            }
            
            // Erstelle ein dediziertes Verzeichnis für Journal-Bilder
            let imagesDirectory = documentsDirectory.appendingPathComponent("JournalImages", isDirectory: true)
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true, attributes: nil)
            
            // Erstelle den vollständigen Datei-URL
            let fileURL = imagesDirectory.appendingPathComponent(filename)
            
            // Schreibe die Daten atomar in die Datei
            try data.write(to: fileURL, options: [.atomic])
            
            // Extrahiere den Pfad sicher
            let filePath = fileURL.path
            logger.debug("Bild erfolgreich lokal gespeichert unter: \(filePath)")
            
            // Wir speichern nur den relativen Pfad ab Documents-Verzeichnis
            // Dies macht den Pfad portabler zwischen App-Neustarts
            let relativePath = "JournalImages/\(filename)"
            logger.debug("Relativer Pfad für Speicherung: \(relativePath)")
            
            return relativePath
        } catch {
            logger.error("Fehler beim lokalen Speichern des Bildes: \(error.localizedDescription)")
            throw FirebaseError.storageError("Fehler beim lokalen Speichern: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Cloud Storage
    private func uploadImageToCloud(_ image: UIImage, entryId: String) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.7) else {
            throw FirebaseError.storageError("Fehler beim Komprimieren des Bildes")
        }
        
        let uniqueID = UUID().uuidString
        let filename = "journal_image_\(entryId)_\(uniqueID).jpg"
        
        do {
            // Versuche zuerst den Upload mit dem neuen Pfad
            return try await storageManager.uploadImage(data: data, path: "journal_images", filename: filename)
        } catch {
            logger.error("Fehler beim Cloud-Upload: \(error.localizedDescription)")
            
            // Wenn der Upload fehlschlägt, speichere den Upload für später
            if let storageError = error as? StorageError {
                switch storageError {
                case .uploadFailed(let message) where message.contains("permission"):
                    logger.warning("Berechtigungsfehler beim Upload - Speichere für späteren Upload")
                    throw FirebaseError.storageError("Berechtigungsfehler - Upload wird später wiederholt")
                case .networkError:
                    logger.warning("Netzwerkfehler beim Upload - Speichere für späteren Upload")
                    throw FirebaseError.storageError("Netzwerkfehler - Upload wird später wiederholt")
                case .quotaExceeded:
                    logger.error("Speicherplatz-Kontingent überschritten")
                    throw FirebaseError.storageError("Speicherplatz-Kontingent überschritten")
                default:
                    throw error
                }
            }
            throw error
        }
    }
    
    // MARK: - Image Management
    func saveJournalEntryWithImages(entry: JournalEntry, images: [UIImage]) async throws -> JournalEntry {
        logger.debug("[JournalService] Speichere Eintrag mit \(images.count) Bildern")
        
        // Sichere bestehende Bildpfade und URLs
        var localImagePaths = entry.localImagePaths ?? []
        var imageURLs = entry.imageURLs ?? []
        
        logger.debug("[JournalService] Bestehender Eintrag hat \(localImagePaths.count) lokale Pfade und \(imageURLs.count) URLs")
        
        // Zähle, wie viele neue Bilder verarbeitet werden
        var newImagesSaved = 0
        var newImagesUploaded = 0
        
        // Verarbeite die neuen Bilder
        for (index, image) in images.enumerated() {
            do {
                guard let entryId = entry.id else {
                    throw NSError(domain: "JournalService", code: 1001, userInfo: [
                        NSLocalizedDescriptionKey: "Keine Entry-ID gefunden für die Bildspeicherung"
                    ])
                }
                
                // Speichere das Bild lokal
                let localPath = try await imageService.saveImageLocally(image, entryId: entryId)
                
                // Prüfe auf Duplikate im lokalen Pfad
                if !localImagePaths.contains(localPath) {
                    localImagePaths.append(localPath)
                    newImagesSaved += 1
                    logger.debug("[JournalService] Bild \(index) lokal gespeichert: \(localPath)")
                } else {
                    logger.debug("[JournalService] Bild \(index) ist bereits lokal gespeichert: \(localPath)")
                }
                
                // Prüfe, ob das Gerät online ist
                if networkMonitor.isConnected {
                    // Lade das Bild hoch, wenn wir online sind
                    let imageURL = try await imageService.uploadImage(image, entryId: entryId)
                    
                    // Prüfe auf Duplikate in der URL
                    if !imageURLs.contains(imageURL) {
                        imageURLs.append(imageURL)
                        newImagesUploaded += 1
                        logger.debug("[JournalService] Bild \(index) hochgeladen: \(imageURL)")
                    } else {
                        logger.debug("[JournalService] Bild \(index) ist bereits hochgeladen: \(imageURL)")
                    }
                } else {
                    logger.debug("[JournalService] Gerät ist offline - Bild \(index) wird später hochgeladen")
                }
            } catch {
                // Bei einem Fehler loggen wir diesen, werfen ihn aber nicht weiter
                logger.error("[JournalService] Fehler beim Verarbeiten von Bild \(index): \(error.localizedDescription)")
                
                if error.localizedDescription.contains("network") || !networkMonitor.isConnected {
                    // Bei Netzwerkfehlern ändern wir den Status auf pendingUpload
                    logger.debug("[JournalService] Netzwerkfehler erkannt, markiere für späteren Upload")
                }
            }
        }
        
        logger.debug("[JournalService] Gesamt verarbeitet: \(newImagesSaved) neue lokal gespeicherte Bilder, \(newImagesUploaded) neue hochgeladene Bilder")
        
        // Eindeutige Pfade und URLs durch Verwendung von Sets sicherstellen
        let uniqueLocalPaths = Array(Set(localImagePaths))
        let uniqueImageURLs = Array(Set(imageURLs))
        
        logger.debug("[JournalService] Nach Entfernung von Duplikaten: \(uniqueLocalPaths.count) lokale Pfade, \(uniqueImageURLs.count) URLs")
        
        // Aktualisiere den Eintrag mit den neuen Bildpfaden und URLs
        let updatedEntry = JournalEntry(
            id: entry.id,
            userId: entry.userId,
            date: entry.date,
            gratitude: entry.gratitude,
            highlight: entry.highlight,
            learning: entry.learning,
            learningNugget: entry.learningNugget,
            lastModified: Date(),
            syncStatus: networkMonitor.isConnected && imageURLs.count == images.count + (entry.imageURLs?.count ?? 0) ? .synced : .pendingUpload,
            title: entry.title,
            content: entry.content,
            location: entry.location,
            imageURLs: uniqueImageURLs,
            localImagePaths: uniqueLocalPaths,
            images: entry.images
        )
        
        // Speichere den Eintrag in CoreData
        try coreDataManager.saveJournalEntry(updatedEntry)
        logger.debug("[JournalService] Eintrag in CoreData gespeichert mit \(uniqueLocalPaths.count) lokalen Pfaden und \(uniqueImageURLs.count) URLs")
        
        return updatedEntry
    }
    
    func deleteCloudImages(urls: [String]) async throws {
        try await imageService.deleteImages(urls: urls)
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
                // Prüfe auf leere Strings
                guard !upload.localPath.isEmpty,
                      !upload.entryId.isEmpty,
                      let imageData = try? Data(contentsOf: URL(fileURLWithPath: upload.localPath)),
                      let image = UIImage(data: imageData) else {
                    continue
                }
                
                let filename = URL(fileURLWithPath: upload.localPath).lastPathComponent
                let processedImage = try processImage(image, filename: filename)
                
                // Verwende die imageService.uploadImage Methode mit korrekter Fehlerbehandlung
                let uploadResult = try await imageService.uploadImage(image, path: "journal_entries", userId: upload.entryId)
                
                if uploadResult.isSuccess {
                    let url = uploadResult.url ?? ""
                    if !url.isEmpty {
                        if let entry = try? await getJournalEntry(withId: upload.entryId) {
                            var updatedEntry = entry
                            let currentUrls = updatedEntry.imageURLs ?? []
                            updatedEntry.imageURLs = currentUrls + [url]
                            updatedEntry.syncStatus = .synced
                            try? await saveJournalEntry(updatedEntry)
                        }
                    } else {
                        logger.warning("Upload erfolgreich, aber keine URL erhalten")
                    }
                } else {
                    logger.error("Fehler beim Cloud-Upload: \(uploadResult.error?.localizedDescription ?? "Unbekannter Fehler")")
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
    
    // MARK: - Diagnostic Methods
    
    /// Führt eine Diagnose der Firebase Storage-Konfiguration durch
    func runStorageDiagnostics() {
        logger.info("Starte Storage-Diagnose...")
        storageManager.printStorageDiagnostics()
    }
    
    // MARK: - Error Types
    
    enum FirebaseError: LocalizedError {
        case invalidData(String)
        case saveFailed(String)
        case fetchFailed(String)
        case syncFailed(String)
        case storageError(String)
        case resourceExhausted
        case databaseError
        
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
            case .databaseError:
                return "Database error"
            }
        }
    }
    
    func uploadImage(_ image: UIImage) async throws -> String? {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw FirebaseError.storageError("Konnte Bild nicht komprimieren")
        }
        
        let imageName = "\(UUID().uuidString).jpg"
        let storageRef = Storage.storage().reference().child("journal_images/\(imageName)")
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
        let downloadURL = try await storageRef.downloadURL()
        
        return downloadURL.absoluteString
    }
} 
