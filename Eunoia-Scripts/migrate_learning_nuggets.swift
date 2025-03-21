import Foundation
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth

// MARK: - Hauptfunktion zur Migration von Learning Nuggets

/// Hauptfunktion zur Migration von Learning Nuggets
struct MigrateLearningNuggets {
    static func run() {
        // Konfiguriere Firebase
        // WICHTIG: Ersetze diese Werte durch deine tatsächlichen Firebase-Konfigurationswerte
        // Diese Werte findest du in der Firebase Console unter Projekteinstellungen > Allgemein > Deine Apps
        let options = FirebaseOptions(
            googleAppID: "1:190076633593:ios:040b87b1ef862c4550bd28",  // Ersetze durch deine App-ID
            gcmSenderID: "190076633593"  // Ersetze durch deine GCM-Sender-ID
        )
        options.apiKey = "AIzaSyAUvwQvxHP0HP57eLjKxi8UVPeO6mPVmik"  // Ersetze durch deinen API-Key
        options.projectID = "eunoia-journal"  // Ersetze durch deine Projekt-ID
        FirebaseApp.configure(options: options)
        
        // Führe die Migration aus
        Task {
            await migrateNuggets()
            exit(0)
        }
        
        // Warte auf die Ausführung der Task
        RunLoop.main.run()
    }
    
    // Hauptfunktion für manuelle Ausführung
    static func main() {
        run()
    }
    
    // MARK: - Datenmodelle für die Migration
    
    /// Repräsentiert ein Learning Nugget
    struct LearningNugget: Codable {
        let id: String
        let userId: String
        let category: String
        let title: String
        let content: String
        let date: Date
        let isAddedToJournal: Bool
    }
    
    /// Repräsentiert ein SharedLearningNugget
    struct SharedLearningNugget: Codable {
        let id: String
        let category: String
        let title: String
        let content: String
        let createdAt: Date
        
        func toFirestore() -> [String: Any] {
            return [
                "id": id,
                "category": category,
                "title": title,
                "content": content,
                "created_at": createdAt
            ]
        }
    }
    
    /// Repräsentiert einen UserNuggetRecord
    struct UserNuggetRecord: Codable {
        let userId: String
        let category: String
        let seenNuggetIds: [String]
        let lastUpdated: Date
        
        func toFirestore() -> [String: Any] {
            return [
                "user_id": userId,
                "category": category,
                "seen_nuggets": seenNuggetIds,
                "last_updated": lastUpdated
            ]
        }
    }
    
    // MARK: - Migrationsfunktion
    
    /// Migriert bestehende Learning Nuggets in das neue Schema
    static func migrateNuggets() async {
        let db = Firestore.firestore()
        
        print("Starte Migration der Learning Nuggets...")
        
        do {
            // 1. Hole alle bestehenden Learning Nuggets aus der alten Collection
            let snapshot = try await db.collection("learningNuggets").getDocuments()
            let existingNuggets = snapshot.documents.compactMap { document -> LearningNugget? in
                let data = document.data()
                guard let userId = data["userId"] as? String,
                      let categoryStr = data["category"] as? String,
                      let title = data["title"] as? String,
                      let content = data["content"] as? String,
                      let date = (data["date"] as? Timestamp)?.dateValue(),
                      let isAddedToJournal = data["isAddedToJournal"] as? Bool else {
                    return nil
                }
                
                return LearningNugget(
                    id: document.documentID,
                    userId: userId,
                    category: categoryStr,
                    title: title,
                    content: content,
                    date: date,
                    isAddedToJournal: isAddedToJournal
                )
            }
            
            print("Gefunden: \(existingNuggets.count) bestehende Learning Nuggets in der alten Collection 'learningNuggets'")
            
            // 2. Gruppiere die Nuggets nach Kategorie
            let nuggetsByCategory = Dictionary(grouping: existingNuggets) { $0.category }
            
            // 3. Für jede Kategorie, speichere die Nuggets im neuen Schema
            var migratedCount = 0
            
            for (category, nuggets) in nuggetsByCategory {
                print("Migriere Kategorie: \(category) mit \(nuggets.count) Nuggets")
                
                // Erstelle SharedLearningNuggets aus den bestehenden Nuggets
                let sharedNuggets = nuggets.map { nugget in
                    SharedLearningNugget(
                        id: UUID().uuidString,
                        category: nugget.category,
                        title: nugget.title,
                        content: nugget.content,
                        createdAt: nugget.date
                    )
                }
                
                // Speichere die SharedLearningNuggets in der neuen Collection
                for nugget in sharedNuggets {
                    let docRef = db.collection("learning_nuggets").document(nugget.id)
                    try await docRef.setData(nugget.toFirestore())
                    migratedCount += 1
                }
                
                // Erstelle UserNuggetRecords für jeden Benutzer
                let userIds = Set(nuggets.map { $0.userId })
                for userId in userIds {
                    let userNuggets = nuggets.filter { $0.userId == userId }
                    let seenNuggetIds = userNuggets.map { $0.id }
                    
                    let userRecord = UserNuggetRecord(
                        userId: userId,
                        category: category,
                        seenNuggetIds: seenNuggetIds,
                        lastUpdated: Date()
                    )
                    
                    let docRef = db.collection("user_nuggets").document()
                    try await docRef.setData(userRecord.toFirestore())
                    
                    print("Benutzer \(userId) hat \(seenNuggetIds.count) Nuggets in Kategorie \(category) gesehen")
                }
            }
            
            print("Migration abgeschlossen: \(migratedCount) Nuggets von 'learningNuggets' zu 'learning_nuggets' migriert")
        } catch {
            print("Fehler bei der Migration: \(error.localizedDescription)")
        }
    }
} 