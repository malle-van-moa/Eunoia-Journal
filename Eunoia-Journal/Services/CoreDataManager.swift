import CoreData
import Foundation

class CoreDataManager {
    static let shared = CoreDataManager()
    
    private init() {}
    
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "Eunoia")
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Unable to load persistent stores: \(error)")
            }
        }
        return container
    }()
    
    var context: NSManagedObjectContext {
        persistentContainer.viewContext
    }
    
    func saveContext() {
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let error = error as NSError
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }
    }
    
    // MARK: - Journal Entry Operations
    
    func saveJournalEntry(_ entry: JournalEntry) {
        let entity = JournalEntryEntity(context: context)
        entity.id = entry.id
        entity.userId = entry.userId
        entity.date = entry.date
        entity.gratitude = entry.gratitude
        entity.highlight = entry.highlight
        entity.learning = entry.learning
        entity.lastModified = entry.lastModified
        entity.syncStatus = entry.syncStatus.rawValue
        
        if let nugget = entry.learningNugget {
            entity.learningNuggetCategory = nugget.category.rawValue
            entity.learningNuggetContent = nugget.content
            entity.learningNuggetAddedToJournal = nugget.isAddedToJournal
        }
        
        saveContext()
    }
    
    func fetchJournalEntries(for userId: String) -> [JournalEntry] {
        let fetchRequest: NSFetchRequest<JournalEntryEntity> = JournalEntryEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "userId == %@", userId)
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \JournalEntryEntity.date, ascending: false)]
        
        do {
            let results = try context.fetch(fetchRequest)
            return results.map { JournalEntry(from: $0) }
        } catch {
            print("Error fetching journal entries: \(error)")
            return []
        }
    }
    
    func fetchUnsyncedJournalEntries() -> [JournalEntry] {
        let fetchRequest: NSFetchRequest<JournalEntryEntity> = JournalEntryEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "syncStatus != %@", JournalEntry.SyncStatus.synced.rawValue)
        
        do {
            let results = try context.fetch(fetchRequest)
            return results.map { JournalEntry(from: $0) }
        } catch {
            print("Error fetching unsynced entries: \(error)")
            return []
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
            print("Error fetching vision board: \(error)")
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