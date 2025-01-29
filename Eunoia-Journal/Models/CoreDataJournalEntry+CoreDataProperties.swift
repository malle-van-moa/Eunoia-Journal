//
//  CoreDataJournalEntry+CoreDataProperties.swift
//  Eunoia-Journal
//
//  Created by Malchow, Alexander (TI-25) on 29.01.25.
//
//

import Foundation
import CoreData


extension CoreDataJournalEntry {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CoreDataJournalEntry> {
        return NSFetchRequest<CoreDataJournalEntry>(entityName: "CoreDataJournalEntry")
    }

    @NSManaged public var content: String?
    @NSManaged public var date: Date?
    @NSManaged public var id: String?
    @NSManaged public var images: NSObject?
    @NSManaged public var title: String?
    @NSManaged public var userId: String?
    @NSManaged public var tags: NSObject?

}

extension CoreDataJournalEntry : Identifiable {

}
