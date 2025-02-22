//
//  SyncManager.swift
//  Eunoia-Journal
//
//  Created by Malchow, Alexander (TI-25) on 29.01.25.
//
import FirebaseFirestore
import FirebaseAuth
import CoreData
import Foundation
import Combine

class SyncManager {
    static let shared = SyncManager()
    
    private let firebaseService = FirebaseService.shared
    private let coreDataManager = CoreDataManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    private init() {}
    
    // MARK: - Sync Methods
    
    func syncOfflineEntries() async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let pendingEntries = try coreDataManager.fetchPendingEntries(for: userId)
        
        for entry in pendingEntries {
            do {
                try await syncSingleEntry(entry)
            } catch {
                print("❌ Failed to sync entry \(entry.id ?? "unknown"): \(error)")
                throw error  // Propagate the error up
            }
        }
    }
    
    private func syncSingleEntry(_ entry: JournalEntry) async throws {
        do {
            try await firebaseService.saveJournalEntry(entry)
            print("✅ Entry successfully synced to Firestore: \(entry.id ?? "unknown")")
        } catch {
            print("❌ Error syncing entry: \(error.localizedDescription)")
            // Exponentieller Backoff für Retry
            try await Task.sleep(nanoseconds: 5_000_000_000) // 5 Sekunden Wartezeit
            do {
                try await firebaseService.saveJournalEntry(entry)
                print("✅ Retry successful for entry: \(entry.id ?? "unknown")")
            } catch {
                print("❌ Final retry failed for entry: \(entry.id ?? "unknown")")
                throw error // Propagate the error up
            }
        }
    }
    
    func startAutoSync() {
        // Check for pending entries every 5 minutes when online
        Timer.publish(every: 300, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    do {
                        try await self?.syncOfflineEntries()
                    } catch {
                        print("❌ Auto-Sync fehlgeschlagen: \(error.localizedDescription)")
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    func stopAutoSync() {
        cancellables.removeAll()
    }
}
