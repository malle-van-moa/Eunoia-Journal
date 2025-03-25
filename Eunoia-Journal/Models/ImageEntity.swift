import Foundation
import CoreData

@objc(ImageEntity)
public class ImageEntity: NSManagedObject, Identifiable {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ImageEntity> {
        return NSFetchRequest<ImageEntity>(entityName: "ImageEntity")
    }
    
    @NSManaged public var id: String?
    @NSManaged public var url: String?
    @NSManaged public var localPath: String?
    @NSManaged public var uploadDate: Date?
    @NSManaged public var journalEntry: CoreDataJournalEntry?
    
    // Convenience initializer
    convenience init(context: NSManagedObjectContext, id: String, url: String? = nil, localPath: String? = nil) {
        let entity = NSEntityDescription.entity(forEntityName: "ImageEntity", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = id
        self.url = url
        self.localPath = localPath
        self.uploadDate = Date()
    }
} 