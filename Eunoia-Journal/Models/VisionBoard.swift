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
    var category: Category
    var title: String
    var description: String
    var targetDate: Date?
    var milestones: [Milestone]
    
    enum Category: String, Codable, CaseIterable {
        case health = "Gesundheit"
        case career = "Karriere"
        case relationships = "Beziehungen"
        case personal = "Persönlich"
        case financial = "Finanzen"
        case spiritual = "Spiritualität"
        
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
                    "Regelmäßige Meditation",
                    "Achtsamkeit üben",
                    "Werte definieren",
                    "Dankbarkeit praktizieren"
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
    var workStyle: String
    var leisureActivities: [String]
    var relationships: String
    
    static let leisureExamples = [
        "Wandern",
        "Lesen",
        "Musik",
        "Sport",
        "Reisen",
        "Kochen",
        "Kunst",
        "Meditation",
        "Gärtnern",
        "Fotografie"
    ]
}

struct DesiredPersonality: Codable {
    var corePrinciples: [String]
    var strengths: [String]
    var areasOfGrowth: [String]
    var habits: [String]
    
    static let corePrincipleExamples = [
        "Integrität",
        "Mut",
        "Mitgefühl",
        "Kreativität",
        "Ausdauer",
        "Offenheit",
        "Dankbarkeit",
        "Verantwortung"
    ]
    
    static let strengthExamples = [
        "Empathie",
        "Analytisches Denken",
        "Kommunikation",
        "Führung",
        "Kreativität",
        "Problemlösung",
        "Teamarbeit",
        "Anpassungsfähigkeit"
    ]
    
    static let growthExamples = [
        "Geduld entwickeln",
        "Besser zuhören",
        "Grenzen setzen",
        "Selbstvertrauen stärken",
        "Stress bewältigen",
        "Zeit management",
        "Kommunikation verbessern"
    ]
    
    static let habitExamples = [
        "Früh aufstehen",
        "Regelmäßig Sport",
        "Gesund essen",
        "Meditation",
        "Lesen",
        "Journaling",
        "Dankbarkeit üben"
    ]
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
