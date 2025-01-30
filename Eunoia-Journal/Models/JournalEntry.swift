//
//  JournalEntry.swift
//  Eunoia-Journal
//
//  Created by Malchow, Alexander (TI-25) on 29.01.25.
//
import Foundation
import FirebaseCore
import FirebaseFirestore

struct JournalEntry: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var date: Date
    var gratitude: String
    var highlight: String
    var learning: String
    var learningNugget: LearningNugget?
    var lastModified: Date
    var syncStatus: SyncStatus
    
    enum SyncStatus: String, Codable {
        case synced
        case pendingUpload
        case pendingUpdate
    }
}

struct LearningNugget: Codable {
    var category: Category
    var content: String
    var isAddedToJournal: Bool
    
    enum Category: String, Codable, CaseIterable {
        case nature
        case science
        case psychology
        case history
    }
}

// Extension for Core Data conversion
extension JournalEntry {
    init(from entity: JournalEntryEntity) {
        self.id = entity.id
        self.userId = entity.userId ?? ""
        self.date = entity.date ?? Date()
        self.gratitude = entity.gratitude ?? ""
        self.highlight = entity.highlight ?? ""
        self.learning = entity.learning ?? ""
        self.lastModified = entity.lastModified ?? Date()
        self.syncStatus = SyncStatus(rawValue: entity.syncStatus ?? "pendingUpload") ?? .pendingUpload
        
        if let nuggetCategory = entity.learningNuggetCategory,
           let nuggetContent = entity.learningNuggetContent {
            self.learningNugget = LearningNugget(
                category: LearningNugget.Category(rawValue: nuggetCategory) ?? .nature,
                content: nuggetContent,
                isAddedToJournal: entity.learningNuggetAddedToJournal
            )
        }
    }
}
