import CoreData
import Foundation

enum CoreDataError: LocalizedError {
    case fetchError(String)
    case saveError(String)
    case conversionError(String)
    case entityNotFound
    
    var errorDescription: String? {
        switch self {
        case .fetchError(let message):
            return "Fehler beim Abrufen der Daten: \(message)"
        case .saveError(let message):
            return "Fehler beim Speichern: \(message)"
        case .conversionError(let message):
            return "Fehler bei der Datenkonvertierung: \(message)"
        case .entityNotFound:
            return "Eintrag wurde nicht gefunden"
        }
    }
}

class CoreDataManager {
    static let shared = CoreDataManager()
    
    private let persistentContainer: NSPersistentContainer
    private let context: NSManagedObjectContext
    
    private init() {
        // Register custom transformers
        StringArrayTransformer.register()
        
        persistentContainer = NSPersistentContainer(name: "Eunoia")
        
        // Verbesserte Fehlerbehandlung beim Laden der Stores
        persistentContainer.loadPersistentStores { description, error in
            if let error = error {
                print("❌ Core Data failed to load: \(error.localizedDescription)")
                print("Detailed error: \(error)")
                
                // Versuche das Backup-Model zu laden
                if let modelURL = Bundle.main.url(forResource: "CoreDataModel", withExtension: "momd") {
                    do {
                        let model = NSManagedObjectModel(contentsOf: modelURL)
                        let container = NSPersistentContainer(name: "CoreDataModel", managedObjectModel: model!)
                        container.loadPersistentStores { description, error in
                            if let error = error {
                                fatalError("Failed to load Core Data: \(error)")
                            }
                        }
                    } catch {
                        fatalError("Failed to load backup Core Data model: \(error)")
                    }
                }
            } else {
                print("✅ Core Data successfully loaded")
            }
        }
        
        context = persistentContainer.viewContext
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
    
    // MARK: - Helper Methods
    private func convertToNSArray(_ array: [String]?) -> NSArray? {
        guard let array = array else { return nil }
        return NSArray(array: array)
    }
    
    private func convertFromNSArray(_ nsArray: NSArray?) -> [String]? {
        guard let nsArray = nsArray else { return nil }
        return nsArray as? [String]
    }
    
    // MARK: - Core Methods
    func saveContext() throws {
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                throw CoreDataError.saveError(error.localizedDescription)
            }
        }
    }
    
    func fetchJournalEntries(for userId: String) throws -> [JournalEntry] {
        let request = NSFetchRequest<JournalEntryEntity>(entityName: "JournalEntryEntity")
        request.predicate = NSPredicate(format: "userId == %@", userId)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \JournalEntryEntity.date, ascending: false)]
        
        do {
            let entities = try context.fetch(request)
            return entities.map { entity -> JournalEntry in
                JournalEntry(
                    id: entity.id,
                    userId: entity.userId ?? "",
                    date: entity.date ?? Date(),
                    gratitude: entity.gratitude ?? "",
                    highlight: entity.highlight ?? "",
                    learning: entity.learning ?? "",
                    learningNugget: entity.learningNuggetCategory != nil ? LearningNugget(
                        userId: entity.userId ?? "",
                        category: LearningNugget.Category(rawValue: entity.learningNuggetCategory ?? "") ?? .persönlichesWachstum,
                        title: "Lernimpuls",
                        content: entity.learningNuggetContent ?? "",
                        isAddedToJournal: entity.learningNuggetAddedToJournal
                    ) : nil,
                    lastModified: entity.lastModified ?? Date(),
                    syncStatus: SyncStatus(rawValue: entity.syncStatus ?? "") ?? .pendingUpload,
                    title: entity.title,
                    content: entity.content,
                    location: entity.location,
                    imageURLs: convertFromNSArray(entity.imageURLs),
                    localImagePaths: convertFromNSArray(entity.localImagePaths)
                )
            }
        } catch {
            throw CoreDataError.fetchError(error.localizedDescription)
        }
    }
    
    func fetchPendingEntries(for userId: String) throws -> [JournalEntry] {
        let request = NSFetchRequest<JournalEntryEntity>(entityName: "JournalEntryEntity")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "userId == %@", userId),
            NSPredicate(format: "syncStatus == %@", SyncStatus.pendingUpload.rawValue)
        ])
        
        do {
            let entities = try context.fetch(request)
            return try entities.compactMap { entity -> JournalEntry? in
                do {
                    return JournalEntry(from: entity)
                } catch {
                    throw CoreDataError.conversionError(error.localizedDescription)
                }
            }
        } catch {
            throw CoreDataError.fetchError(error.localizedDescription)
        }
    }
    
    func saveJournalEntry(_ entry: JournalEntry) throws {
        let request = NSFetchRequest<JournalEntryEntity>(entityName: "JournalEntryEntity")
        request.predicate = NSPredicate(format: "id == %@", entry.id ?? "")
        
        var saveError: Error?
        
        context.performAndWait {
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
                
                // Update properties in a transaction
                context.transactionAuthor = "JournalEntry_Save"
                context.name = "SaveJournalEntry"
                
                entity.userId = entry.userId
                entity.date = entry.date
                entity.gratitude = entry.gratitude
                entity.highlight = entry.highlight
                entity.learning = entry.learning
                entity.lastModified = entry.lastModified
                entity.syncStatus = entry.syncStatus.rawValue
                entity.title = entry.title
                entity.content = entry.content
                entity.location = entry.location
                entity.imageURLs = convertToNSArray(entry.imageURLs)
                entity.localImagePaths = convertToNSArray(entry.localImagePaths)
                
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
                
                // Versuche zu speichern
                if context.hasChanges {
                    do {
                        try context.save()
                    } catch {
                        saveError = CoreDataError.saveError("Fehler beim Speichern in CoreData: \(error.localizedDescription)")
                    }
                }
            } catch {
                saveError = CoreDataError.saveError("Fehler beim Speichern: \(error.localizedDescription)")
            }
        }
        
        if let error = saveError {
            throw error
        }
    }
    
    func deleteJournalEntry(withId id: String) throws {
        let request = NSFetchRequest<JournalEntryEntity>(entityName: "JournalEntryEntity")
        request.predicate = NSPredicate(format: "id == %@", id)
        
        do {
            let results = try context.fetch(request)
            guard let entity = results.first else {
                throw CoreDataError.entityNotFound
            }
            
            context.delete(entity)
            try context.save()
        } catch {
            throw CoreDataError.saveError(error.localizedDescription)
        }
    }
    
    func deleteJournalEntryAsync(withId id: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            context.perform {
                do {
                    // Prüfe ob der Eintrag existiert
                    let fetchRequest = NSFetchRequest<JournalEntryEntity>(entityName: "JournalEntryEntity")
                    fetchRequest.predicate = NSPredicate(format: "id == %@", id)
                    
                    let results = try self.context.fetch(fetchRequest)
                    
                    if let entityToDelete = results.first {
                        self.context.delete(entityToDelete)
                        
                        // Speichere den Kontext
                        if self.context.hasChanges {
                            try self.context.save()
                        }
                        continuation.resume()
                    } else {
                        // Eintrag existiert nicht mehr
                        continuation.resume()
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Vision Board Operations
    
    func saveVisionBoard(_ visionBoard: VisionBoard) {
        let request = NSFetchRequest<VisionBoardEntity>(entityName: "VisionBoardEntity")
        request.predicate = NSPredicate(format: "id == %@", visionBoard.id ?? "")
        
        do {
            let results = try context.fetch(request)
            let entity: VisionBoardEntity
            
            if let existingEntity = results.first {
                // Update existing entity
                entity = existingEntity
                
                // Remove existing relationships
                if let existingValues = entity.personalValues as? Set<PersonalValueEntity> {
                    existingValues.forEach { context.delete($0) }
                }
                if let existingGoals = entity.goals as? Set<GoalEntity> {
                    existingGoals.forEach { context.delete($0) }
                }
            } else {
                // Create new entity
                entity = VisionBoardEntity(context: context)
                entity.id = visionBoard.id
            }
            
            // Update properties
            entity.userId = visionBoard.userId
            entity.lastModified = visionBoard.lastModified
            entity.syncStatus = visionBoard.syncStatus.rawValue
            
            // Save lifestyle vision
            entity.lifestyleDailyRoutine = visionBoard.lifestyleVision.dailyRoutine
            entity.lifestyleLivingEnvironment = visionBoard.lifestyleVision.livingEnvironment
            entity.lifestyleWorkLife = visionBoard.lifestyleVision.workLife
            entity.lifestyleRelationships = visionBoard.lifestyleVision.relationships
            entity.lifestyleHobbies = visionBoard.lifestyleVision.hobbies
            entity.lifestyleHealth = visionBoard.lifestyleVision.health
            
            // Save desired personality
            entity.personalityTraits = visionBoard.desiredPersonality.traits
            entity.personalityMindset = visionBoard.desiredPersonality.mindset
            entity.personalityBehaviors = visionBoard.desiredPersonality.behaviors
            entity.personalitySkills = visionBoard.desiredPersonality.skills
            entity.personalityHabits = visionBoard.desiredPersonality.habits
            entity.personalityGrowth = visionBoard.desiredPersonality.growth
            
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
                goalEntity.priority = Int16(goal.priority)
                goalEntity.visionBoard = entity
            }
            
            try context.save()
        } catch {
            print("Error saving vision board: \(error)")
        }
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