import Foundation
import Firebase
import FirebaseStorage
import FirebaseAuth
import UIKit
import OSLog

enum StorageError: Error, LocalizedError {
    case uploadFailed(String)
    case downloadFailed(String)
    case quotaExceeded
    case networkError
    case invalidLocalPath
    case fileSystemError(String)
    case processError(String)
    case saveError(String)
    
    var errorDescription: String? {
        switch self {
        case .uploadFailed(let message):
            return "Upload fehlgeschlagen: \(message)"
        case .downloadFailed(let message):
            return "Download fehlgeschlagen: \(message)"
        case .quotaExceeded:
            return "Speicherplatz-Kontingent überschritten"
        case .networkError:
            return "Netzwerkfehler beim Zugriff auf den Cloud-Speicher"
        case .invalidLocalPath:
            return "Ungültiger lokaler Pfad"
        case .fileSystemError(let message):
            return "Dateisystem-Fehler: \(message)"
        case .processError(let message):
            return "Fehler beim Verarbeiten des Bildes: \(message)"
        case .saveError(let message):
            return "Fehler beim Speichern: \(message)"
        }
    }
}

class StorageManager {
    private let storage = Storage.storage()
    private let logger = Logger(subsystem: "com.eunoia.journal", category: "StorageManager")
    
    // MARK: - Singleton
    
    static let shared = StorageManager()
    
    private init() {}
    
    // MARK: - Public Methods
    
    func uploadImage(data: Data, path: String, filename: String) async throws -> String {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw StorageError.uploadFailed("Kein authentifizierter Benutzer")
        }
        
        // Extrahiere die entryId aus dem Dateinamen
        // Beispiel: journal_image_entryID_uniqueID.jpg
        var entryId = "unknown"
        if let entryIdComponent = filename.split(separator: "_").dropFirst(2).first {
            entryId = String(entryIdComponent)
        }
        
        // Verwende den in den Firebase-Regeln definierten Pfad
        let imagePath = "journal_images/\(userId)/\(entryId)/\(filename)"
        
        // Log zur Fehlersuche
        logger.debug("Versuche Bild hochzuladen nach: \(imagePath)")
        
        let imageRef = storage.reference().child(imagePath)
        
        // Extrahiere Bildgröße für Metadaten
        var width = 0
        var height = 0
        if let image = UIImage(data: data) {
            width = Int(image.size.width)
            height = Int(image.size.height)
        }
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        metadata.customMetadata = [
            "uploadDate": ISO8601DateFormatter().string(from: Date()),
            "userId": userId,
            "entryId": entryId,
            "width": String(width),
            "height": String(height)
        ]
        
        do {
            _ = try await imageRef.putDataAsync(data, metadata: metadata)
            let downloadURL = try await imageRef.downloadURL()
            logger.info("Bild erfolgreich hochgeladen: \(downloadURL.absoluteString)")
            return downloadURL.absoluteString
        } catch let error as NSError {
            switch error.code {
            case StorageErrorCode.quotaExceeded.rawValue:
                throw StorageError.quotaExceeded
            case StorageErrorCode.retryLimitExceeded.rawValue:
                throw StorageError.networkError
            case StorageErrorCode.unauthorized.rawValue:
                logger.error("Berechtigungsfehler: \(error.localizedDescription)")
                throw StorageError.uploadFailed("Keine Berechtigung für den Zugriff auf den angegebenen Pfad. Bitte prüfe die Firebase Storage Regeln.")
            default:
                logger.error("Hochladefehler (\(error.code)): \(error.localizedDescription)")
                throw StorageError.uploadFailed(error.localizedDescription)
            }
        }
    }
    
    func deleteImage(url: String) async throws {
        guard let urlObj = URL(string: url) else {
            throw StorageError.invalidLocalPath
        }
        
        let pathReference = storage.reference(forURL: url)
        do {
            try await pathReference.delete()
        } catch {
            logger.error("Fehler beim Löschen des Bildes \(urlObj.lastPathComponent): \(error.localizedDescription)")
            throw StorageError.uploadFailed("Fehler beim Löschen: \(error.localizedDescription)")
        }
    }
    
    func deleteImages(urls: [String]) async throws {
        for url in urls {
            try await deleteImage(url: url)
        }
    }
    
    // MARK: - Diagnostic Methods
    
    /// Gibt Diagnostikdaten zur Firebase Storage-Konfiguration aus
    func printStorageDiagnostics() {
        let localLogger = self.logger
        let localStorage = self.storage
        
        localLogger.info("Firebase Storage Diagnostik:")
        localLogger.info("Storage Bucket: \(localStorage.app.options.storageBucket ?? "kein Bucket konfiguriert")")
        
        // Benutzer-Info
        let userId = Auth.auth().currentUser?.uid ?? "nicht angemeldet"
        localLogger.info("Aktueller Benutzer: \(userId)")
        localLogger.info("Firebase App: \(localStorage.app.name)")
        
        // Verwende eine lokale Task ohne Capture von self
        Task {
            do {
                let rootReference = localStorage.reference()
                localLogger.info("Root Reference: \(rootReference.fullPath)")
                
                // Versuche, die oberste Ebene zu listen
                do {
                    let result = try await rootReference.listAll()
                    localLogger.info("Root listbar mit \(result.prefixes.count) Präfixen und \(result.items.count) Elementen")
                    
                    if !result.prefixes.isEmpty {
                        let prefixPaths = result.prefixes.map { $0.fullPath }.joined(separator: ", ")
                        localLogger.info("Verfügbare Präfixe: \(prefixPaths)")
                    }
                } catch let listError {
                    localLogger.error("Kann Root nicht listen: \(listError.localizedDescription)")
                }
                
                // Versuche, das journal_images-Verzeichnis zu listen
                let journalImagesRef = localStorage.reference().child("journal_images")
                do {
                    let journalImagesResult = try await journalImagesRef.listAll()
                    localLogger.info("journal_images-Verzeichnis listbar mit \(journalImagesResult.prefixes.count) Präfixen")
                    
                    // Prüfe, ob das Benutzerverzeichnis vorhanden ist
                    if !userId.isEmpty && userId != "nicht angemeldet" {
                        let userRef = journalImagesRef.child(userId)
                        let userResult = try await userRef.listAll()
                        localLogger.info("Benutzerverzeichnis (\(userId)) listbar mit \(userResult.prefixes.count) Entry-Verzeichnissen")
                    }
                } catch let imageError {
                    localLogger.error("Kann journal_images-Verzeichnis nicht listen: \(imageError.localizedDescription)")
                }
                
                // Prüfe auch das alte images-Verzeichnis
                let imagesRef = localStorage.reference().child("images")
                do {
                    let imagesResult = try await imagesRef.listAll()
                    localLogger.info("Altes images-Verzeichnis listbar mit \(imagesResult.prefixes.count) Präfixen")
                } catch let imageError {
                    localLogger.error("Kann altes images-Verzeichnis nicht listen: \(imageError.localizedDescription)")
                }
                
                // Gib Informationen über Storage-Regeln aus
                localLogger.info("HINWEIS: Prüfe die storage.rules Datei und stelle sicher, dass sie folgende Struktur enthält:")
                localLogger.info("match /journal_images/{userId}/{entryId}/{imageFile} mit entsprechenden Berechtigungen")
                
            } catch {
                // Dieser Block fängt Fehler, die in der äußeren do-Anweisung auftreten könnten
                localLogger.error("Unerwarteter Fehler bei Storage-Diagnostik: \(error.localizedDescription)")
            }
        }
    }
} 