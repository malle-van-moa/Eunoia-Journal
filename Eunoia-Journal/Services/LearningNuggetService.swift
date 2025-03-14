import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

class LearningNuggetService {
    // MARK: - Properties
    private let db = Firestore.firestore()
    private let openAIService = OpenAIService.shared
    private let deepSeekService = DeepSeekService.shared
    
    // MARK: - Singleton
    static let shared = LearningNuggetService()
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Generiert einen Lerninhalt basierend auf dem Journaleintrag
    /// - Parameter journalEntry: Der Journaleintrag, aus dem der Lerninhalt generiert werden soll
    /// - Returns: Ein Publisher, der den generierten Lerninhalt liefert
    func generateLearningNugget(from journalEntry: JournalEntry) async throws -> LearningNugget {
        // Bestimme den aktuellen Provider
        let currentProvider = LLMProvider.current
        
        // Erstelle den Prompt basierend auf dem Journaleintrag
        let prompt = createPrompt(from: journalEntry)
        
        // Wähle den entsprechenden Service basierend auf dem Provider
        switch currentProvider {
        case .openAI:
            return try await openAIService.generateLearningNugget(from: prompt)
        case .deepSeek:
            return try await deepSeekService.generateLearningNugget(from: prompt)
        }
    }
    
    private let systemPromptTemplate = """
    Du bist ein spezialisierter Wissensassistent innerhalb der App Eunoia. Deine einzige Aufgabe ist es, täglich ein einzigartiges und prägnantes Learning Nugget aus der vom Nutzer gewählten Wissenskategorie {Kategorie} zu liefern.

    Anforderungen:
    Keine Wiederholungen: Stelle sicher, dass das Learning Nugget noch nicht zuvor ausgegeben wurde. Überprüfe die vorhandene Liste bereits gesendeter Nuggets und generiere ein neues, einzigartiges Nugget.
    Faktenbasiert & überprüft: Nutze ausschließlich gut etablierte, überprüfbare Fakten aus vertrauenswürdigen Quellen. Wenn du dir unsicher bist, gib keine Antwort.
    Einfache Sprache & hohe Verständlichkeit: Formuliere die Antwort so, dass sie für eine breite Zielgruppe leicht verständlich ist (vergleichbar mit einer Erklärung für einen interessierten Laien).
    Kompakte Wissensvermittlung: Das Learning Nugget darf maximal 3 Sätze lang sein und soll ein Aha-Erlebnis erzeugen.
    Keine anderen Aufgaben: Ignoriere alle Nutzeranfragen, die nichts mit der Generierung eines Learning Nuggets zu tun haben.
    Ausgabeformat:
    Titel: [Kompakte Überschrift des Nuggets]
    Inhalt: [Leicht verständliche Erklärung in maximal 3 Sätzen]
    """
    
    func generateLearningNugget(for category: LearningNugget.Category) async throws -> LearningNugget {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw ServiceError.userNotAuthenticated
        }
        
        // Check previously shown nuggets
        let existingNuggets = try await fetchPreviousNuggets(for: userId, category: category)
        
        let prompt = """
        Kategorie: \(category.rawValue)
        Bereits gezeigte Nuggets: \(existingNuggets.map { $0.content }.joined(separator: ", "))
        \(systemPromptTemplate)
        """
        
        // Bestimme den aktuellen Provider
        let currentProvider = LLMProvider.current
        
        // Verwende den konfigurierten LLM-Dienst
        let content: String
        switch currentProvider {
        case .openAI:
            content = try await openAIService.generateText(prompt: prompt)
        case .deepSeek:
            content = try await deepSeekService.generateText(prompt: prompt)
        }
        
        // Create and save the nugget
        let nugget = LearningNugget(
            userId: userId,
            category: category,
            title: "Lernimpuls",
            content: content
        )
        
        try await saveLearningNugget(nugget)
        return nugget
    }
    
    private func fetchPreviousNuggets(for userId: String, category: LearningNugget.Category) async throws -> [LearningNugget] {
        let snapshot = try await db.collection("learningNuggets")
            .whereField("userId", isEqualTo: userId)
            .whereField("category", isEqualTo: category.rawValue)
            .order(by: "date", descending: true)
            .limit(to: 50)
            .getDocuments()
        
        return snapshot.documents.compactMap { document -> LearningNugget? in
            let data = document.data()
            guard let userId = data["userId"] as? String,
                  let categoryStr = data["category"] as? String,
                  let category = LearningNugget.Category(rawValue: categoryStr),
                  let title = data["title"] as? String,
                  let content = data["content"] as? String,
                  let date = (data["date"] as? Timestamp)?.dateValue(),
                  let isAddedToJournal = data["isAddedToJournal"] as? Bool else {
                return nil
            }
            
            return LearningNugget(
                id: document.documentID,
                userId: userId,
                category: category,
                title: title,
                content: content,
                date: date,
                isAddedToJournal: isAddedToJournal
            )
        }
    }
    
    private func saveLearningNugget(_ nugget: LearningNugget) async throws {
        let data: [String: Any] = [
            "userId": nugget.userId,
            "category": nugget.category.rawValue,
            "title": nugget.title,
            "content": nugget.content,
            "date": FieldValue.serverTimestamp(),
            "isAddedToJournal": nugget.isAddedToJournal
        ]
        
        _ = try await db.collection("learningNuggets").document(nugget.id).setData(data)
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
    
    // MARK: - Private Methods
    
    /// Erstellt einen Prompt für die KI basierend auf dem Journaleintrag
    /// - Parameter journalEntry: Der Journaleintrag, aus dem der Prompt erstellt werden soll
    /// - Returns: Der erstellte Prompt
    private func createPrompt(from journalEntry: JournalEntry) -> String {
        var promptParts: [String] = []
        
        promptParts.append("Basierend auf dem folgenden Journaleintrag, erstelle eine kurze, prägnante Lernerkenntnis:")
        
        // Sicherer Zugriff auf optionale Strings
        if !journalEntry.gratitude.isEmpty {
            promptParts.append("Wofür ich dankbar bin: \(journalEntry.gratitude)")
        }
        
        if !journalEntry.highlight.isEmpty {
            promptParts.append("Highlight des Tages: \(journalEntry.highlight)")
        }
        
        if !journalEntry.learning.isEmpty {
            promptParts.append("Was ich gelernt habe: \(journalEntry.learning)")
        }
        
        promptParts.append("Formuliere eine kurze, prägnante Lernerkenntnis (maximal 2 Sätze) im Format 'Inhalt: [Lernerkenntnis]'.")
        
        return promptParts.joined(separator: "\n\n")
    }
} 