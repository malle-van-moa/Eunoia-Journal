import Foundation
import FirebaseFirestore

/// Repräsentiert die Zuordnung zwischen einem Benutzer und den von ihm gesehenen Learning Nuggets
struct UserNuggetRecord: Identifiable, Codable, Equatable {
    let id: String
    let userId: String
    let category: LearningNugget.Category
    var seenNuggetIds: [String]
    let lastUpdated: Date
    
    init(
        id: String = UUID().uuidString,
        userId: String,
        category: LearningNugget.Category,
        seenNuggetIds: [String] = [],
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.category = category
        self.seenNuggetIds = seenNuggetIds
        self.lastUpdated = lastUpdated
    }
    
    // MARK: - Firestore Conversion
    
    /// Konvertiert ein Firestore-Dokument in ein UserNuggetRecord
    /// - Parameter document: Das Firestore-Dokument
    /// - Returns: Ein UserNuggetRecord oder nil, wenn die Konvertierung fehlschlägt
    static func fromFirestore(_ document: DocumentSnapshot) -> UserNuggetRecord? {
        guard let data = document.data() else { return nil }
        
        guard let userId = data["user_id"] as? String,
              let categoryString = data["category"] as? String,
              let category = LearningNugget.Category(rawValue: categoryString),
              let seenNuggetIds = data["seen_nuggets"] as? [String],
              let lastUpdatedTimestamp = data["last_updated"] as? Timestamp else {
            return nil
        }
        
        return UserNuggetRecord(
            id: document.documentID,
            userId: userId,
            category: category,
            seenNuggetIds: seenNuggetIds,
            lastUpdated: lastUpdatedTimestamp.dateValue()
        )
    }
    
    /// Konvertiert das UserNuggetRecord in ein Dictionary für Firestore
    /// - Returns: Ein Dictionary mit den Daten des UserNuggetRecord
    func toFirestore() -> [String: Any] {
        return [
            "user_id": userId,
            "category": category.rawValue,
            "seen_nuggets": seenNuggetIds,
            "last_updated": FieldValue.serverTimestamp()
        ]
    }
    
    // MARK: - Helper Methods
    
    /// Fügt eine Nugget-ID zur Liste der gesehenen Nuggets hinzu
    /// - Parameter nuggetId: Die ID des gesehenen Nuggets
    /// - Returns: Ein aktualisiertes UserNuggetRecord
    func addSeenNugget(_ nuggetId: String) -> UserNuggetRecord {
        var updatedSeenNuggetIds = seenNuggetIds
        if !updatedSeenNuggetIds.contains(nuggetId) {
            updatedSeenNuggetIds.append(nuggetId)
        }
        
        return UserNuggetRecord(
            id: id,
            userId: userId,
            category: category,
            seenNuggetIds: updatedSeenNuggetIds,
            lastUpdated: Date()
        )
    }
    
    // MARK: - Equatable
    
    static func == (lhs: UserNuggetRecord, rhs: UserNuggetRecord) -> Bool {
        return lhs.id == rhs.id &&
               lhs.userId == rhs.userId &&
               lhs.category == rhs.category &&
               lhs.seenNuggetIds == rhs.seenNuggetIds
    }
} 