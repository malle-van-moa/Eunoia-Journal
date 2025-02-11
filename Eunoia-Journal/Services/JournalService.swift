import Foundation
import FirebaseCore
import FirebaseFirestore
import Combine

class JournalService {
    static let shared = JournalService()
    
    private let db = Firestore.firestore()
    private let coreDataManager = CoreDataManager.shared
    
    private init() {}
    
    // MARK: - Journal Entries
    
    func saveJournalEntry(_ entry: JournalEntry) async throws {
        guard let id = entry.id else {
            throw FirebaseError.invalidData("Entry ID is missing")
        }
        
        // Create the dictionary manually to avoid JSON encoding issues with Timestamps
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