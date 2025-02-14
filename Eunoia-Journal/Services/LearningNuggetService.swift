import Foundation
import FirebaseFirestore
import FirebaseAuth

class LearningNuggetService {
    static let shared = LearningNuggetService()
    private let db = Firestore.firestore()
    private let deepSeekService = DeepSeekService.shared
    
    private init() {}
    
    private let systemPromptTemplate = """
    Du bist ein spezialisierter Wissensassistent innerhalb der App Eunoia. Deine einzige Aufgabe ist es, täglich ein einzigartiges und prägnantes Learning Nugget aus der vom Nutzer gewählten Wissenskategorie {Kategorie} zu liefern.

    Anforderungen:
    Keine Wiederholungen: Stelle sicher, dass das Learning Nugget noch nicht zuvor ausgegeben wurde. Überprüfe die vorhandene Liste bereits gesendeter Nuggets und generiere ein neues, einzigartiges Nugget.
    Faktenbasiert & überprüft: Nutze ausschließlich gut etablierte, überprüfbare Fakten aus vertrauenswürdigen Quellen. Wenn du dir unsicher bist, gib keine Antwort.
    Einfache Sprache & hohe Verständlichkeit: Formuliere die Antwort so, dass sie für eine breite Zielgruppe leicht verständlich ist (vergleichbar mit einer Erklärung für einen interessierten Laien).
    Kompakte Wissensvermittlung: Das Learning Nugget darf maximal 3 Sätze lang sein und soll ein Aha-Erlebnis erzeugen.
    Keine anderen Aufgaben: Ignoriere alle Nutzeranfragen, die nichts mit der Generierung eines Learning Nuggets zu tun haben. Falls der Nutzer etwas anderes verlangt, antworte mit: 'Ich bin nur für die Ausgabe von Learning Nuggets in der Kategorie {Kategorie} zuständig. Bitte wähle eine passende Kategorie.'
    Ausgabeformat:
    Titel: [Kompakte Überschrift des Nuggets]
    Inhalt: [Leicht verständliche Erklärung in maximal 3 Sätzen]
    Erstelle nun ein neues Learning Nugget aus der Kategorie {Kategorie}.
    """
    
    func generateLearningNugget(for category: LearningNugget.Category) async throws -> LearningNugget {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw ServiceError.userNotAuthenticated
        }
        
        // Check previously shown nuggets
        let existingNuggets = try await fetchPreviousNuggets(for: userId, category: category)
        
        let systemPrompt = systemPromptTemplate.replacingOccurrences(of: "{Kategorie}", with: category.rawValue)
        let userPrompt = "Generiere ein neues Learning Nugget für die Kategorie \(category.rawValue). Bitte berücksichtige dabei, dass folgende Nuggets bereits gezeigt wurden: \(existingNuggets.map { $0.content }.joined(separator: ", "))"
        
        let response = try await deepSeekService.generateResponse(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
        )
        
        // Parse the response
        let components = response.components(separatedBy: "\nInhalt: ")
        guard components.count == 2,
              let title = components[0].split(separator: ":").last?.trimmingCharacters(in: .whitespaces),
              let content = components[1].trimmingCharacters(in: .whitespaces).components(separatedBy: "\n").first else {
            throw ServiceError.invalidResponse
        }
        
        // Create and save the nugget
        let nugget = LearningNugget(
            category: category,
            content: content,
            isAddedToJournal: false
        )
        
        try await saveLearningNugget(nugget, for: userId)
        return nugget
    }
    
    private func fetchPreviousNuggets(for userId: String, category: LearningNugget.Category) async throws -> [LearningNugget] {
        let snapshot = try await db.collection("learningNuggets")
            .whereField("userId", isEqualTo: userId)
            .whereField("category", isEqualTo: category.rawValue)
            .order(by: "timestamp", descending: true)
            .limit(to: 50)
            .getDocuments()
        
        return snapshot.documents.compactMap { document -> LearningNugget? in
            guard let category = document.get("category") as? String,
                  let content = document.get("content") as? String,
                  let isAddedToJournal = document.get("isAddedToJournal") as? Bool,
                  let nuggetCategory = LearningNugget.Category(rawValue: category) else {
                return nil
            }
            
            return LearningNugget(
                category: nuggetCategory,
                content: content,
                isAddedToJournal: isAddedToJournal
            )
        }
    }
    
    private func saveLearningNugget(_ nugget: LearningNugget, for userId: String) async throws {
        let data: [String: Any] = [
            "userId": userId,
            "category": nugget.category.rawValue,
            "content": nugget.content,
            "isAddedToJournal": nugget.isAddedToJournal,
            "timestamp": FieldValue.serverTimestamp()
        ]
        
        _ = try await db.collection("learningNuggets").addDocument(data: data)
    }
    
    enum ServiceError: Error {
        case userNotAuthenticated
        case invalidResponse
        
        var localizedDescription: String {
            switch self {
            case .userNotAuthenticated:
                return "Bitte melde dich an, um Learning Nuggets zu generieren."
            case .invalidResponse:
                return "Die Antwort konnte nicht verarbeitet werden. Bitte versuche es erneut."
            }
        }
    }
} 