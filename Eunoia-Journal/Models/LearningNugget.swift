import Foundation

struct LearningNugget: Identifiable, Codable {
    let id: String
    let userId: String
    let category: Category
    let title: String
    let content: String
    let date: Date
    var isAddedToJournal: Bool
    
    enum Category: String, Codable, CaseIterable {
        case persönlichesWachstum = "Persönliches Wachstum"
        case beziehungen = "Beziehungen"
        case gesundheit = "Gesundheit"
        case produktivität = "Produktivität"
        case finanzen = "Finanzen"
        case kreativität = "Kreativität"
        case achtsamkeit = "Achtsamkeit"
        case karriere = "Karriere"
    }
    
    init(id: String = UUID().uuidString,
         userId: String,
         category: Category,
         title: String,
         content: String,
         date: Date = Date(),
         isAddedToJournal: Bool = false) {
        self.id = id
        self.userId = userId
        self.category = category
        self.title = title
        self.content = content
        self.date = date
        self.isAddedToJournal = isAddedToJournal
    }
} 