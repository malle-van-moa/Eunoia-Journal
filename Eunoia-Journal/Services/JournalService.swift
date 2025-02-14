import Foundation
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth
import Combine
import JournalingSuggestions
import OSLog
import FirebaseStorage
import UIKit
import PhotosUI

@available(iOS 17.0, *)
class JournalService {
    static let shared = JournalService()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Eunoia", category: "JournalService")
    
    private let db = Firestore.firestore()
    private let coreDataManager = CoreDataManager.shared
    
    private init() {}
    
    // MARK: - Journal Entries
    
    func saveJournalEntry(_ entry: JournalEntry) async throws {
        guard let id = entry.id else {
            throw FirebaseError.invalidData("Entry ID is missing")
        }
        
        var dict: [String: Any] = [
            "userId": entry.userId,
            "date": Timestamp(date: entry.date),
            "gratitude": entry.gratitude,
            "highlight": entry.highlight,
            "learning": entry.learning,
            "lastModified": Timestamp(date: entry.lastModified),
            "syncStatus": entry.syncStatus.rawValue
        ]
        
        // Add optional fields
        if let title = entry.title {
            dict["title"] = title
        }
        if let content = entry.content {
            dict["content"] = content
        }
        if let location = entry.location {
            dict["location"] = location
        }
        if let learningNugget = entry.learningNugget {
            let nuggetDict: [String: Any] = [
                "category": learningNugget.category.rawValue,
                "content": learningNugget.content,
                "isAddedToJournal": learningNugget.isAddedToJournal
            ]
            dict["learningNugget"] = nuggetDict
        }
        
        // Add server timestamp
        dict["serverTimestamp"] = FieldValue.serverTimestamp()
        
        do {
            try await db.collection("journalEntries").document(id).setData(dict)
            
            // Update local entry status to synced
            var updatedEntry = entry
            updatedEntry.syncStatus = .synced
            coreDataManager.saveJournalEntry(updatedEntry)
        } catch {
            throw FirebaseError.saveFailed("Failed to save entry: \(error.localizedDescription)")
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
                            category: category,
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
                                category: category,
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
                            category: category,
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
    
    @available(iOS 17.2, *)
    func createEntryFromSuggestion(_ suggestion: JournalingSuggestion) async throws -> JournalEntry {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw FirebaseError.invalidData("User ID ist nicht verfügbar")
        }
        
        // Versuche den aktuellen Standort zu erhalten
        var locationString: String? = nil
        do {
            locationString = try await LocationManager.shared.getCurrentLocationString()
        } catch {
            logger.error("Fehler beim Abrufen des Standorts: \(error.localizedDescription)")
        }
        
        // Erstelle einen neuen Eintrag mit den verfügbaren Informationen
        let entry = JournalEntry(
            id: UUID().uuidString,
            userId: userId,
            date: Date(),
            gratitude: "",
            highlight: suggestion.title,
            learning: "",
            title: suggestion.title,
            content: suggestion.title,
            location: locationString,
            imageURLs: nil
        )
        
        try await saveJournalEntry(entry)
        return entry
    }
    
    func saveJournalEntryWithImages(_ entry: JournalEntry, images: [UIImage]) async throws -> JournalEntry {
        var imageURLs: [String] = []
        
        // Konvertiere UIImages zu Data
        let imageDataArray = images.compactMap { image in
            image.jpegData(compressionQuality: 0.7)
        }
        
        // Lade Bilder hoch
        if !imageDataArray.isEmpty {
            imageURLs = try await uploadImages(imageDataArray)
        }
        
        // Erstelle aktualisiertes Entry mit Bild-URLs
        var updatedEntry = entry
        updatedEntry.imageURLs = imageURLs
        
        // Speichere Entry
        try await saveJournalEntry(updatedEntry)
        
        return updatedEntry
    }
    
    private func uploadImages(_ images: [Data]) async throws -> [String] {
        var urls: [String] = []
        let storage = Storage.storage()
        let storageRef = storage.reference()
        
        for (index, imageData) in images.enumerated() {
            let imagePath = "journal_images/\(UUID().uuidString)_\(index).jpg"
            let imageRef = storageRef.child(imagePath)
            
            _ = try await imageRef.putDataAsync(imageData)
            let downloadURL = try await imageRef.downloadURL()
            urls.append(downloadURL.absoluteString)
        }
        
        return urls
    }
    
    func deleteImages(urls: [String]) async throws {
        let storage = Storage.storage()
        
        for url in urls {
            guard let storageRef = try? storage.reference(forURL: url) else { continue }
            try await storageRef.delete()
        }
    }
    
    // MARK: - Error Types
    
    enum FirebaseError: LocalizedError {
        case invalidData(String)
        case saveFailed(String)
        case fetchFailed(String)
        case syncFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidData(let message),
                 .saveFailed(let message),
                 .fetchFailed(let message),
                 .syncFailed(let message):
                return message
            }
        }
    }
} 