//
//  SyncManager.swift
//  Eunoia-Journal
//
//  Created by Malchow, Alexander (TI-25) on 29.01.25.
//
import FirebaseFirestore
import CoreData
import Foundation

class SyncManager {
    private let db = Firestore.firestore()
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // 🔥 Funktion zur Synchronisierung von Core Data → Firestore
    func syncOfflineEntries() {
        let request = CoreDataJournalEntry.fetchRequest()

        do {
            let offlineEntries = try context.fetch(request)

            for entry in offlineEntries {
                let journalEntry: [String: Any] = [
                    "userId": "user_abc",
                    "title": entry.title ?? "",
                    "content": entry.content ?? "",
                    "date": Timestamp(date: entry.date ?? Date()),
                    "tags": entry.tags as? [String] ?? [],
                    "images": entry.images as? [String] ?? []
                ]

                // Eintrag in Firestore speichern
                db.collection("journals").addDocument(data: journalEntry) { error in
                    if let error = error {
                        print("❌ Fehler beim Hochladen: \(error.localizedDescription)")
                    } else {
                        print("✅ Eintrag erfolgreich in Firestore gespeichert!")

                        // Erfolgreich synchronisiert → aus Core Data löschen
                        self.context.delete(entry)
                        do {
                            try self.context.save()
                            print("🗑️ Lokaler Eintrag gelöscht")
                        } catch {
                            print("❌ Fehler beim Löschen: \(error.localizedDescription)")
                        }
                    }
                }
            }
        } catch {
            print("❌ Fehler beim Abrufen der Core Data Einträge: \(error.localizedDescription)")
        }
    }

    func syncEntries() {
        // Erstellen Sie einen Fetch Request für alle CoreDataJournalEntry Objekte
        let request = CoreDataJournalEntry.fetchRequest()
        
        do {
            let entries = try context.fetch(request)
            // Weitere Verarbeitung der Einträge...
        } catch {
            print("Fehler beim Abrufen der Einträge: \(error)")
        }
    }
}
