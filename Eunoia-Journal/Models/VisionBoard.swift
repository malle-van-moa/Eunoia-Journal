import Foundation
import FirebaseCore
import FirebaseFirestore

struct VisionBoard: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var lastModified: Date
    var personalValues: [PersonalValue]
    var goals: [Goal]
    var lifestyleVision: LifestyleVision
    var desiredPersonality: DesiredPersonality
    var syncStatus: SyncStatus
}

struct PersonalValue: Identifiable, Codable {
    var id: String = UUID().uuidString
    var name: String
    var description: String
    var importance: Int // 1-5 scale
}

struct Goal: Identifiable, Codable {
    var id: String = UUID().uuidString
    var category: Category
    var title: String
    var description: String
    var targetDate: Date?
    var milestones: [Milestone]
    
    enum Category: String, Codable, CaseIterable {
        case health
        case career
        case relationships
        case personal
        case financial
        case spiritual
    }
}

struct Milestone: Identifiable, Codable {
    var id: String = UUID().uuidString
    var description: String
    var isCompleted: Bool
    var targetDate: Date?
}

struct LifestyleVision: Codable {
    var dailyRoutine: String
    var livingEnvironment: String
    var workStyle: String
    var leisureActivities: [String]
    var relationships: String
}

struct DesiredPersonality: Codable {
    var corePrinciples: [String]
    var strengths: [String]
    var areasOfGrowth: [String]
    var habits: [String]
}

// Extension for Core Data conversion
extension VisionBoard {
    init(from entity: VisionBoardEntity) {
        self.id = entity.id
        self.userId = entity.userId ?? ""
        self.lastModified = entity.lastModified ?? Date()
        self.syncStatus = SyncStatus(rawValue: entity.syncStatus ?? "pendingUpload") ?? .pendingUpload
        
        // Convert personal values
        self.personalValues = entity.personalValues?.compactMap { value in
            guard let value = value as? PersonalValueEntity else { return nil }
            return PersonalValue(
                id: value.id ?? UUID().uuidString,
                name: value.name ?? "",
                description: value.valueDescription ?? "",
                importance: Int(value.importance)
            )
        } ?? []
        
        // Convert goals
        self.goals = entity.goals?.compactMap { goal in
            guard let goal = goal as? GoalEntity else { return nil }
            return Goal(
                id: goal.id ?? UUID().uuidString,
                category: Goal.Category(rawValue: goal.category ?? "") ?? .personal,
                title: goal.title ?? "",
                description: goal.goalDescription ?? "",
                targetDate: goal.targetDate,
                milestones: []
            )
        } ?? []
        
        // Convert lifestyle vision
        self.lifestyleVision = LifestyleVision(
            dailyRoutine: entity.lifestyleDailyRoutine ?? "",
            livingEnvironment: entity.lifestyleLivingEnvironment ?? "",
            workStyle: entity.lifestyleWorkStyle ?? "",
            leisureActivities: entity.lifestyleLeisureActivities?.components(separatedBy: ",") ?? [],
            relationships: entity.lifestyleRelationships ?? ""
        )
        
        // Convert desired personality
        self.desiredPersonality = DesiredPersonality(
            corePrinciples: entity.personalityCorePrinciples?.components(separatedBy: ",") ?? [],
            strengths: entity.personalityStrengths?.components(separatedBy: ",") ?? [],
            areasOfGrowth: entity.personalityAreasOfGrowth?.components(separatedBy: ",") ?? [],
            habits: entity.personalityHabits?.components(separatedBy: ",") ?? []
        )
    }
} 
