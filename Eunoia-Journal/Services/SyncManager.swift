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
    
    func syncOfflineEntries() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let pendingEntries = coreDataManager.fetchPendingEntries(for: userId)
        
        for entry in pendingEntries {
            Task {
                do {
                    try await firebaseService.saveJournalEntry(entry)
                    print("✅ Entry successfully synced to Firestore: \(entry.id ?? "unknown")")
                } catch {
                    print("❌ Error syncing entry: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func startAutoSync() {
        // Check for pending entries every 5 minutes when online
        Timer.publish(every: 300, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.syncOfflineEntries()
            }
            .store(in: &cancellables)
    }
    
    func stopAutoSync() {
        cancellables.removeAll()
    }
}
