import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

class LearningNuggetService {
    // MARK: - Properties
    private let db = Firestore.firestore()
    private let openAIService = OpenAIService.shared
    private let deepSeekService = DeepSeekService.shared
    
    // Firestore Collection-Namen
    private let learningNuggetsCollection = "learning_nuggets"
    
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
        do {
            switch currentProvider {
            case .openAI:
                return try await openAIService.generateLearningNugget(from: prompt)
            case .deepSeek:
                return try await deepSeekService.generateLearningNugget(from: prompt)
            }
        } catch let error as OpenAIError {
            // Konvertiere OpenAI-spezifische Fehler in ServiceError
            switch error {
            case .rateLimitExceeded:
                throw ServiceError.apiQuotaExceeded
            case .authenticationError:
                throw ServiceError.aiServiceUnavailable
            case .networkError:
                throw ServiceError.networkError
            case .apiError(let message):
                throw ServiceError.aiGeneration(message)
            default:
                throw ServiceError.aiServiceUnavailable
            }
        } catch {
            // Wenn wir bereits einen ServiceError haben, reiche ihn durch
            if let serviceError = error as? ServiceError {
                throw serviceError
            } else {
                // Sonst, konvertiere in einen generischen ServiceError
                throw ServiceError.aiGeneration(error.localizedDescription)
            }
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
        do {
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
        } catch let error as OpenAIError {
            // Konvertiere OpenAI-spezifische Fehler in ServiceError
            switch error {
            case .rateLimitExceeded:
                throw ServiceError.apiQuotaExceeded
            case .authenticationError:
                throw ServiceError.aiServiceUnavailable
            case .networkError:
                throw ServiceError.networkError
            case .apiError(let message):
                throw ServiceError.aiGeneration(message)
            default:
                throw ServiceError.aiServiceUnavailable
            }
        } catch {
            // Wenn wir bereits einen ServiceError haben, reiche ihn durch
            if let serviceError = error as? ServiceError {
                throw serviceError
            } else {
                // Sonst, konvertiere in einen generischen ServiceError
                throw ServiceError.aiGeneration(error.localizedDescription)
            }
        }
    }
    
    private func fetchPreviousNuggets(for userId: String, category: LearningNugget.Category) async throws -> [LearningNugget] {
        do {
            let snapshot = try await db.collection(learningNuggetsCollection)
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
        } catch {
            // Klassifiziere Firestore-Fehler als Datenbankfehler
            let nsError = error as NSError
            // Prüfe, ob es sich um einen Index-Fehler handelt
            if nsError.domain == "FIRFirestoreErrorDomain" || 
               nsError.localizedDescription.contains("index") || 
               nsError.localizedDescription.contains("Index") {
                throw ServiceError.databaseError("Ein Datenbankindex wird benötigt. Bitte versuche es später erneut oder kontaktiere den Support.")
            }
            // Allgemeiner Datenbankfehler
            throw ServiceError.databaseError(error.localizedDescription)
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
        
        do {
            _ = try await db.collection(learningNuggetsCollection).document(nugget.id).setData(data)
        } catch {
            // Klassifiziere Firestore-Fehler als Datenbankfehler
            let nsError = error as NSError
            // Speziell prüfen, ob es sich um einen Permissions-Fehler handelt
            if nsError.domain == "FIRFirestoreErrorDomain" && nsError.code == 7 {
                throw ServiceError.databaseError("Keine Berechtigung zum Speichern von Daten. Bitte melde dich erneut an.")
            } else {
                throw ServiceError.databaseError("Fehler beim Speichern in der Datenbank: \(error.localizedDescription)")
            }
        }
    }
    
    enum ServiceError: Error {
        case userNotAuthenticated
        case invalidResponse
        case apiQuotaExceeded
        case aiServiceUnavailable
        case networkError
        case aiGeneration(String)
        case databaseError(String)
        
        var localizedDescription: String {
            switch self {
            case .userNotAuthenticated:
                return "Bitte melde dich an, um Learning Nuggets zu generieren."
            case .invalidResponse:
                return "Die Antwort konnte nicht verarbeitet werden. Bitte versuche es erneut."
            case .apiQuotaExceeded:
                return "Die API-Quote wurde überschritten. Bitte versuche es später erneut."
            case .aiServiceUnavailable:
                return "Der AI-Dienst ist derzeit nicht verfügbar. Bitte versuche es später erneut."
            case .networkError:
                return "Es konnte keine Verbindung zum Netzwerk hergestellt werden. Bitte überprüfe deine Internetverbindung."
            case .aiGeneration(let message):
                return "Es konnte kein Learning Nugget generiert werden. Grund: \(message)"
            case .databaseError(let message):
                return "Es konnte keine Verbindung zur Datenbank hergestellt werden. Grund: \(message)"
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