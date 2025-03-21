import CoreData
import Foundation

enum CoreDataError: LocalizedError {
    case fetchError(String)
    case saveError(String)
    case conversionError(String)
    case entityNotFound
    case migrationFailed(String)
    
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
        case .migrationFailed(let message):
            return "Migration fehlgeschlagen: \(message)"
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
        
        persistentContainer = NSPersistentContainer(name: "CoreDataModel")
        
        // Migrationsoptions konfigurieren
        let options = NSPersistentStoreDescription()
        options.shouldMigrateStoreAutomatically = true
        options.shouldInferMappingModelAutomatically = true
        persistentContainer.persistentStoreDescriptions = [options]
        
        // Verbesserte Fehlerbehandlung beim Laden der Stores
        persistentContainer.loadPersistentStores { description, error in
            if let error = error {
                print("❌ Core Data failed to load: \(error.localizedDescription)")
                print("Detailed error: \(error)")
                fatalError("Failed to load Core Data: \(error)")
            } else {
                print("✅ Core Data successfully loaded")
            }
        }
        
        context = persistentContainer.viewContext
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
    
    // MARK: - Migration and Repair Methods
    
    func repairImageRelationships() throws {
        let fetchRequest: NSFetchRequest<CoreDataJournalEntry> = CoreDataJournalEntry.fetchRequest()
        
        do {
            let entries = try context.fetch(fetchRequest)
            
            for entry in entries {
                context.performAndWait {
                    if entry.imageRelationship == nil {
                        entry.imageRelationship = NSSet()
                    }
                }
            }
            
            try context.save()
        } catch {
            throw CoreDataError.migrationFailed("Fehler beim Reparieren der Bildbeziehungen: \(error)")
        }
    }
    
    func validateDataStore() throws {
        // Überprüfen und reparieren der Bildbeziehungen
        try repairImageRelationships()
        
        // Überprüfen auf beschädigte Einträge
        let fetchRequest: NSFetchRequest<CoreDataJournalEntry> = CoreDataJournalEntry.fetchRequest()
        
        do {
            let entries = try context.fetch(fetchRequest)
            for entry in entries {
                if entry.id == nil {
                    entry.id = UUID().uuidString
                }
                
                if entry.date == nil {
                    entry.date = Date()
                }
                
                if entry.tags == nil {
                    entry.tags = []
                }
            }
            
            try context.save()
        } catch {
            throw CoreDataError.migrationFailed("Fehler bei der Validierung: \(error)")
        }
    }
    
    func performFullRepair() throws {
        do {
            try validateDataStore()
        } catch {
            // Wenn die Validierung fehlschlägt, versuchen wir einen Reset
            try resetStore()
        }
    }
    
    // MARK: - Store Management
    
    func resetStore() throws {
        // Stores entfernen
        for store in persistentContainer.persistentStoreCoordinator.persistentStores {
            try persistentContainer.persistentStoreCoordinator.remove(store)
        }
        
        // Store-Dateien löschen
        if let storeURL = persistentContainer.persistentStoreCoordinator.persistentStores.first?.url {
            try FileManager.default.removeItem(at: storeURL)
            try FileManager.default.removeItem(at: storeURL.deletingPathExtension().appendingPathExtension("sqlite-shm"))
            try FileManager.default.removeItem(at: storeURL.deletingPathExtension().appendingPathExtension("sqlite-wal"))
        }
        
        // Container neu laden
        persistentContainer.loadPersistentStores { (description, error) in
            if let error = error {
                print("Fehler beim Neuladen des Stores: \(error)")
            }
        }
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
        let request = NSFetchRequest<CoreDataJournalEntry>(entityName: "CoreDataJournalEntry")
        request.predicate = NSPredicate(format: "userId == %@", userId)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CoreDataJournalEntry.date, ascending: false)]
        
        do {
            let entities = try context.fetch(request)
            return entities.map { entity in
                JournalEntry(from: entity)
            }
        } catch {
            throw CoreDataError.fetchError(error.localizedDescription)
        }
    }
    
    func fetchPendingEntries(for userId: String) throws -> [JournalEntry] {
        let request = NSFetchRequest<CoreDataJournalEntry>(entityName: "CoreDataJournalEntry")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "userId == %@", userId),
            NSPredicate(format: "syncStatus == %@", SyncStatus.pendingUpload.rawValue)
        ])
        
        do {
            let entities = try context.fetch(request)
            return entities.map { entity in
                JournalEntry(from: entity)
            }
        } catch {
            throw CoreDataError.fetchError(error.localizedDescription)
        }
    }
    
    func saveJournalEntry(_ entry: JournalEntry) throws {
        let request = NSFetchRequest<CoreDataJournalEntry>(entityName: "CoreDataJournalEntry")
        request.predicate = NSPredicate(format: "id == %@", entry.id ?? "")
        
        var saveError: Error?
        
        context.performAndWait {
            do {
                let results = try context.fetch(request)
                let entity: CoreDataJournalEntry
                
                if let existingEntity = results.first {
                    // Update existing entity
                    entity = existingEntity
                } else {
                    // Create new entity
                    entity = CoreDataJournalEntry(context: context)
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
                
                // Handle images
                if let images = entry.images {
                    // Remove old images
                    if let oldImages = entity.imageRelationship as? Set<ImageEntity> {
                        for image in oldImages {
                            context.delete(image)
                        }
                    }
                    
                    // Add new images
                    let imageEntities = images.map { image in
                        let imageEntity = ImageEntity(context: context,
                                                    id: image.id,
                                                    url: image.url,
                                                    localPath: image.localPath)
                        imageEntity.uploadDate = image.uploadDate
                        imageEntity.journalEntry = entity
                        return imageEntity
                    }
                    entity.imageRelationship = NSSet(array: imageEntities)
                }
                
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
                
                // Save context
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
        let request = NSFetchRequest<CoreDataJournalEntry>(entityName: "CoreDataJournalEntry")
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
                    let fetchRequest = NSFetchRequest<CoreDataJournalEntry>(entityName: "CoreDataJournalEntry")
                    fetchRequest.predicate = NSPredicate(format: "id == %@", id)
                    
                    let results = try self.context.fetch(fetchRequest)
                    
                    if let entityToDelete = results.first {
                        self.context.delete(entityToDelete)
                        
                        if self.context.hasChanges {
                            try self.context.save()
                        }
                        continuation.resume()
                    } else {
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
            
            // Speichere ValueCompass, falls vorhanden
            entity.valueCompass = visionBoard.valueCompass
            
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
    
    // MARK: - Image Management
    
    func saveImage(for journalEntryId: String, url: String?, localPath: String?) throws -> ImageEntity {
        let request = NSFetchRequest<CoreDataJournalEntry>(entityName: "CoreDataJournalEntry")
        request.predicate = NSPredicate(format: "id == %@", journalEntryId)
        
        let results = try context.fetch(request)
        guard let journalEntry = results.first else {
            throw CoreDataError.entityNotFound
        }
        
        let imageEntity = ImageEntity(context: context,
                                    id: UUID().uuidString,
                                    url: url,
                                    localPath: localPath)
        imageEntity.journalEntry = journalEntry
        
        try context.save()
        return imageEntity
    }
    
    func deleteImage(_ image: ImageEntity) throws {
        context.delete(image)
        try context.save()
    }
    
    func updateImage(_ image: ImageEntity, url: String?, localPath: String?) throws {
        image.url = url
        image.localPath = localPath
        image.uploadDate = Date()
        
        try context.save()
    }
} 