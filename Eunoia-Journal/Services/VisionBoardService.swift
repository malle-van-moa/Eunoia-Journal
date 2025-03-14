import Foundation
import FirebaseCore
import FirebaseFirestore
import Combine

class VisionBoardService {
    static let shared = VisionBoardService()
    
    private let db = Firestore.firestore()
    private let coreDataManager = CoreDataManager.shared
    
    private init() {}
    
    // MARK: - Vision Board
    
    func saveVisionBoard(_ visionBoard: VisionBoard) async throws {
        // Wenn keine ID vorhanden ist, generiere eine neue ID
        let documentId: String
        var updatedVisionBoard = visionBoard
        
        if let id = visionBoard.id {
            documentId = id
        } else {
            // Generiere eine neue ID für das Dokument
            let newDocRef = db.collection("visionBoards").document()
            documentId = newDocRef.documentID
            
            // Aktualisiere das VisionBoard mit der neuen ID
            updatedVisionBoard.id = documentId
        }
        
        // Create dictionary manually to avoid JSON encoding issues
        var dict: [String: Any] = [
            "userId": updatedVisionBoard.userId,
            "lastModified": Timestamp(date: updatedVisionBoard.lastModified),
            "syncStatus": updatedVisionBoard.syncStatus.rawValue
        ]
        
        // Convert personal values
        let personalValuesData = updatedVisionBoard.personalValues.map { value -> [String: Any] in
            return [
                "name": value.name,
                "description": value.description,
                "importance": value.importance
            ]
        }
        dict["personalValues"] = personalValuesData
        
        // Convert goals
        let goalsData = updatedVisionBoard.goals.map { goal -> [String: Any] in
            var goalDict: [String: Any] = [
                "title": goal.title,
                "description": goal.description,
                "category": goal.category.rawValue,
                "priority": goal.priority
            ]
            
            // Add optional target date if available
            if let targetDate = goal.targetDate {
                goalDict["targetDate"] = Timestamp(date: targetDate)
            }
            
            return goalDict
        }
        dict["goals"] = goalsData
        
        // Convert lifestyle vision
        let lifestyleVisionData: [String: Any] = [
            "dailyRoutine": updatedVisionBoard.lifestyleVision.dailyRoutine,
            "livingEnvironment": updatedVisionBoard.lifestyleVision.livingEnvironment,
            "workLife": updatedVisionBoard.lifestyleVision.workLife,
            "relationships": updatedVisionBoard.lifestyleVision.relationships,
            "hobbies": updatedVisionBoard.lifestyleVision.hobbies,
            "health": updatedVisionBoard.lifestyleVision.health
        ]
        dict["lifestyleVision"] = lifestyleVisionData
        
        // Convert desired personality
        let desiredPersonalityData: [String: Any] = [
            "traits": updatedVisionBoard.desiredPersonality.traits,
            "mindset": updatedVisionBoard.desiredPersonality.mindset,
            "behaviors": updatedVisionBoard.desiredPersonality.behaviors,
            "skills": updatedVisionBoard.desiredPersonality.skills,
            "habits": updatedVisionBoard.desiredPersonality.habits,
            "growth": updatedVisionBoard.desiredPersonality.growth
        ]
        dict["desiredPersonality"] = desiredPersonalityData
        
        try await db.collection("visionBoards").document(documentId).setData(dict)
        
        // Update local vision board status to synced
        updatedVisionBoard.syncStatus = .synced
        coreDataManager.saveVisionBoard(updatedVisionBoard)
    }
    
    func fetchVisionBoard(for userId: String) async throws -> VisionBoard? {
        let snapshot = try await db.collection("visionBoards")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        
        guard let document = snapshot.documents.first else { return nil }
        
        let data = document.data()
        
        // Extract required fields
        guard let userId = data["userId"] as? String,
              let lastModifiedTimestamp = data["lastModified"] as? Timestamp,
              let syncStatusRaw = data["syncStatus"] as? String,
              let syncStatus = SyncStatus(rawValue: syncStatusRaw),
              let personalValuesData = data["personalValues"] as? [[String: Any]],
              let goalsData = data["goals"] as? [[String: Any]] else {
            return nil
        }
        
        // Convert personal values
        let personalValues = personalValuesData.compactMap { valueData -> PersonalValue? in
            guard let name = valueData["name"] as? String,
                  let description = valueData["description"] as? String,
                  let importance = valueData["importance"] as? Int else {
                return nil
            }
            return PersonalValue(
                name: name,
                description: description,
                importance: importance
            )
        }
        
        // Convert goals
        let goals = goalsData.compactMap { goalData -> Goal? in
            guard let title = goalData["title"] as? String,
                  let description = goalData["description"] as? String,
                  let categoryRaw = goalData["category"] as? String,
                  let category = Goal.Category(rawValue: categoryRaw),
                  let priority = goalData["priority"] as? Int else {
                return nil
            }
            
            // Handle optional target date
            let targetDate = (goalData["targetDate"] as? Timestamp)?.dateValue()
            
            return Goal(
                title: title,
                description: description,
                category: category,
                targetDate: targetDate,
                priority: priority
            )
        }
        
        // Extract lifestyle vision
        let lifestyleVision: LifestyleVision
        if let lifestyleData = data["lifestyleVision"] as? [String: Any],
           let dailyRoutine = lifestyleData["dailyRoutine"] as? String,
           let livingEnvironment = lifestyleData["livingEnvironment"] as? String,
           let workLife = lifestyleData["workLife"] as? String,
           let relationships = lifestyleData["relationships"] as? String,
           let hobbies = lifestyleData["hobbies"] as? String,
           let health = lifestyleData["health"] as? String {
            lifestyleVision = LifestyleVision(
                dailyRoutine: dailyRoutine,
                livingEnvironment: livingEnvironment,
                workLife: workLife,
                relationships: relationships,
                hobbies: hobbies,
                health: health
            )
        } else {
            lifestyleVision = LifestyleVision(
                dailyRoutine: "",
                livingEnvironment: "",
                workLife: "",
                relationships: "",
                hobbies: "",
                health: ""
            )
        }
        
        // Extract desired personality
        let desiredPersonality: DesiredPersonality
        if let personalityData = data["desiredPersonality"] as? [String: Any],
           let traits = personalityData["traits"] as? String,
           let mindset = personalityData["mindset"] as? String,
           let behaviors = personalityData["behaviors"] as? String,
           let skills = personalityData["skills"] as? String,
           let habits = personalityData["habits"] as? String,
           let growth = personalityData["growth"] as? String {
            desiredPersonality = DesiredPersonality(
                traits: traits,
                mindset: mindset,
                behaviors: behaviors,
                skills: skills,
                habits: habits,
                growth: growth
            )
        } else {
            desiredPersonality = DesiredPersonality(
                traits: "",
                mindset: "",
                behaviors: "",
                skills: "",
                habits: "",
                growth: ""
            )
        }
        
        return VisionBoard(
            id: document.documentID,
            userId: userId,
            lastModified: lastModifiedTimestamp.dateValue(),
            personalValues: personalValues,
            goals: goals,
            lifestyleVision: lifestyleVision,
            desiredPersonality: desiredPersonality,
            syncStatus: syncStatus
        )
    }
    
    func observeVisionBoard(for userId: String) -> AnyPublisher<VisionBoard?, Error> {
        let subject = PassthroughSubject<VisionBoard?, Error>()
        
        // Erstelle eine Referenz auf den Listener, um ihn später entfernen zu können
        var listenerReference: ListenerRegistration?
        
        // Erstelle einen Listener, der automatisch entfernt wird, wenn das Subject abgebrochen wird
        let cancellable = subject
            .handleEvents(receiveCancel: {
                // Entferne den Listener, wenn das Subject abgebrochen wird
                listenerReference?.remove()
                print("🔄 Firestore-Listener für Vision Board wurde entfernt")
            })
            .eraseToAnyPublisher()
        
        // Erstelle die Firestore-Abfrage
        let query = db.collection("visionBoards")
            .whereField("userId", isEqualTo: userId)
        
        // Füge den Listener hinzu mit verbesserter Fehlerbehandlung
        listenerReference = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            // Behandle Netzwerkfehler speziell
            if let error = error {
                let nsError = error as NSError
                
                // Prüfe, ob es sich um einen Netzwerkfehler handelt
                if nsError.domain == "FIRFirestoreErrorDomain" && 
                   (nsError.code == 8 || // Fehlercode für "Unavailable"
                    nsError.localizedDescription.contains("Network connectivity changed")) {
                    
                    print("📡 Netzwerkverbindung unterbrochen. Firestore-Listener für Vision Board wird pausiert.")
                    
                    // Sende keine Fehlermeldung, da dies ein erwartetes Verhalten ist
                    // Stattdessen versuchen wir, lokale Daten zu verwenden
                    if let localVisionBoard = self.coreDataManager.fetchVisionBoard(for: userId) {
                        subject.send(localVisionBoard)
                    }
                    
                    return
                } else {
                    // Bei anderen Fehlern senden wir den Fehler an den Subscriber
                    print("❌ Firestore-Fehler: \(error.localizedDescription)")
                    subject.send(completion: .failure(error))
                    return
                }
            }
            
            guard let document = snapshot?.documents.first else {
                subject.send(nil)
                return
            }
            
            do {
                let data = document.data()
                
                // Extract required fields
                guard let userId = data["userId"] as? String,
                      let lastModifiedTimestamp = data["lastModified"] as? Timestamp,
                      let syncStatusRaw = data["syncStatus"] as? String,
                      let syncStatus = SyncStatus(rawValue: syncStatusRaw),
                      let personalValuesData = data["personalValues"] as? [[String: Any]],
                      let goalsData = data["goals"] as? [[String: Any]] else {
                    subject.send(nil)
                    return
                }
                
                // Convert personal values
                let personalValues = personalValuesData.compactMap { valueData -> PersonalValue? in
                    guard let name = valueData["name"] as? String,
                          let description = valueData["description"] as? String,
                          let importance = valueData["importance"] as? Int else {
                        return nil
                    }
                    return PersonalValue(
                        name: name,
                        description: description,
                        importance: importance
                    )
                }
                
                // Convert goals
                let goals = goalsData.compactMap { goalData -> Goal? in
                    guard let title = goalData["title"] as? String,
                          let description = goalData["description"] as? String,
                          let categoryRaw = goalData["category"] as? String,
                          let category = Goal.Category(rawValue: categoryRaw),
                          let priority = goalData["priority"] as? Int else {
                        return nil
                    }
                    
                    // Handle optional target date
                    let targetDate = (goalData["targetDate"] as? Timestamp)?.dateValue()
                    
                    return Goal(
                        title: title,
                        description: description,
                        category: category,
                        targetDate: targetDate,
                        priority: priority
                    )
                }
                
                // Extract lifestyle vision
                let lifestyleVision: LifestyleVision
                if let lifestyleData = data["lifestyleVision"] as? [String: Any],
                   let dailyRoutine = lifestyleData["dailyRoutine"] as? String,
                   let livingEnvironment = lifestyleData["livingEnvironment"] as? String,
                   let workLife = lifestyleData["workLife"] as? String,
                   let relationships = lifestyleData["relationships"] as? String,
                   let hobbies = lifestyleData["hobbies"] as? String,
                   let health = lifestyleData["health"] as? String {
                    lifestyleVision = LifestyleVision(
                        dailyRoutine: dailyRoutine,
                        livingEnvironment: livingEnvironment,
                        workLife: workLife,
                        relationships: relationships,
                        hobbies: hobbies,
                        health: health
                    )
                } else {
                    lifestyleVision = LifestyleVision(
                        dailyRoutine: "",
                        livingEnvironment: "",
                        workLife: "",
                        relationships: "",
                        hobbies: "",
                        health: ""
                    )
                }
                
                // Extract desired personality
                let desiredPersonality: DesiredPersonality
                if let personalityData = data["desiredPersonality"] as? [String: Any],
                   let traits = personalityData["traits"] as? String,
                   let mindset = personalityData["mindset"] as? String,
                   let behaviors = personalityData["behaviors"] as? String,
                   let skills = personalityData["skills"] as? String,
                   let habits = personalityData["habits"] as? String,
                   let growth = personalityData["growth"] as? String {
                    desiredPersonality = DesiredPersonality(
                        traits: traits,
                        mindset: mindset,
                        behaviors: behaviors,
                        skills: skills,
                        habits: habits,
                        growth: growth
                    )
                } else {
                    desiredPersonality = DesiredPersonality(
                        traits: "",
                        mindset: "",
                        behaviors: "",
                        skills: "",
                        habits: "",
                        growth: ""
                    )
                }
                
                let visionBoard = VisionBoard(
                    id: document.documentID,
                    userId: userId,
                    lastModified: lastModifiedTimestamp.dateValue(),
                    personalValues: personalValues,
                    goals: goals,
                    lifestyleVision: lifestyleVision,
                    desiredPersonality: desiredPersonality,
                    syncStatus: syncStatus
                )
                
                subject.send(visionBoard)
            } catch {
                subject.send(completion: .failure(error))
            }
        }
        
        return cancellable
    }
} 