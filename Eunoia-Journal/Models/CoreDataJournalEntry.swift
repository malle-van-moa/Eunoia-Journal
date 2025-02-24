import Foundation
import CoreData

@objc(CoreDataJournalEntry)
public class CoreDataJournalEntry: NSManagedObject, Identifiable {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CoreDataJournalEntry> {
        return NSFetchRequest<CoreDataJournalEntry>(entityName: "CoreDataJournalEntry")
    }
    
    @NSManaged public var id: String?
    @NSManaged public var userId: String?
    @NSManaged public var date: Date?
    @NSManaged public var gratitude: String?
    @NSManaged public var highlight: String?
    @NSManaged public var learning: String?
    @NSManaged public var lastModified: Date?
    @NSManaged public var syncStatus: String?
    @NSManaged public var title: String?
    @NSManaged public var content: String?
    @NSManaged public var location: String?
    @NSManaged public var learningNuggetCategory: String?
    @NSManaged public var learningNuggetContent: String?
    @NSManaged public var learningNuggetAddedToJournal: Bool
    @NSManaged public var tags: NSArray?
    @NSManaged public var imageRelationship: NSSet?
    
    public var images: Set<ImageEntity> {
        get {
            (imageRelationship as? Set<ImageEntity>) ?? Set<ImageEntity>()
        }
        set {
            imageRelationship = newValue as NSSet
        }
    }
    
    // Helper method to safely access images
    public func safeImageAccess() -> Set<ImageEntity> {
        return images
    }
}

// MARK: - Generated accessors for imageRelationship
extension CoreDataJournalEntry {
    @objc(addImageRelationshipObject:)
    @NSManaged public func addToImageRelationship(_ value: ImageEntity)

    @objc(removeImageRelationshipObject:)
    @NSManaged public func removeFromImageRelationship(_ value: ImageEntity)

    @objc(addImageRelationship:)
    @NSManaged public func addToImageRelationship(_ values: NSSet)

    @objc(removeImageRelationship:)
    @NSManaged public func removeFromImageRelationship(_ values: NSSet)
}

extension CoreDataJournalEntry {
    // MARK: - Safe Image Access Methods
    
    public func safelyAddImage(_ image: ImageEntity) {
        self.managedObjectContext?.performAndWait {
            addToImageRelationship(image)
            try? self.managedObjectContext?.save()
        }
    }
    
    public func safelyRemoveImage(_ image: ImageEntity) {
        self.managedObjectContext?.performAndWait {
            removeFromImageRelationship(image)
            try? self.managedObjectContext?.save()
        }
    }
    
    public func safelyRemoveAllImages() {
        self.managedObjectContext?.performAndWait {
            guard let images = imageRelationship as? Set<ImageEntity> else { return }
            removeFromImageRelationship(images as NSSet)
            try? self.managedObjectContext?.save()
        }
    }
    
    public var imageCount: Int {
        return images.count
    }
} 