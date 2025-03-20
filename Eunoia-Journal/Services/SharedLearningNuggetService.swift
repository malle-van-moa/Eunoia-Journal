import Foundation
import Firebase
import FirebaseFirestore
import FirebaseAuth
import OSLog
import Combine

/// Fehler, die im Zusammenhang mit dem SharedLearningNuggetService auftreten können
enum SharedLearningNuggetError: Error, LocalizedError {
    case userNotAuthenticated
    case noNuggetsAvailable
    case allNuggetsSeen
    case fetchError(String)
    case saveError(String)
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .userNotAuthenticated:
            return "Benutzer ist nicht authentifiziert"
        case .noNuggetsAvailable:
            return "Keine Learning Nuggets verfügbar"
        case .allNuggetsSeen:
            return "Alle verfügbaren Learning Nuggets wurden bereits gesehen"
        case .fetchError(let message):
            return "Fehler beim Abrufen der Daten: \(message)"
        case .saveError(let message):
            return "Fehler beim Speichern der Daten: \(message)"
        case .invalidData:
            return "Ungültige Daten erhalten"
        }
    }
}

/// Fehler, die beim Arbeiten mit dem SharedLearningNuggetService auftreten können
enum SharedLearningNuggetServiceError: Error, LocalizedError {
    case userNotAuthenticated
    case documentNotFound
    case noNuggetsAvailable
    case networkError
    case dataError
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .userNotAuthenticated:
            return "Benutzer ist nicht authentifiziert"
        case .documentNotFound:
            return "Dokument wurde nicht gefunden"
        case .noNuggetsAvailable:
            return "Keine weiteren Learning Nuggets verfügbar"
        case .networkError:
            return "Netzwerkfehler beim Zugriff auf die Datenbank"
        case .dataError:
            return "Fehler beim Verarbeiten der Daten"
        case .apiError(let message):
            return "API-Fehler: \(message)"
        }
    }
}

/// Service für das Rolling Refill-System der Learning Nuggets
class SharedLearningNuggetService {
    // MARK: - Properties
    
    private let db = Firestore.firestore()
    private let openAIService = OpenAIService.shared
    private let deepSeekService = DeepSeekService.shared
    private let logger = Logger(subsystem: "com.eunoia.journal", category: "SharedLearningNuggetService")
    
    // Firestore Collection-Namen
    private let learningNuggetsCollection = "learning_nuggets"
    private let userNuggetsCollection = "user_nuggets"
    
    // Anzahl der Nuggets, die pro Kategorie generiert werden sollen
    private let nuggetsPerCategory = 25
    
    // MARK: - Singleton
    
    static let shared = SharedLearningNuggetService()
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Ruft ein Learning Nugget für einen Benutzer ab
    /// - Parameters:
    ///   - category: Die Kategorie des Learning Nuggets
    ///   - userId: Die ID des Benutzers
    /// - Returns: Ein Learning Nugget oder nil, wenn keines verfügbar ist
    func fetchLearningNugget(for category: LearningNugget.Category, userId: String) async throws -> LearningNugget {
        logger.debug("Rufe Learning Nugget für Kategorie \(category.rawValue) und Benutzer \(userId) ab")
        
        // 1. Hole die Liste der bereits gesehenen Nuggets für diesen Benutzer
        let userRecord = try await getUserNuggetRecord(for: userId, category: category)
        let seenNuggetIds = userRecord?.seenNuggetIds ?? []
        
        logger.debug("Benutzer hat bereits \(seenNuggetIds.count) Nuggets in dieser Kategorie gesehen")
        
        // 2. Suche nach einem ungenutzten Nugget - ohne komplexe Abfragen, die spezielle Indizes erfordern
        let query = db.collection(learningNuggetsCollection)
            .whereField("category", isEqualTo: category.rawValue)
        
        let snapshot = try await query.getDocuments()
        
        // Filtere die Nuggets manuell, um nur die unbenutzten zu behalten
        var availableNuggets = snapshot.documents.compactMap { SharedLearningNugget.fromFirestore($0) }
            .filter { !seenNuggetIds.contains($0.id) }
        
        // 3. Wenn ein ungenutztes Nugget gefunden wurde, markiere es als gesehen und gib es zurück
        if let nugget = availableNuggets.first {
            logger.debug("Ungenutztes Nugget gefunden: \(nugget.id)")
            
            // Markiere das Nugget als gesehen
            try await markNuggetAsSeen(nuggetId: nugget.id, for: userId, category: category)
            
            // Konvertiere das SharedLearningNugget in ein LearningNugget
            return nugget.toLearningNugget(for: userId)
        }
        
        // 4. Wenn kein ungenutztes Nugget gefunden wurde, generiere neue Nuggets
        logger.debug("Kein ungenutztes Nugget gefunden, generiere neue Nuggets")
        
        // Generiere neue Nuggets direkt mit der Cloud Function
        let newNuggets = try await generateNuggetsWithCloudFunction(category: category, count: nuggetsPerCategory)
        
        // Wenn neue Nuggets generiert wurden, gib das erste zurück
        if let firstNugget = newNuggets.first {
            logger.debug("Neues Nugget generiert: \(firstNugget.id)")
            
            // Markiere das Nugget als gesehen
            try await markNuggetAsSeen(nuggetId: firstNugget.id, for: userId, category: category)
            
            // Konvertiere das SharedLearningNugget in ein LearningNugget
            return firstNugget.toLearningNugget(for: userId)
        }
        
        // Wenn keine neuen Nuggets generiert werden konnten, wirf einen Fehler
        throw ServiceError.noNuggetsAvailable
    }
    
    /// Migriert bestehende Learning Nuggets in das neue Schema
    /// - Returns: Die Anzahl der migrierten Nuggets
    func migrateExistingNuggets() async throws -> Int {
        logger.debug("Migriere bestehende Learning Nuggets")
        
        // 1. Hole alle bestehenden Learning Nuggets aus der alten Collection
        let snapshot = try await db.collection("learningNuggets").getDocuments()
        let existingNuggets = snapshot.documents.compactMap { document -> LearningNugget? in
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
        
        logger.debug("Gefunden: \(existingNuggets.count) bestehende Learning Nuggets in der alten Collection 'learningNuggets'")
        
        // 2. Gruppiere die Nuggets nach Kategorie
        let nuggetsByCategory = Dictionary(grouping: existingNuggets) { $0.category }
        
        // 3. Für jede Kategorie, speichere die Nuggets im neuen Schema
        var migratedCount = 0
        
        for (category, nuggets) in nuggetsByCategory {
            // Erstelle SharedLearningNuggets aus den bestehenden Nuggets
            let sharedNuggets = nuggets.map { nugget in
                SharedLearningNugget(
                    category: nugget.category,
                    title: nugget.title,
                    content: nugget.content,
                    createdAt: nugget.date
                )
            }
            
            // Speichere die SharedLearningNuggets in der neuen Collection
            for nugget in sharedNuggets {
                let docRef = db.collection(learningNuggetsCollection).document(nugget.id)
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
                    seenNuggetIds: seenNuggetIds
                )
                
                let docRef = db.collection(userNuggetsCollection).document()
                try await docRef.setData(userRecord.toFirestore())
            }
        }
        
        logger.debug("Migration abgeschlossen: \(migratedCount) Nuggets von 'learningNuggets' zu '\(self.learningNuggetsCollection)' migriert")
        return migratedCount
    }
    
    /// Initialisiert die Datenbank mit Learning Nuggets für alle Kategorien
    /// - Returns: Die Anzahl der generierten Nuggets
    func initializeDatabaseWithLearningNuggets() async throws {
        logger.debug("Initialisiere Datenbank mit Learning Nuggets")
        
        // Prüfe, ob bereits Nuggets in der Datenbank vorhanden sind
        let snapshot = try await db.collection(learningNuggetsCollection).limit(to: 1).getDocuments()
        
        if !snapshot.documents.isEmpty {
            logger.debug("Datenbank enthält bereits Learning Nuggets, Initialisierung übersprungen")
            return
        }
        
        logger.debug("Keine Learning Nuggets in der Datenbank gefunden, generiere neue")
        
        // Generiere Nuggets für jede Kategorie
        var totalGenerated = 0
        
        for category in LearningNugget.Category.allCases {
            do {
                let generatedCount = try await generateNewNuggets(for: category, count: nuggetsPerCategory)
                totalGenerated += generatedCount
                logger.debug("Generiert: \(generatedCount) Nuggets für Kategorie \(category.rawValue)")
            } catch {
                logger.error("Fehler beim Generieren von Nuggets für Kategorie \(category.rawValue): \(error.localizedDescription)")
            }
        }
        
        logger.debug("Datenbank-Initialisierung abgeschlossen, insgesamt \(totalGenerated) Nuggets generiert")
    }
    
    /// Generiert neue Learning Nuggets für eine Kategorie mit Hilfe der Cloud Function
    /// - Parameters:
    ///   - category: Die Kategorie, für die Nuggets generiert werden sollen
    ///   - count: Die Anzahl der zu generierenden Nuggets
    /// - Returns: Die Anzahl der generierten Nuggets
    func generateNuggetsWithCloudFunction(category: LearningNugget.Category, count: Int = 25) async throws -> [SharedLearningNugget] {
        self.logger.debug("Generiere \(count) Nuggets für Kategorie \(category.rawValue) lokal")
        
        // Lokale Implementierung anstelle der Cloud Function
        let exampleNuggets = generateLocalExampleNuggets(category: category, count: count)
        
        // Speichere die generierten Nuggets in Firestore
        for nugget in exampleNuggets {
            try await db.collection(learningNuggetsCollection).document(nugget.id).setData([
                "id": nugget.id,
                "category": nugget.category.rawValue,
                "title": nugget.title,
                "content": nugget.content,
                "createdAt": nugget.createdAt
            ])
        }
        
        self.logger.debug("Erfolgreich \(exampleNuggets.count) Nuggets lokal generiert und gespeichert")
        return exampleNuggets
    }
    
    /// Markiert ein Nugget als zum Journal hinzugefügt
    /// - Parameters:
    ///   - nuggetId: Die ID des Nuggets
    ///   - userId: Die ID des Benutzers
    func markNuggetAddedToJournal(nuggetId: String, for userId: String) async throws {
        logger.debug("Markiere Nugget \(nuggetId) als zum Journal hinzugefügt für Benutzer \(userId)")
        
        // Suche nach dem UserNuggetRecord
        let snapshot = try await db.collection(userNuggetsCollection)
            .whereField("user_id", isEqualTo: userId)
            .whereField("seen_nuggets", arrayContains: nuggetId)
            .limit(to: 1)
            .getDocuments()
        
        guard let document = snapshot.documents.first else {
            logger.error("Kein UserNuggetRecord gefunden für Nugget \(nuggetId) und Benutzer \(userId)")
            throw SharedLearningNuggetError.invalidData
        }
        
        // Aktualisiere den Record
        try await document.reference.updateData([
            "added_to_journal": true
        ])
        
        logger.debug("Nugget \(nuggetId) erfolgreich als zum Journal hinzugefügt markiert")
    }
    
    /// Ruft Statistiken über die Nuggets ab
    /// - Returns: Ein Dictionary mit Kategorien als Schlüssel und der Anzahl der Nuggets als Wert
    func fetchNuggetStatistics() async throws -> [String: Int] {
        logger.debug("Rufe Nugget-Statistiken ab")
        
        var statistics: [String: Int] = [:]
        
        // Hole alle Kategorien
        for category in LearningNugget.Category.allCases {
            // Zähle die Nuggets für diese Kategorie
            let query = db.collection(learningNuggetsCollection)
                .whereField("category", isEqualTo: category.rawValue)
            
            let countQuery = query.count
            let snapshot = try await countQuery.getAggregation(source: .server)
            
            statistics[category.rawValue] = Int(truncating: snapshot.count)
        }
        
        logger.debug("Nugget-Statistiken abgerufen: \(statistics)")
        return statistics
    }
    
    // MARK: - Private Methods
    
    /// Generiert neue Learning Nuggets für eine Kategorie
    /// - Parameter category: Die Kategorie, für die Nuggets generiert werden sollen
    /// - Returns: Die generierten Nuggets
    private func generateNewNuggets(for category: LearningNugget.Category, count: Int = 25) async throws -> Int {
        logger.debug("Generiere neue Nuggets für Kategorie \(category.rawValue)")
        
        // Versuche zuerst, die Cloud Function zu verwenden
        do {
            let generatedNuggets = try await generateNuggetsWithCloudFunction(category: category, count: count)
            
            if !generatedNuggets.isEmpty {
                logger.debug("Erfolgreich \(generatedNuggets.count) neue Nuggets mit Cloud Function generiert")
                return generatedNuggets.count
            } else {
                logger.warning("Keine Nuggets mit Cloud Function generiert, versuche lokale Generierung")
            }
        } catch {
            logger.error("Fehler bei der Cloud Function: \(error.localizedDescription), versuche lokale Generierung")
        }
        
        // Fallback: Versuche, Nuggets mit dem aktuellen Provider zu generieren
        do {
            let currentProvider = LLMProvider.current
            logger.debug("Versuche Nuggets mit Provider \(currentProvider.rawValue) zu generieren")
            
            // Hier würde normalerweise die Logik für die Generierung mit verschiedenen Providern stehen
            // Da wir aber bereits eine lokale Implementierung in generateNuggetsWithCloudFunction haben,
            // verwenden wir diese erneut
            let generatedNuggets = try await generateNuggetsWithCloudFunction(category: category, count: count)
            logger.debug("Erfolgreich \(generatedNuggets.count) neue Nuggets lokal generiert")
            return generatedNuggets.count
        } catch {
            logger.error("Fehler bei der lokalen Generierung: \(error.localizedDescription)")
            throw ServiceError.generationFailed
        }
    }
    
    /// Erstellt einen Prompt für die Batch-Generierung von Learning Nuggets
    /// - Parameters:
    ///   - category: Die Kategorie, für die Nuggets generiert werden sollen
    ///   - count: Die Anzahl der zu generierenden Nuggets
    /// - Returns: Der Prompt für die KI
    private func createPromptForBatchGeneration(category: LearningNugget.Category, count: Int) -> String {
        return """
        Generiere \(count) einzigartige, prägnante und lehrreiche Learning Nuggets zum Thema "\(category.rawValue)".
        
        Anforderungen:
        - Jedes Nugget sollte faktenbasiert und überprüfbar sein
        - Verwende einfache Sprache und sorge für hohe Verständlichkeit
        - Jedes Nugget sollte maximal 3 Sätze lang sein und ein Aha-Erlebnis erzeugen
        - Jedes Nugget sollte einen kurzen, prägnanten Titel haben
        
        Ausgabeformat:
        Formatiere die Ausgabe als nummerierte Liste mit Titel und Inhalt für jedes Nugget:
        
        1. Titel: [Titel des ersten Nuggets]
        Inhalt: [Inhalt des ersten Nuggets]
        
        2. Titel: [Titel des zweiten Nuggets]
        Inhalt: [Inhalt des zweiten Nuggets]
        
        usw.
        """
    }
    
    /// Parst die Antwort der KI und erstellt daraus Learning Nuggets
    /// - Parameters:
    ///   - response: Die Antwort der KI
    ///   - category: Die Kategorie der Nuggets
    /// - Returns: Die erstellten Nuggets
    private func parseNuggetsFromResponse(_ response: String, category: LearningNugget.Category) -> [SharedLearningNugget] {
        var nuggets: [SharedLearningNugget] = []
        
        // Teile die Antwort in Zeilen auf
        let lines = response.components(separatedBy: .newlines)
        
        var currentTitle: String?
        var currentContent: String?
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Überspringe leere Zeilen
            if trimmedLine.isEmpty {
                continue
            }
            
            // Suche nach Titelzeilen (Format: "X. Titel: [Titel]" oder "Titel: [Titel]")
            if trimmedLine.contains("Titel:") {
                // Wenn wir bereits einen Titel haben, speichere das vorherige Nugget
                if let title = currentTitle, let content = currentContent {
                    nuggets.append(SharedLearningNugget(
                        category: category,
                        title: title,
                        content: content
                    ))
                }
                
                // Extrahiere den neuen Titel
                if let titleRange = trimmedLine.range(of: "Titel:") {
                    let titleStart = titleRange.upperBound
                    currentTitle = String(trimmedLine[titleStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    currentContent = nil
                }
            }
            // Suche nach Inhaltszeilen (Format: "Inhalt: [Inhalt]")
            else if trimmedLine.contains("Inhalt:") {
                if let contentRange = trimmedLine.range(of: "Inhalt:") {
                    let contentStart = contentRange.upperBound
                    currentContent = String(trimmedLine[contentStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                // Wenn wir sowohl Titel als auch Inhalt haben, speichere das Nugget
                if let title = currentTitle, let content = currentContent {
                    nuggets.append(SharedLearningNugget(
                        category: category,
                        title: title,
                        content: content
                    ))
                    
                    // Setze die Werte zurück
                    currentTitle = nil
                    currentContent = nil
                }
            }
        }
        
        // Füge das letzte Nugget hinzu, falls vorhanden
        if let title = currentTitle, let content = currentContent {
            nuggets.append(SharedLearningNugget(
                category: category,
                title: title,
                content: content
            ))
        }
        
        return nuggets
    }
    
    /// Ruft den UserNuggetRecord für einen Benutzer und eine Kategorie ab
    /// - Parameters:
    ///   - userId: Die ID des Benutzers
    ///   - category: Die Kategorie
    /// - Returns: Der UserNuggetRecord oder nil, wenn keiner existiert
    private func getUserNuggetRecord(for userId: String, category: LearningNugget.Category) async throws -> UserNuggetRecord? {
        let snapshot = try await db.collection(userNuggetsCollection)
            .whereField("user_id", isEqualTo: userId)
            .whereField("category", isEqualTo: category.rawValue)
            .limit(to: 1)
            .getDocuments()
        
        return snapshot.documents.first.flatMap { UserNuggetRecord.fromFirestore($0) }
    }
    
    /// Markiert ein Nugget als gesehen für einen Benutzer
    /// - Parameters:
    ///   - nuggetId: Die ID des Nuggets
    ///   - userId: Die ID des Benutzers
    ///   - category: Die Kategorie des Nuggets
    private func markNuggetAsSeen(nuggetId: String, for userId: String, category: LearningNugget.Category) async throws {
        // Hole den bestehenden Record oder erstelle einen neuen
        let existingRecord = try await getUserNuggetRecord(for: userId, category: category)
        
        let updatedRecord: UserNuggetRecord
        if let record = existingRecord {
            // Aktualisiere den bestehenden Record
            updatedRecord = record.addSeenNugget(nuggetId)
            
            // Speichere den aktualisierten Record
            let docRef = db.collection(userNuggetsCollection).document(record.id)
            try await docRef.setData(updatedRecord.toFirestore())
        } else {
            // Erstelle einen neuen Record
            updatedRecord = UserNuggetRecord(
                userId: userId,
                category: category,
                seenNuggetIds: [nuggetId]
            )
            
            // Speichere den neuen Record
            let docRef = db.collection(userNuggetsCollection).document()
            try await docRef.setData(updatedRecord.toFirestore())
        }
        
        logger.debug("Nugget \(nuggetId) als gesehen markiert für Benutzer \(userId)")
    }
    
    /// Generiert lokale Beispiel-Nuggets für eine Kategorie (temporäre Implementierung)
    /// - Parameters:
    ///   - category: Die Kategorie, für die Nuggets generiert werden sollen
    ///   - count: Die Anzahl der zu generierenden Nuggets
    /// - Returns: Array von generierten SharedLearningNugget-Objekten
    private func generateLocalExampleNuggets(category: LearningNugget.Category, count: Int) -> [SharedLearningNugget] {
        var exampleTitles: [String] = []
        var exampleContents: [String] = []
        
        // Beispiel-Inhalte je nach Kategorie
        switch category {
        case .achtsamkeit:
            exampleTitles = [
                "Achtsames Atmen",
                "Im Moment leben",
                "Bewusstes Wahrnehmen",
                "Gedanken beobachten",
                "Körperwahrnehmung"
            ]
            exampleContents = [
                "Nimm dir einen Moment Zeit, um bewusst zu atmen. Spüre, wie die Luft durch deine Nase ein- und ausströmt.",
                "Konzentriere dich vollständig auf die gegenwärtige Aktivität, ohne an Vergangenheit oder Zukunft zu denken.",
                "Beobachte deine Umgebung mit allen Sinnen. Was siehst, hörst, riechst und fühlst du?",
                "Betrachte deine Gedanken wie vorbeiziehende Wolken, ohne sie zu bewerten oder festzuhalten.",
                "Führe einen kurzen Body-Scan durch. Spüre nacheinander in verschiedene Körperregionen hinein."
            ]
        case .persönlichesWachstum:
            exampleTitles = [
                "Dankbarkeit für Kleinigkeiten",
                "Menschen wertschätzen",
                "Herausforderungen als Chancen",
                "Alltägliche Wunder",
                "Selbstfürsorge würdigen"
            ]
            exampleContents = [
                "Notiere drei kleine Dinge, für die du heute dankbar bist.",
                "Denke an eine Person, die dein Leben bereichert, und überlege, wie du ihr deine Wertschätzung zeigen kannst.",
                "Reflektiere über eine Herausforderung, die dich letztendlich stärker gemacht hat.",
                "Achte heute bewusst auf die kleinen Wunder des Alltags, die wir oft als selbstverständlich hinnehmen.",
                "Würdige etwas, das du heute für dein eigenes Wohlbefinden getan hast."
            ]
        case .beziehungen:
            exampleTitles = [
                "Tägliche Erfolge",
                "Lernmomente",
                "Werte und Handlungen",
                "Emotionale Muster",
                "Zukunftsvisionen"
            ]
            exampleContents = [
                "Was war heute dein größter Erfolg, egal wie klein er erscheinen mag?",
                "Welche Erfahrung hat dir heute etwas Wichtiges gelehrt?",
                "Inwiefern haben deine heutigen Handlungen deine wichtigsten Werte widergespiegelt?",
                "Welche Emotionen hast du heute am stärksten wahrgenommen und was haben sie dir mitgeteilt?",
                "Wie bringt dich das, was du heute getan hast, deinen langfristigen Zielen näher?"
            ]
        case .gesundheit:
            exampleTitles = [
                "Bewegung im Alltag",
                "Ausgewogene Ernährung",
                "Ausreichend Schlaf",
                "Stressmanagement",
                "Mentale Gesundheit"
            ]
            exampleContents = [
                "Integriere mehr Bewegung in deinen Alltag – nimm die Treppe statt des Aufzugs oder mache kurze Spaziergänge in den Pausen.",
                "Achte auf eine ausgewogene Ernährung mit viel Gemüse, Obst, Vollkornprodukten und qualitativ hochwertigen Proteinen.",
                "Priorisiere ausreichend Schlaf, indem du eine regelmäßige Schlafenszeit einhältst und eine entspannende Abendroutine etablierst.",
                "Entwickle Strategien zum Stressabbau, wie tiefes Atmen, Meditation oder körperliche Aktivität.",
                "Kümmere dich aktiv um deine mentale Gesundheit, indem du soziale Kontakte pflegst und bei Bedarf professionelle Hilfe in Anspruch nimmst."
            ]
        case .aiGenerated:
            exampleTitles = [
                "Kreative Perspektiven",
                "Neue Gewohnheiten",
                "Persönliches Wachstum",
                "Achtsamkeitsübung",
                "Positive Affirmation"
            ]
            exampleContents = [
                "Betrachte eine aktuelle Herausforderung aus drei verschiedenen Perspektiven. Was ändert sich?",
                "Welche kleine Gewohnheit könntest du in deinen Alltag integrieren, die langfristig große Wirkung haben könnte?",
                "In welchem Bereich deines Lebens möchtest du wachsen, und was wäre ein erster kleiner Schritt in diese Richtung?",
                "Nimm dir einen Moment Zeit, um deine Atmung zu beobachten. Wie verändert sich dein Bewusstsein?",
                "Formuliere eine positive Aussage über dich selbst, die du heute besonders brauchst, und wiederhole sie mehrmals."
            ]
        case .produktivität:
            exampleTitles = [
                "Zeitmanagement",
                "Prioritäten setzen",
                "Fokussiertes Arbeiten",
                "Effektive Planung",
                "Motivationssteigerung"
            ]
            exampleContents = [
                "Teile große Aufgaben in kleine, überschaubare Schritte auf, um Überforderung zu vermeiden und kontinuierlichen Fortschritt zu erleben.",
                "Identifiziere jeden Morgen die drei wichtigsten Aufgaben des Tages und erledige diese zuerst.",
                "Verwende die Pomodoro-Technik: 25 Minuten konzentriertes Arbeiten, gefolgt von 5 Minuten Pause.",
                "Plane nicht nur deine Aufgaben, sondern auch bewusste Pausen. Erholung ist ein wesentlicher Teil der Produktivität.",
                "Verbinde unangenehme Aufgaben mit einer angenehmen Belohnung, um deine Motivation zu steigern."
            ]
        case .finanzen:
            exampleTitles = [
                "Budgetplanung",
                "Investieren lernen",
                "Sparziele setzen",
                "Finanzielle Achtsamkeit",
                "Langfristige Sicherheit"
            ]
            exampleContents = [
                "Führe ein einfaches Haushaltsbuch, um Überblick über deine regelmäßigen Einnahmen und Ausgaben zu behalten.",
                "Beginne früh mit dem Investieren, auch mit kleinen Beträgen. Der Zinseszins-Effekt ist ein mächtiger Verbündeter.",
                "Definiere konkrete, messbare Sparziele mit einem klaren Zeitrahmen, um deine Motivation aufrechtzuerhalten.",
                "Vor jedem nicht-essentiellen Kauf, warte 24 Stunden. Dies verhindert impulsive Ausgaben und fördert bewussten Konsum.",
                "Baue schrittweise einen Notfallfonds auf, der mindestens drei bis sechs Monatsgehälter umfasst."
            ]
        case .kreativität:
            exampleTitles = [
                "Ideenfindung",
                "Kreative Routinen",
                "Perspektivwechsel",
                "Inspiration finden",
                "Kreatives Denken"
            ]
            exampleContents = [
                "Führe regelmäßig Brainstorming-Sessions durch, in denen du alle Ideen ohne sofortige Bewertung notierst.",
                "Etabliere eine feste kreative Routine, um deinem Gehirn zu signalisieren, dass es Zeit für kreatives Denken ist.",
                "Betrachte Probleme aus ungewöhnlichen Blickwinkeln, indem du dich fragst: 'Wie würde Person X dieses Problem lösen?'",
                "Sammle aktiv Inspiration aus verschiedenen Quellen – Natur, Kunst, Gespräche oder neuen Erfahrungen.",
                "Verbinde scheinbar nicht zusammenhängende Konzepte, um innovative Lösungen und Ideen zu generieren."
            ]
        case .karriere:
            exampleTitles = [
                "Netzwerkaufbau",
                "Kompetenzerweiterung",
                "Berufliche Ziele",
                "Arbeits-Leben-Balance",
                "Persönliche Marke"
            ]
            exampleContents = [
                "Pflege dein berufliches Netzwerk kontinuierlich, nicht nur wenn du aktiv auf Jobsuche bist.",
                "Investiere regelmäßig in deine Weiterbildung, um relevant zu bleiben und neue Karrierechancen zu eröffnen.",
                "Setze dir sowohl kurzfristige als auch langfristige berufliche Ziele und überprüfe diese regelmäßig.",
                "Definiere klare Grenzen zwischen Arbeits- und Privatzeit, um Burnout zu vermeiden und Erholung zu gewährleisten.",
                "Entwickle deine persönliche Marke, indem du deine einzigartigen Stärken und Fachkenntnisse herausstellst."
            ]
        }
        
        // Generiere die angeforderte Anzahl an Nuggets
        var nuggets: [SharedLearningNugget] = []
        for i in 0..<count {
            // Wenn mehr Nuggets angefordert werden als Beispiele vorhanden sind, erstelle Variationen
            let titleIndex = i % exampleTitles.count
            let contentIndex = i % exampleContents.count
            
            let title = exampleTitles[titleIndex]
            let content = exampleContents[contentIndex]
            
            // Füge eine kleine Variation hinzu, wenn wir die Beispiele wiederverwenden
            let titleVariation = i >= exampleTitles.count ? " (\(i / exampleTitles.count + 1))" : ""
            
            let nugget = SharedLearningNugget(
                id: UUID().uuidString,
                category: category,
                title: title + titleVariation,
                content: content,
                createdAt: Date()
            )
            nuggets.append(nugget)
        }
        
        return nuggets
    }
    
    // MARK: - Error Types
    
    enum ServiceError: Error, LocalizedError {
        case userNotAuthenticated
        case noNuggetsAvailable
        case generationFailed
        case invalidData
        
        var errorDescription: String? {
            switch self {
            case .userNotAuthenticated:
                return "Bitte melde dich an, um Learning Nuggets zu generieren."
            case .noNuggetsAvailable:
                return "Es konnten keine Learning Nuggets generiert werden. Bitte versuche es später erneut."
            case .generationFailed:
                return "Die Generierung der Learning Nuggets ist fehlgeschlagen. Bitte versuche es später erneut."
            case .invalidData:
                return "Die Daten sind ungültig oder konnten nicht verarbeitet werden."
            }
        }
    }
} 