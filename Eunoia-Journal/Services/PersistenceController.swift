//
//  PersistenceController.swift
//  Eunoia-Journal
//
//  Created by Malchow, Alexander (TI-25) on 29.01.25.
//
import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init() {
        // 🔥 Registriere die Transformer für sichere Speicherung
        TagsTransformer.register()
        ImagesTransformer.register()
        
        container = NSPersistentContainer(name: "EunoiaModel")
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Fehler beim Laden des Core Data Stores: \(error)")
            }
        }
    }
    
    // 🔥 Funktion zum Speichern eines Eintrags in Core Data
    func saveEntryLocally(title: String, content: String, tags: [String], images: [String]) {
        let context = container.viewContext
        let entry = CoreDataJournalEntry(context: context)
        
        entry.id = UUID().uuidString
        entry.title = title
        entry.content = content
        entry.date = Date()
        entry.tags = tags as NSObject  // Core Data speichert Arrays als NSObject
        entry.images = images as NSObject

        do {
            try context.save()
            print("✅ Eintrag erfolgreich lokal gespeichert.")
        } catch {
            print("❌ Fehler beim Speichern: \(error.localizedDescription)")
        }
    }
}

