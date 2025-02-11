import CoreData
import Foundation

class CoreDataManager {
    static let shared = CoreDataManager()
    
    private let persistentContainer: NSPersistentContainer
    private let context: NSManagedObjectContext
    
    private init() {
        persistentContainer = NSPersistentContainer(name: "Eunoia_Journal")
        persistentContainer.loadPersistentStores { description, error in
            if let error = error {
                print("Core Data failed to load: \(error.localizedDescription)")
            }
        }
        context = persistentContainer.viewContext
    }
    
    func saveContext() {
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("Error saving context: \(error)")
            }
        }
    }
    
    func fetchJournalEntries(for userId: String) -> [JournalEntry] {
        let request = NSFetchRequest<JournalEntryEntity>(entityName: "JournalEntryEntity")
        request.predicate = NSPredicate(format: "userId == %@", userId)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \JournalEntryEntity.date, ascending: false)]
        
        do {
            let entities = try context.fetch(request)
            return entities.map { JournalEntry(from: $0) }
        } catch {
            // Only log real errors, not empty results
            if error.localizedDescription != "nilError" {
                print("Error fetching entries: \(error)")
            }
            return []
        }
    }
    
    func fetchPendingEntries(for userId: String) -> [JournalEntry] {
        let request = NSFetchRequest<JournalEntryEntity>(entityName: "JournalEntryEntity")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "userId == %@", userId),
            NSPredicate(format: "syncStatus == %@", SyncStatus.pendingUpload.rawValue)
        ])
        
        do {
            let entities = try context.fetch(request)
            return entities.map { JournalEntry(from: $0) }
        } catch {
            // Only log real errors, not empty results
            if error.localizedDescription != "nilError" {
                print("Error fetching pending entries: \(error)")
            }
            return []
        }
    }
    
    func saveJournalEntry(_ entry: JournalEntry) {
        let request = NSFetchRequest<JournalEntryEntity>(entityName: "JournalEntryEntity")
        request.predicate = NSPredicate(format: "id == %@", entry.id ?? "")
        
        do {
            let results = try context.fetch(request)
            let entity: JournalEntryEntity
            
            if let existingEntity = results.first {
                // Update existing entity
                entity = existingEntity
            } else {
                // Create new entity
                entity = JournalEntryEntity(context: context)
                entity.id = entry.id
            }
            
            // Update properties
            entity.userId = entry.userId
            entity.date = entry.date
            entity.gratitude = entry.gratitude
            entity.highlight = entry.highlight
            entity.learning = entry.learning
            entity.lastModified = entry.lastModified
            entity.syncStatus = entry.syncStatus.rawValue
            
            // Handle learning nugget
            if let nugget = entry.learningNugget {
                entity.learningNuggetCategory = nugget.category.rawValue
                entity.learningNuggetContent = nugget.content
                entity.learningNuggetAddedToJournal = nugget.isAddedToJournal
            } else {
                entity.learningNuggetCategory = nil
                entity.learningNuggetContent = nil
                entity.learningNuggetAddedToJournal = false
            }
            
            try context.save()
        } catch {
            // Only log real errors
            if error.localizedDescription != "nilError" {
                print("Error saving entry: \(error)")
            }
        }
    }
    
    func deleteJournalEntry(withId id: String) {
        let request = NSFetchRequest<JournalEntryEntity>(entityName: "JournalEntryEntity")
        request.predicate = NSPredicate(format: "id == %@", id)
        
        do {
            let results = try context.fetch(request)
            if let entity = results.first {
                context.delete(entity)
                try context.save()
            }
        } catch {
            print("Error deleting entry: \(error)")
        }
    }
    
    // MARK: - Vision Board Operations
    
    func saveVisionBoard(_ visionBoard: VisionBoard) {
        let entity = VisionBoardEntity(context: context)
        entity.id = visionBoard.id
        entity.userId = visionBoard.userId
        entity.lastModified = visionBoard.lastModified
        entity.syncStatus = visionBoard.syncStatus.rawValue
        
        // Save lifestyle vision
        entity.lifestyleDailyRoutine = visionBoard.lifestyleVision.dailyRoutine
        entity.lifestyleLivingEnvironment = visionBoard.lifestyleVision.livingEnvironment
        entity.lifestyleWorkStyle = visionBoard.lifestyleVision.workStyle
        entity.lifestyleLeisureActivities = visionBoard.lifestyleVision.leisureActivities.joined(separator: ",")
        entity.lifestyleRelationships = visionBoard.lifestyleVision.relationships
        
        // Save desired personality
        entity.personalityCorePrinciples = visionBoard.desiredPersonality.corePrinciples.joined(separator: ",")
        entity.personalityStrengths = visionBoard.desiredPersonality.strengths.joined(separator: ",")
        entity.personalityAreasOfGrowth = visionBoard.desiredPersonality.areasOfGrowth.joined(separator: ",")
        entity.personalityHabits = visionBoard.desiredPersonality.habits.joined(separator: ",")
        
        // Save personal values
        visionBoard.personalValues.forEach { value in
            let valueEntity = PersonalValueEntity(context: context)
            valueEntity.id = value.id
            valueEntity.name = value.name
            valueEntity.valueDescription = value.description
            valueEntity.importance = Int16(value.importance)
            valueEntity.visionBoard = entity
        }
        
        // Save goals
        visionBoard.goals.forEach { goal in
            let goalEntity = GoalEntity(context: context)
            goalEntity.id = goal.id
            goalEntity.title = goal.title
            goalEntity.goalDescription = goal.description
            goalEntity.category = goal.category.rawValue
            goalEntity.targetDate = goal.targetDate
            goalEntity.visionBoard = entity
            
            // Save milestones
            goal.milestones.forEach { milestone in
                let milestoneEntity = MilestoneEntity(context: context)
                milestoneEntity.id = milestone.id
                milestoneEntity.milestoneDescription = milestone.description
                milestoneEntity.isCompleted = milestone.isCompleted
                milestoneEntity.targetDate = milestone.targetDate
                milestoneEntity.goal = goalEntity
            }
        }
        
        saveContext()
    }
    
    func fetchVisionBoard(for userId: String) -> VisionBoard? {
        let fetchRequest: NSFetchRequest<VisionBoardEntity> = VisionBoardEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "userId == %@", userId)
        
        do {
            let results = try context.fetch(fetchRequest)
            return results.first.map { VisionBoard(from: $0) }
        } catch {
            // Only log real errors, not empty results
            if error.localizedDescription != "nilError" {
                print("Error fetching vision board: \(error)")
            }
            return nil
        }
    }
    
    func deleteAllData() {
        let entities = persistentContainer.managedObjectModel.entities
        entities.forEach { entity in
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entity.name!)
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            
            do {
                try persistentContainer.persistentStoreCoordinator.execute(deleteRequest, with: context)
            } catch {
                print("Error deleting \(entity.name!) data: \(error)")
            }
        }
    }
} 