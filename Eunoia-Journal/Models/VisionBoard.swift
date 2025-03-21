import Foundation
import FirebaseCore
import FirebaseFirestore

// Wertekompass-Modell mit direkter Definition
struct ValueCompass: Identifiable, Codable {
    var id: String = UUID().uuidString
    var values: [RadarChartEntry]
    var lastUpdated: Date
    
    init(values: [RadarChartEntry], lastUpdated: Date = Date()) {
        self.values = values
        self.lastUpdated = lastUpdated
    }
}

struct VisionBoard: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var lastModified: Date
    var personalValues: [PersonalValue]
    var goals: [Goal]
    var lifestyleVision: LifestyleVision
    var desiredPersonality: DesiredPersonality
    var syncStatus: SyncStatus
    var valueCompass: ValueCompass?
    
    init(
        id: String? = nil,
        userId: String,
        lastModified: Date,
        personalValues: [PersonalValue],
        goals: [Goal],
        lifestyleVision: LifestyleVision,
        desiredPersonality: DesiredPersonality,
        syncStatus: SyncStatus,
        valueCompass: ValueCompass? = nil
    ) {
        self.id = id
        self.userId = userId
        self.lastModified = lastModified
        self.personalValues = personalValues
        self.goals = goals
        self.lifestyleVision = lifestyleVision
        self.desiredPersonality = desiredPersonality
        self.syncStatus = syncStatus
        self.valueCompass = valueCompass
    }
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
        self.syncStatus = SyncStatus(rawValue: entity.syncStatus ?? "") ?? .pendingUpload
        
        // Convert personal values
        if let valueEntities = entity.personalValues as? Set<PersonalValueEntity> {
            self.personalValues = valueEntities.map { entity in
                PersonalValue(
                    id: entity.id ?? UUID().uuidString,
                    name: entity.name ?? "",
                    description: entity.valueDescription ?? "",
                    importance: Int(entity.importance)
                )
            }
        } else {
            self.personalValues = []
        }
        
        // Convert goals
        if let goalEntities = entity.goals as? Set<GoalEntity> {
            self.goals = goalEntities.map { entity in
                Goal(
                    id: entity.id ?? UUID().uuidString,
                    title: entity.title ?? "",
                    description: entity.goalDescription ?? "",
                    category: Goal.Category(rawValue: entity.category ?? "") ?? .personal,
                    targetDate: entity.targetDate,
                    priority: Int(entity.priority)
                )
            }
        } else {
            self.goals = []
        }
        
        // Konvertiere Lifestyle-Vision
        self.lifestyleVision = LifestyleVision(
            dailyRoutine: entity.lifestyleDailyRoutine ?? "",
            livingEnvironment: entity.lifestyleLivingEnvironment ?? "",
            workLife: entity.lifestyleWorkLife ?? "",
            relationships: entity.lifestyleRelationships ?? "",
            hobbies: entity.lifestyleHobbies ?? "",
            health: entity.lifestyleHealth ?? ""
        )
        
        // Konvertiere Desired Personality
        self.desiredPersonality = DesiredPersonality(
            traits: entity.personalityTraits ?? "",
            mindset: entity.personalityMindset ?? "",
            behaviors: entity.personalityBehaviors ?? "",
            skills: entity.personalitySkills ?? "",
            habits: entity.personalityHabits ?? "",
            growth: entity.personalityGrowth ?? ""
        )
        
        // Konvertiere ValueCompass mit dem definierten Accessor
        self.valueCompass = entity.valueCompass
    }
} 
