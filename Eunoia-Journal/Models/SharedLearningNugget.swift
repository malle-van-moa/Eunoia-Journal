import Foundation
import FirebaseFirestore

/// Repräsentiert ein Learning Nugget, das von mehreren Nutzern gemeinsam genutzt werden kann
struct LearningNuggetShared: Identifiable, Codable, Equatable {
    let id: String
    let category: LearningNugget.Category
    let title: String
    let content: String
    let createdAt: Date
    
    init(
        id: String = UUID().uuidString,
        category: LearningNugget.Category,
        title: String,
        content: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.content = content
        self.createdAt = createdAt
    }
    
    // MARK: - Firestore Conversion
    
    /// Konvertiert ein Firestore-Dokument in ein SharedLearningNugget
    /// - Parameter document: Das Firestore-Dokument
    /// - Returns: Ein SharedLearningNugget oder nil, wenn die Konvertierung fehlschlägt
    static func fromFirestore(_ document: DocumentSnapshot) -> LearningNuggetShared? {
        guard let data = document.data() else { return nil }
        
        guard let categoryString = data["category"] as? String,
              let category = LearningNugget.Category(rawValue: categoryString),
              let title = data["title"] as? String,
              let content = data["content"] as? String,
              let createdAtTimestamp = data["created_at"] as? Timestamp else {
            return nil
        }
        
        return LearningNuggetShared(
            id: document.documentID,
            category: category,
            title: title,
            content: content,
            createdAt: createdAtTimestamp.dateValue()
        )
    }
    
    /// Konvertiert das SharedLearningNugget in ein Dictionary für Firestore
    /// - Returns: Ein Dictionary mit den Daten des SharedLearningNugget
    func toFirestore() -> [String: Any] {
        return [
            "category": category.rawValue,
            "title": title,
            "content": content,
            "created_at": FieldValue.serverTimestamp()
        ]
    }
    
    // MARK: - Conversion to LearningNugget
    
    /// Konvertiert das SharedLearningNugget in ein LearningNugget für einen bestimmten Nutzer
    /// - Parameter userId: Die ID des Nutzers
    /// - Returns: Ein LearningNugget
    func toLearningNugget(for userId: String) -> LearningNugget {
        return LearningNugget(
            id: UUID().uuidString, // Neue ID für das persönliche Nugget
            userId: userId,
            category: category,
            title: title,
            content: content,
            date: Date(),
            isAddedToJournal: false
        )
    }
    
    // MARK: - Equatable
    
    static func == (lhs: LearningNuggetShared, rhs: LearningNuggetShared) -> Bool {
        return lhs.id == rhs.id &&
               lhs.category == rhs.category &&
               lhs.title == rhs.title &&
               lhs.content == rhs.content
    }
}

// Typaliasdeklaration für Abwärtskompatibilität
typealias SharedLearningNugget = LearningNuggetShared 