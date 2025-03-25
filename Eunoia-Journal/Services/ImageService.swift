import Foundation
import FirebaseStorage
import UIKit
import OSLog
import FirebaseAuth

class ImageService {
    static let shared = ImageService()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Eunoia", category: "ImageService")
    private let storage = Storage.storage()
    
    // MARK: - Constants
    private struct Constants {
        static let maxImageDimension: CGFloat = 2048.0
        static let compressionQuality: CGFloat = 0.7
        static let maxFileSize: Int64 = 5 * 1024 * 1024 // 5MB
    }
    
    private init() {}
    
    // MARK: - Image Processing
    private func processImage(_ image: UIImage) throws -> Data {
        // Skaliere das Bild wenn nötig
        let scaledImage: UIImage
        if image.size.width > Constants.maxImageDimension || image.size.height > Constants.maxImageDimension {
            let scale = Constants.maxImageDimension / max(image.size.width, image.size.height)
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            defer { UIGraphicsEndImageContext() }
            
            image.draw(in: CGRect(origin: .zero, size: newSize))
            guard let resizedImage = UIGraphicsGetImageFromCurrentImageContext() else {
                throw ImageError.processingFailed("Fehler bei der Bildskalierung")
            }
            scaledImage = resizedImage
        } else {
            scaledImage = image
        }
        
        // Komprimiere das Bild
        guard let imageData = scaledImage.jpegData(compressionQuality: Constants.compressionQuality),
              !imageData.isEmpty,
              imageData.count <= Constants.maxFileSize else {
            throw ImageError.processingFailed("Fehler bei der Bildkomprimierung")
        }
        
        return imageData
    }
    
    // MARK: - Result Types
    struct ImageUploadResult {
        let isSuccess: Bool
        let url: String
        let error: Error?
        let metadata: [String: String]
        
        init(url: String, metadata: [String: String], error: Error? = nil) {
            self.isSuccess = error == nil
            self.url = url
            self.error = error
            self.metadata = metadata
        }
    }
    
    // MARK: - Cloud Storage
    /// Lädt ein Bild in die Cloud hoch und gibt das Ergebnis mit URL und Metadaten zurück.
    /// - Parameters:
    ///   - image: Das hochzuladende Bild
    ///   - path: Der Pfad im Storage
    ///   - userId: Die ID des Benutzers
    /// - Returns: Ein ImageUploadResult mit URL und Metadaten
    func uploadImage(_ image: UIImage, path: String, userId: String) async throws -> ImageUploadResult {
        let imageData = try processImage(image)
        let imageName = "\(UUID().uuidString).jpg"
        let storageRef = storage.reference().child("\(path)/\(imageName)")
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        metadata.customMetadata = [
            "userId": userId,
            "width": String(Int(image.size.width)),
            "height": String(Int(image.size.height))
        ]
        
        do {
            _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
            let downloadURL = try await storageRef.downloadURL()
            
            return ImageUploadResult(
                url: downloadURL.absoluteString,
                metadata: metadata.customMetadata ?? [:],
                error: nil
            )
        } catch {
            return ImageUploadResult(
                url: "",
                metadata: [:],
                error: error
            )
        }
    }
    
    /// Lädt ein Bild in die Cloud hoch und gibt die URL zurück.
    /// - Parameters:
    ///   - image: Das hochzuladende Bild
    ///   - entryId: Die ID des zugehörigen Journal-Eintrags
    ///   - path: Optionaler Pfad im Storage (Standard: "journal_images")
    /// - Returns: Die URL des hochgeladenen Bildes
    func uploadImage(_ image: UIImage, entryId: String, path: String = "journal_images") async throws -> String {
        // Bild komprimieren
        guard let imageData = compressImage(image) else {
            throw ImageError.compressionError("Bild konnte nicht komprimiert werden")
        }
        
        // Eindeutigen Dateinamen erstellen
        let uuid = UUID().uuidString
        let fileName = "journal_image_\(entryId)_\(uuid).jpg"
        
        // Prüfen, ob ein Benutzer angemeldet ist
        guard let userId = Auth.auth().currentUser?.uid else {
            throw ImageError.storageFailed("Kein angemeldeter Benutzer")
        }
        
        // Bild in Firebase Storage hochladen
        let storageRef = storage.reference().child("\(path)/\(userId)/\(entryId)/\(fileName)")
        
        // Metadaten setzen
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        metadata.customMetadata = [
            "userId": userId,
            "entryId": entryId,
            "uploadDate": ISO8601DateFormatter().string(from: Date()),
            "width": String(Int(image.size.width)),
            "height": String(Int(image.size.height))
        ]
        
        do {
            // Bild hochladen
            _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
            
            // Download-URL abrufen
            let downloadURL = try await storageRef.downloadURL()
            
            logger.debug("[ImageService] Bild erfolgreich hochgeladen: \(downloadURL.absoluteString)")
            
            return downloadURL.absoluteString
        } catch {
            logger.error("[ImageService] Fehler beim Hochladen des Bildes: \(error.localizedDescription)")
            throw ImageError.storageFailed("Hochladen fehlgeschlagen: \(error.localizedDescription)")
        }
    }
    
    func deleteImage(url: String) async throws {
        guard let storageRef = try? storage.reference(forURL: url) else {
            throw ImageError.invalidURL
        }
        
        try await storageRef.delete()
    }
    
    func deleteImages(urls: [String]) async throws {
        for url in urls {
            try await deleteImage(url: url)
        }
    }
    
    // MARK: - Local Storage
    func saveImageLocally(_ image: UIImage, entryId: String) async throws -> String {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw ImageError.fileSystemError("Dokumentenverzeichnis nicht gefunden")
        }
        
        let journalImagesDirectory = documentsDirectory.appendingPathComponent("JournalImages")
        
        // Eindeutige IDs für Dateien generieren
        let uuid = UUID().uuidString
        let timestamp = Int(Date().timeIntervalSince1970)
        
        // Sicherer Dateiname ohne Sonderzeichen
        let safeEntryId = entryId.replacingOccurrences(of: "-", with: "")
                                 .replacingOccurrences(of: " ", with: "_")
        let fileName = "journal_\(safeEntryId)_\(timestamp)_\(uuid).jpg"
        
        do {
            // Sicherstellen, dass das Verzeichnis existiert
            if !FileManager.default.fileExists(atPath: journalImagesDirectory.path) {
                try FileManager.default.createDirectory(at: journalImagesDirectory, 
                                                      withIntermediateDirectories: true, 
                                                      attributes: nil)
            }
            
            // Sicherer Dateiname, z.B. ohne Sonderzeichen
            let fileURL = journalImagesDirectory.appendingPathComponent(fileName)
            
            // Komprimiere das Bild mit der sicheren Methode
            guard let imageData = await compressImageSafelyAsync(image) else {
                throw ImageError.compressionError("Bild konnte nicht komprimiert werden")
            }
            
            // Verwende den temporären Speicher für zwischenzeitliches Schreiben
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_img_\(uuid).jpg")
            
            // Schreibe in temporäre Datei mit atomarer Operation
            try imageData.write(to: tempURL, options: [.atomic])
            
            // Versuche die Datei zu verschieben, was in der Regel effizienter ist als Kopieren
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            
            try FileManager.default.moveItem(at: tempURL, to: fileURL)
            
            // Verifiziere die Dateierstellung
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw ImageError.fileSystemError("Datei konnte nicht erstellt werden")
            }
            
            logger.debug("Bild erfolgreich gespeichert unter: \(fileURL.path)")
            
            // Vom iCloud-Backup ausschließen (nicht kritisch)
            do {
                var resourceValues = URLResourceValues()
                resourceValues.isExcludedFromBackup = true
                var mutableURL = fileURL
                try mutableURL.setResourceValues(resourceValues)
            } catch {
                logger.warning("Konnte Datei nicht vom Backup ausschließen: \(error.localizedDescription)")
            }
            
            return "JournalImages/\(fileName)"
        } catch {
            logger.error("Fehler beim Speichern des Bildes: \(error.localizedDescription)")
            throw ImageError.fileSystemError("Bild konnte nicht gespeichert werden: \(error.localizedDescription)")
        }
    }
    
    // Erweiterte asynchrone Version der Bildkomprimierung
    private func compressImageSafelyAsync(_ image: UIImage) async -> Data? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let data = self.compressImageSafely(image)
                continuation.resume(returning: data)
            }
        }
    }
    
    /// Komprimiert ein Bild auf maximal 5 MB und gibt die Daten zurück
    func compressImage(_ image: UIImage) -> Data? {
        logger.debug("[ImageService] Komprimiere Bild: \(image)")
        
        return compressImageSafely(image)
    }
    
    /// Komprimiert ein Bild sicher mit Prüfung auf ungültige Werte
    private func compressImageSafely(_ image: UIImage) -> Data? {
        // Prüfe auf ungültige Bilddimensionen
        guard image.size.width > 0, image.size.height > 0,
              !image.size.width.isNaN, !image.size.height.isNaN else {
            logger.error("[ImageService] Ungültige Bilddimensionen: \(String(describing: image.size)), verwende Standardqualität")
            return image.jpegData(compressionQuality: 0.5) // Fallback mit mittlerer Qualität
        }
        
        let maxSize: CGFloat = 2048 // Maximale Größe in Pixeln
        var scaleFactor: CGFloat = 1.0
        
        // Berechne Skalierungsfaktor für große Bilder
        if image.size.width > maxSize || image.size.height > maxSize {
            if image.size.width > image.size.height {
                scaleFactor = maxSize / image.size.width
            } else {
                scaleFactor = maxSize / image.size.height
            }
        }
        
        // Validiere den Skalierungsfaktor
        if !(scaleFactor > 0 && scaleFactor.isFinite) {
            logger.error("[ImageService] Ungültiger Skalierungsfaktor: \(scaleFactor), verwende Originalgroße")
            scaleFactor = 1.0
        }
        
        // Berechne neue Dimensionen
        let newWidth = image.size.width * scaleFactor
        let newHeight = image.size.height * scaleFactor
        
        // Validiere die neuen Dimensionen
        guard newWidth > 0, newHeight > 0, 
              newWidth.isFinite, newHeight.isFinite else {
            logger.error("[ImageService] Ungültige neue Dimensionen: \(newWidth)x\(newHeight), verwende Standardqualität")
            return image.jpegData(compressionQuality: 0.5)
        }
        
        logger.debug("[ImageService] Skaliere Bild von \(String(describing: image.size)) zu \(String(format: "%.1f", newWidth))x\(String(format: "%.1f", newHeight))")
        
        // Verwende einen autoreleasepool für besseres Speichermanagement
        return autoreleasepool { () -> Data? in
            // Setze neues Format und Größe
            let newSize = CGSize(width: newWidth, height: newHeight)
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            defer { UIGraphicsEndImageContext() }
            
            // Zeichne das Bild in der neuen Größe
            image.draw(in: CGRect(origin: .zero, size: newSize))
            
            // Erhalte das neue Bild
            guard let resizedImage = UIGraphicsGetImageFromCurrentImageContext() else {
                logger.error("[ImageService] Konnte kein skaliertes Bild erzeugen")
                return image.jpegData(compressionQuality: 0.5)
            }
            
            // Versuche verschiedene Kompressionsqualitäten
            let qualities: [CGFloat] = [0.9, 0.7, 0.5, 0.3]
            let maxFileSize: Int = 5 * 1024 * 1024 // 5 MB in Bytes
            
            for quality in qualities {
                if let data = resizedImage.jpegData(compressionQuality: quality) {
                    if data.count <= maxFileSize {
                        logger.debug("[ImageService] Bild komprimiert auf \(data.count) Bytes mit Qualität \(quality)")
                        return data
                    }
                }
            }
            
            // Wenn keine der Qualitätseinstellungen passt, verwende die niedrigste
            let finalData: Data? = resizedImage.jpegData(compressionQuality: 0.2)
            logger.debug("[ImageService] Bild mit niedrigster Qualität: \(finalData?.count ?? 0) Bytes")
            return finalData
        }
    }
    
    func loadImage(from path: String) async throws -> UIImage {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw ImageError.fileSystemError("Dokumentenverzeichnis nicht gefunden")
        }
        
        let fileURL = documentsDirectory.appendingPathComponent(path)
        
        do {
            // Direktes Lesen der Daten ohne NSFileCoordinator
            let imageData = try Data(contentsOf: fileURL)
            
            guard let image = UIImage(data: imageData) else {
                throw ImageError.decodingError("Bild konnte nicht dekodiert werden")
            }
            
            return image
        } catch {
            logger.error("Fehler beim Laden des Bildes: \(error.localizedDescription)")
            throw ImageError.fileSystemError("Bild konnte nicht geladen werden: \(error.localizedDescription)")
        }
    }
    
    func deleteLocalImage(at path: String) async throws {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw ImageError.fileSystemError("Dokumentenverzeichnis nicht gefunden")
        }
        
        let fileURL = documentsDirectory.appendingPathComponent(path)
        
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            logger.error("Fehler beim Löschen des Bildes: \(error.localizedDescription)")
            throw ImageError.fileSystemError("Bild konnte nicht gelöscht werden: \(error.localizedDescription)")
        }
    }
    
    func deleteLocalImages(paths: [String]) async throws {
        for path in paths {
            try await deleteLocalImage(at: path)
        }
    }
}

// MARK: - Error Types
extension ImageService {
    enum ImageError: LocalizedError {
        case processingFailed(String)
        case storageFailed(String)
        case invalidURL
        case fileSystemError(String)
        case compressionError(String)
        case decodingError(String)
        
        var errorDescription: String? {
            switch self {
            case .processingFailed(let message):
                return "Bildverarbeitung fehlgeschlagen: \(message)"
            case .storageFailed(let message):
                return "Speicherung fehlgeschlagen: \(message)"
            case .invalidURL:
                return "Ungültige Bild-URL"
            case .fileSystemError(let message):
                return "Dateisystemfehler: \(message)"
            case .compressionError(let message):
                return "Komprimierungsfehler: \(message)"
            case .decodingError(let message):
                return "Dekodierungsfehler: \(message)"
            }
        }
    }
} 