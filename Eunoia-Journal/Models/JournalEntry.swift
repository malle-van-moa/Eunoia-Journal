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
    var id: String?
    let userId: String
    let date: Date
    var gratitude: String
    var highlight: String
    var learning: String
    var learningNugget: LearningNugget?
    var lastModified: Date
    var syncStatus: SyncStatus
    var serverTimestamp: Timestamp?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case date
        case gratitude
        case highlight
        case learning
        case learningNugget
        case lastModified
        case syncStatus
        case serverTimestamp
    }
    
    // Custom encoding to handle Timestamp
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        
        // Convert Date to dictionary representation for Timestamp
        let dateTimestamp = Timestamp(date: date)
        let dateDict: [String: Int64] = [
            "seconds": dateTimestamp.seconds,
            "nanoseconds": Int64(dateTimestamp.nanoseconds)
        ]
        try container.encode(dateDict, forKey: .date)
        
        try container.encode(gratitude, forKey: .gratitude)
        try container.encode(highlight, forKey: .highlight)
        try container.encode(learning, forKey: .learning)
        try container.encodeIfPresent(learningNugget, forKey: .learningNugget)
        
        // Convert lastModified to dictionary representation for Timestamp
        let lastModifiedTimestamp = Timestamp(date: lastModified)
        let lastModifiedDict: [String: Int64] = [
            "seconds": lastModifiedTimestamp.seconds,
            "nanoseconds": Int64(lastModifiedTimestamp.nanoseconds)
        ]
        try container.encode(lastModifiedDict, forKey: .lastModified)
        
        try container.encode(syncStatus, forKey: .syncStatus)
        
        // Only encode serverTimestamp if it exists
        if let timestamp = serverTimestamp {
            let serverDict: [String: Int64] = [
                "seconds": timestamp.seconds,
                "nanoseconds": Int64(timestamp.nanoseconds)
            ]
            try container.encode(serverDict, forKey: .serverTimestamp)
        }
    }
    
    // Custom decoding to handle Timestamp
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        
        let dateTimestamp = try container.decode([String: Int64].self, forKey: .date)
        date = Date(timeIntervalSince1970: TimeInterval(dateTimestamp["seconds"] ?? 0))
        
        gratitude = try container.decode(String.self, forKey: .gratitude)
        highlight = try container.decode(String.self, forKey: .highlight)
        learning = try container.decode(String.self, forKey: .learning)
        learningNugget = try container.decodeIfPresent(LearningNugget.self, forKey: .learningNugget)
        
        let lastModifiedTimestamp = try container.decode([String: Int64].self, forKey: .lastModified)
        lastModified = Date(timeIntervalSince1970: TimeInterval(lastModifiedTimestamp["seconds"] ?? 0))
        
        syncStatus = try container.decode(SyncStatus.self, forKey: .syncStatus)
        
        if let serverDict = try container.decodeIfPresent([String: Int64].self, forKey: .serverTimestamp) {
            serverTimestamp = Timestamp(seconds: serverDict["seconds"] ?? 0,
                                      nanoseconds: Int32(serverDict["nanoseconds"] ?? 0))
        } else {
            serverTimestamp = nil
        }
    }
    
    // Convenience initializer
    init(id: String? = nil,
         userId: String,
         date: Date,
         gratitude: String,
         highlight: String,
         learning: String,
         learningNugget: LearningNugget? = nil,
         lastModified: Date,
         syncStatus: SyncStatus,
         serverTimestamp: Timestamp? = nil) {
        self.id = id
        self.userId = userId
        self.date = date
        self.gratitude = gratitude
        self.highlight = highlight
        self.learning = learning
        self.learningNugget = learningNugget
        self.lastModified = lastModified
        self.syncStatus = syncStatus
        self.serverTimestamp = serverTimestamp
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
