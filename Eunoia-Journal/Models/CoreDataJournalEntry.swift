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
    @NSManaged private var _imageRelationship: NSSet?
    
    public var imageRelationship: Set<ImageEntity> {
        get {
            let set = _imageRelationship ?? NSSet()
            return set as? Set<ImageEntity> ?? Set<ImageEntity>()
        }
        set {
            _imageRelationship = newValue as NSSet
        }
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