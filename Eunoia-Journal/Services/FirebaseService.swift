import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

class FirebaseService {
    static let shared = FirebaseService()
    
    private let db = Firestore.firestore()
    private let coreDataManager = CoreDataManager.shared
    
    private init() {}
    
    // MARK: - Authentication
    
    func signUp(email: String, password: String) async throws -> User {
        let authResult = try await Auth.auth().createUser(withEmail: email, password: password)
        return authResult.user
    }
    
    func signIn(email: String, password: String) async throws -> User {
        let authResult = try await Auth.auth().signIn(withEmail: email, password: password)
        return authResult.user
    }
    
    func signOut() throws {
        try Auth.auth().signOut()
    }
    
    // MARK: - Journal Entries
    
    func saveJournalEntry(_ entry: JournalEntry) async throws {
        guard let id = entry.id else { return }
        
        let data = try JSONEncoder().encode(entry)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        
        try await db.collection("journalEntries").document(id).setData(dict)
        
        // Update local entry status to synced
        var updatedEntry = entry
        updatedEntry.syncStatus = .synced
        coreDataManager.saveJournalEntry(updatedEntry)
    }
    
    func fetchJournalEntries(for userId: String) async throws -> [JournalEntry] {
        let snapshot = try await db.collection("journalEntries")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        
        return try snapshot.documents.compactMap { document in
            let data = try JSONSerialization.data(withJSONObject: document.data())
            var entry = try JSONDecoder().decode(JournalEntry.self, from: data)
            entry.id = document.documentID
            return entry
        }
    }
    
    func deleteJournalEntry(withId id: String) async throws {
        try await db.collection("journalEntries").document(id).delete()
    }
    
    // MARK: - Vision Board
    
    func saveVisionBoard(_ visionBoard: VisionBoard) async throws {
        guard let id = visionBoard.id else { return }
        
        let data = try JSONEncoder().encode(visionBoard)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        
        try await db.collection("visionBoards").document(id).setData(dict)
        
        // Update local vision board status to synced
        var updatedVisionBoard = visionBoard
        updatedVisionBoard.syncStatus = .synced
        coreDataManager.saveVisionBoard(updatedVisionBoard)
    }
    
    func fetchVisionBoard(for userId: String) async throws -> VisionBoard? {
        let snapshot = try await db.collection("visionBoards")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        
        guard let document = snapshot.documents.first else { return nil }
        
        let data = try JSONSerialization.data(withJSONObject: document.data())
        var visionBoard = try JSONDecoder().decode(VisionBoard.self, from: data)
        visionBoard.id = document.documentID
        return visionBoard
    }
    
    // MARK: - Synchronization
    
    func syncUnsyncedData() async {
        // Sync unsynced journal entries
        let unsyncedEntries = coreDataManager.fetchUnsyncedJournalEntries()
        for entry in unsyncedEntries {
            do {
                try await saveJournalEntry(entry)
            } catch {
                print("Error syncing journal entry: \(error)")
            }
        }
        
        // Sync vision board if needed
        if let currentUser = Auth.auth().currentUser,
           let visionBoard = coreDataManager.fetchVisionBoard(for: currentUser.uid),
           visionBoard.syncStatus != .synced {
            do {
                try await saveVisionBoard(visionBoard)
            } catch {
                print("Error syncing vision board: \(error)")
            }
        }
    }
    
    // MARK: - Network Connectivity
    
    func startNetworkMonitoring() {
        // Implement network connectivity monitoring
        // When connection is restored, call syncUnsyncedData()
    }
    
    // MARK: - Real-time Updates
    
    func observeJournalEntries(for userId: String) -> AnyPublisher<[JournalEntry], Error> {
        let subject = PassthroughSubject<[JournalEntry], Error>()
        
        db.collection("journalEntries")
            .whereField("userId", isEqualTo: userId)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    subject.send(completion: .failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    subject.send([])
                    return
                }
                
                do {
                    let entries = try documents.compactMap { document -> JournalEntry? in
                        let data = try JSONSerialization.data(withJSONObject: document.data())
                        var entry = try JSONDecoder().decode(JournalEntry.self, from: data)
                        entry.id = document.documentID
                        return entry
                    }
                    subject.send(entries)
                } catch {
                    subject.send(completion: .failure(error))
                }
            }
        
        return subject.eraseToAnyPublisher()
    }
    
    func observeVisionBoard(for userId: String) -> AnyPublisher<VisionBoard?, Error> {
        let subject = PassthroughSubject<VisionBoard?, Error>()
        
        db.collection("visionBoards")
            .whereField("userId", isEqualTo: userId)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    subject.send(completion: .failure(error))
                    return
                }
                
                guard let document = snapshot?.documents.first else {
                    subject.send(nil)
                    return
                }
                
                do {
                    let data = try JSONSerialization.data(withJSONObject: document.data())
                    var visionBoard = try JSONDecoder().decode(VisionBoard.self, from: data)
                    visionBoard.id = document.documentID
                    subject.send(visionBoard)
                } catch {
                    subject.send(completion: .failure(error))
                }
            }
        
        return subject.eraseToAnyPublisher()
    }
} 