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
    
    static let examples = [
        "Authentizität",
        "Ehrlichkeit",
        "Familie",
        "Gesundheit",
        "Kreativität",
        "Lernen",
        "Nachhaltigkeit",
        "Persönliches Wachstum",
        "Respekt",
        "Verantwortung"
    ]
}

struct Goal: Identifiable, Codable {
    var id: String = UUID().uuidString
    var title: String
    var description: String
    var category: Category
    var targetDate: Date?
    var priority: Int
    
    enum Category: String, Codable, CaseIterable {
        case health = "Gesundheit"
        case career = "Karriere"
        case relationships = "Beziehungen"
        case personal = "Persönlich"
        case financial = "Finanzen"
        case spiritual = "Spiritualität"
        
        var localizedName: String { rawValue }
        
        var description: String {
            switch self {
            case .health:
                return "Fitness, Ernährung und allgemeines Wohlbefinden"
            case .career:
                return "Berufliche Entwicklung und Fähigkeiten"
            case .relationships:
                return "Familie, Freundschaften und soziale Verbindungen"
            case .personal:
                return "Persönliche Entwicklung und Hobbys"
            case .financial:
                return "Finanzielle Ziele und Sicherheit"
            case .spiritual:
                return "Innere Entwicklung und Sinnfindung"
            }
        }
        
        var examples: [String] {
            switch self {
            case .health:
                return [
                    "Regelmäßiger Sport",
                    "Gesunde Ernährung",
                    "Besserer Schlaf",
                    "Meditation"
                ]
            case .career:
                return [
                    "Neue Fähigkeiten erlernen",
                    "Beförderung anstreben",
                    "Netzwerk aufbauen",
                    "Eigenes Projekt starten"
                ]
            case .relationships:
                return [
                    "Mehr Zeit mit Familie",
                    "Neue Freundschaften",
                    "Bestehende Beziehungen vertiefen",
                    "Aktiv zuhören üben"
                ]
            case .personal:
                return [
                    "Neues Hobby beginnen",
                    "Buch schreiben",
                    "Sprache lernen",
                    "Kreativität fördern"
                ]
            case .financial:
                return [
                    "Notgroschen aufbauen",
                    "Investieren lernen",
                    "Budget erstellen",
                    "Schulden abbauen"
                ]
            case .spiritual:
                return [
                    "Meditation praktizieren",
                    "Achtsamkeit üben",
                    "Werte definieren",
                    "Sinn finden"
                ]
            }
        }
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
    var workLife: String
    var relationships: String
    var hobbies: String
    var health: String
    
    var isEmpty: Bool {
        dailyRoutine.isEmpty &&
        livingEnvironment.isEmpty &&
        workLife.isEmpty &&
        relationships.isEmpty &&
        hobbies.isEmpty &&
        health.isEmpty
    }
}

struct DesiredPersonality: Codable {
    var traits: String
    var mindset: String
    var behaviors: String
    var skills: String
    var habits: String
    var growth: String
    
    var isEmpty: Bool {
        traits.isEmpty &&
        mindset.isEmpty &&
        behaviors.isEmpty &&
        skills.isEmpty &&
        habits.isEmpty &&
        growth.isEmpty
    }
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
                title: goal.title ?? "",
                description: goal.goalDescription ?? "",
                category: Goal.Category(rawValue: goal.category ?? "") ?? .personal,
                targetDate: goal.targetDate,
                priority: Int(goal.priority)
            )
        } ?? []
        
        // Convert lifestyle vision
        self.lifestyleVision = LifestyleVision(
            dailyRoutine: entity.lifestyleDailyRoutine ?? "",
            livingEnvironment: entity.lifestyleLivingEnvironment ?? "",
            workLife: entity.lifestyleWorkLife ?? "",
            relationships: entity.lifestyleRelationships ?? "",
            hobbies: entity.lifestyleHobbies ?? "",
            health: entity.lifestyleHealth ?? ""
        )
        
        // Convert desired personality
        self.desiredPersonality = DesiredPersonality(
            traits: entity.personalityTraits ?? "",
            mindset: entity.personalityMindset ?? "",
            behaviors: entity.personalityBehaviors ?? "",
            skills: entity.personalitySkills ?? "",
            habits: entity.personalityHabits ?? "",
            growth: entity.personalityGrowth ?? ""
        )
    }
} 
