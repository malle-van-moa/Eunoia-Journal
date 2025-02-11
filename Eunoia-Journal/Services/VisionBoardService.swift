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
        guard let id = visionBoard.id else { return }
        
        // Create dictionary manually to avoid JSON encoding issues
        var dict: [String: Any] = [
            "userId": visionBoard.userId,
            "lastModified": Timestamp(date: visionBoard.lastModified),
            "syncStatus": visionBoard.syncStatus.rawValue
        ]
        
        // Convert personal values
        let personalValuesData = visionBoard.personalValues.map { value -> [String: Any] in
            return [
                "name": value.name,
                "description": value.description,
                "importance": value.importance
            ]
        }
        dict["personalValues"] = personalValuesData
        
        // Convert goals
        let goalsData = visionBoard.goals.map { goal -> [String: Any] in
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
            "dailyRoutine": visionBoard.lifestyleVision.dailyRoutine,
            "livingEnvironment": visionBoard.lifestyleVision.livingEnvironment,
            "workLife": visionBoard.lifestyleVision.workLife,
            "relationships": visionBoard.lifestyleVision.relationships,
            "hobbies": visionBoard.lifestyleVision.hobbies,
            "health": visionBoard.lifestyleVision.health
        ]
        dict["lifestyleVision"] = lifestyleVisionData
        
        // Convert desired personality
        let desiredPersonalityData: [String: Any] = [
            "traits": visionBoard.desiredPersonality.traits,
            "mindset": visionBoard.desiredPersonality.mindset,
            "behaviors": visionBoard.desiredPersonality.behaviors,
            "skills": visionBoard.desiredPersonality.skills,
            "habits": visionBoard.desiredPersonality.habits,
            "growth": visionBoard.desiredPersonality.growth
        ]
        dict["desiredPersonality"] = desiredPersonalityData
        
        try await db.collection("visionBoards").document(id).setData(dict)
        
        // Update local vision board status to synced
        var updatedVisionBoard = visionBoard
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
        
        db.collection("visionBoards")
            .whereField("userId", isEqualTo: userId)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    subject.send(completion: .failure(error))
                    return
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
        
        return subject.eraseToAnyPublisher()
    }
} 