//
//  JournalEntry.swift
//  Eunoia-Journal
//
//  Created by Malchow, Alexander (TI-25) on 29.01.25.
//
import Foundation
import FirebaseFirestore

struct JournalEntry: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var title: String
    var content: String
    var date: Date
    var tags: [String]
    var images: [String]
}
