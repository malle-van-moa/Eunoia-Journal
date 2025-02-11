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
                "category": goal.category.rawValue
            ]
            
            // Add optional target date if available
            if let targetDate = goal.targetDate {
                goalDict["targetDate"] = Timestamp(date: targetDate)
            }
            
            // Add milestones
            let milestonesData = goal.milestones.map { milestone -> [String: Any] in
                var milestoneDict: [String: Any] = [
                    "description": milestone.description,
                    "isCompleted": milestone.isCompleted
                ]
                if let targetDate = milestone.targetDate {
                    milestoneDict["targetDate"] = Timestamp(date: targetDate)
                }
                return milestoneDict
            }
            goalDict["milestones"] = milestonesData
            
            return goalDict
        }
        dict["goals"] = goalsData
        
        // Convert lifestyle vision
        let lifestyleVisionData: [String: Any] = [
            "dailyRoutine": visionBoard.lifestyleVision.dailyRoutine,
            "livingEnvironment": visionBoard.lifestyleVision.livingEnvironment,
            "workStyle": visionBoard.lifestyleVision.workStyle,
            "leisureActivities": visionBoard.lifestyleVision.leisureActivities,
            "relationships": visionBoard.lifestyleVision.relationships
        ]
        dict["lifestyleVision"] = lifestyleVisionData
        
        // Convert desired personality
        let desiredPersonalityData: [String: Any] = [
            "corePrinciples": visionBoard.desiredPersonality.corePrinciples,
            "strengths": visionBoard.desiredPersonality.strengths,
            "areasOfGrowth": visionBoard.desiredPersonality.areasOfGrowth,
            "habits": visionBoard.desiredPersonality.habits
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
                  let category = Goal.Category(rawValue: categoryRaw) else {
                return nil
            }
            
            // Handle optional target date
            let targetDate = (goalData["targetDate"] as? Timestamp)?.dateValue()
            
            // Handle milestones
            let milestonesData = goalData["milestones"] as? [[String: Any]] ?? []
            let milestones = milestonesData.compactMap { milestoneData -> Milestone? in
                guard let description = milestoneData["description"] as? String,
                      let isCompleted = milestoneData["isCompleted"] as? Bool else {
                    return nil
                }
                let targetDate = (milestoneData["targetDate"] as? Timestamp)?.dateValue()
                return Milestone(
                    description: description,
                    isCompleted: isCompleted,
                    targetDate: targetDate
                )
            }
            
            return Goal(
                category: category,
                title: title,
                description: description,
                targetDate: targetDate,
                milestones: milestones
            )
        }
        
        // Extract lifestyle vision
        let lifestyleVision: LifestyleVision
        if let lifestyleData = data["lifestyleVision"] as? [String: Any],
           let dailyRoutine = lifestyleData["dailyRoutine"] as? String,
           let livingEnvironment = lifestyleData["livingEnvironment"] as? String,
           let workStyle = lifestyleData["workStyle"] as? String,
           let leisureActivities = lifestyleData["leisureActivities"] as? [String],
           let relationships = lifestyleData["relationships"] as? String {
            lifestyleVision = LifestyleVision(
                dailyRoutine: dailyRoutine,
                livingEnvironment: livingEnvironment,
                workStyle: workStyle,
                leisureActivities: leisureActivities,
                relationships: relationships
            )
        } else {
            lifestyleVision = LifestyleVision(
                dailyRoutine: "",
                livingEnvironment: "",
                workStyle: "",
                leisureActivities: [],
                relationships: ""
            )
        }
        
        // Extract desired personality
        let desiredPersonality: DesiredPersonality
        if let personalityData = data["desiredPersonality"] as? [String: Any],
           let corePrinciples = personalityData["corePrinciples"] as? [String],
           let strengths = personalityData["strengths"] as? [String],
           let areasOfGrowth = personalityData["areasOfGrowth"] as? [String],
           let habits = personalityData["habits"] as? [String] {
            desiredPersonality = DesiredPersonality(
                corePrinciples: corePrinciples,
                strengths: strengths,
                areasOfGrowth: areasOfGrowth,
                habits: habits
            )
        } else {
            desiredPersonality = DesiredPersonality(
                corePrinciples: [],
                strengths: [],
                areasOfGrowth: [],
                habits: []
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
                              let category = Goal.Category(rawValue: categoryRaw) else {
                            return nil
                        }
                        
                        // Handle optional target date
                        let targetDate = (goalData["targetDate"] as? Timestamp)?.dateValue()
                        
                        // Handle milestones
                        let milestonesData = goalData["milestones"] as? [[String: Any]] ?? []
                        let milestones = milestonesData.compactMap { milestoneData -> Milestone? in
                            guard let description = milestoneData["description"] as? String,
                                  let isCompleted = milestoneData["isCompleted"] as? Bool else {
                                return nil
                            }
                            let targetDate = (milestoneData["targetDate"] as? Timestamp)?.dateValue()
                            return Milestone(
                                description: description,
                                isCompleted: isCompleted,
                                targetDate: targetDate
                            )
                        }
                        
                        return Goal(
                            category: category,
                            title: title,
                            description: description,
                            targetDate: targetDate,
                            milestones: milestones
                        )
                    }
                    
                    // Extract lifestyle vision
                    let lifestyleVision: LifestyleVision
                    if let lifestyleData = data["lifestyleVision"] as? [String: Any],
                       let dailyRoutine = lifestyleData["dailyRoutine"] as? String,
                       let livingEnvironment = lifestyleData["livingEnvironment"] as? String,
                       let workStyle = lifestyleData["workStyle"] as? String,
                       let leisureActivities = lifestyleData["leisureActivities"] as? [String],
                       let relationships = lifestyleData["relationships"] as? String {
                        lifestyleVision = LifestyleVision(
                            dailyRoutine: dailyRoutine,
                            livingEnvironment: livingEnvironment,
                            workStyle: workStyle,
                            leisureActivities: leisureActivities,
                            relationships: relationships
                        )
                    } else {
                        lifestyleVision = LifestyleVision(
                            dailyRoutine: "",
                            livingEnvironment: "",
                            workStyle: "",
                            leisureActivities: [],
                            relationships: ""
                        )
                    }
                    
                    // Extract desired personality
                    let desiredPersonality: DesiredPersonality
                    if let personalityData = data["desiredPersonality"] as? [String: Any],
                       let corePrinciples = personalityData["corePrinciples"] as? [String],
                       let strengths = personalityData["strengths"] as? [String],
                       let areasOfGrowth = personalityData["areasOfGrowth"] as? [String],
                       let habits = personalityData["habits"] as? [String] {
                        desiredPersonality = DesiredPersonality(
                            corePrinciples: corePrinciples,
                            strengths: strengths,
                            areasOfGrowth: areasOfGrowth,
                            habits: habits
                        )
                    } else {
                        desiredPersonality = DesiredPersonality(
                            corePrinciples: [],
                            strengths: [],
                            areasOfGrowth: [],
                            habits: []
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