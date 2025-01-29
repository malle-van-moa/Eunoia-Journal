//
//  FirestoreManager.swift
//  Eunoia-Journal
//
//  Created by Malchow, Alexander (TI-25) on 29.01.25.
//
import Foundation
import FirebaseFirestore

class FirestoreManager: ObservableObject {
    private let db = Firestore.firestore()
    
    @Published var journalEntries: [JournalEntry] = []

    // Eintrag speichern
    func addJournalEntry(_ entry: JournalEntry, completion: @escaping (Error?) -> Void) {
        do {
            let _ = try db.collection("journals").addDocument(from: entry)
            completion(nil)
        } catch {
            completion(error)
        }
    }

    // Alle Einträge abrufen
    func fetchJournalEntries(for userId: String) {
        db.collection("journals").whereField("userId", isEqualTo: userId)
            .order(by: "date", descending: true)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Fehler beim Abrufen: \(error)")
                    return
                }
                self.journalEntries = snapshot?.documents.compactMap { doc in
                    try? doc.data(as: JournalEntry.self)
                } ?? []
            }
    }
}
