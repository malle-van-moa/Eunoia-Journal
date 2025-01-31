import Foundation
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth
import Combine
import AuthenticationServices
import GoogleSignIn
import CryptoKit

class FirebaseService {
    static let shared = FirebaseService()
    
    private let db = Firestore.firestore()
    private let coreDataManager = CoreDataManager.shared
    private var currentNonce: String?
    
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
        GIDSignIn.sharedInstance.signOut()
    }
    
    // MARK: - Google Sign In
    
    func signInWithGoogle() async throws -> User {
        guard let clientID = FirebaseApp.app()?.options.clientID,
              let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            throw AuthError.presentationError
        }
        
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.invalidCredential
        }
        
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        
        let authResult = try await Auth.auth().signIn(with: credential)
        return authResult.user
    }
    
    // MARK: - Apple Sign In
    
    func startSignInWithApple() -> ASAuthorizationAppleIDRequest {
        let nonce = randomNonceString()
        currentNonce = nonce
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        return request
    }
    
    func handleSignInWithApple(authorization: ASAuthorization) async throws -> User {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let nonce = currentNonce,
              let appleIDToken = appleIDCredential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            throw AuthError.invalidCredential
        }
        
        let credential = OAuthProvider.credential(
            withProviderID: "apple.com",
            idToken: idTokenString,
            rawNonce: nonce
        )
        
        let authResult = try await Auth.auth().signIn(with: credential)
        
        // Optional: Save user's full name if provided
        if let fullName = appleIDCredential.fullName {
            let changeRequest = authResult.user.createProfileChangeRequest()
            changeRequest.displayName = [
                fullName.givenName,
                fullName.familyName
            ].compactMap { $0 }.joined(separator: " ")
            try await changeRequest.commitChanges()
        }
        
        return authResult.user
    }
    
    // MARK: - Helper Methods
    
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                }
                return random
            }
            
            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }
                
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        
        return result
    }
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        
        return hashString
    }
    
    // MARK: - Error Types
    
    enum AuthError: Error {
        case invalidCredential
        case presentationError
        
        var localizedDescription: String {
            switch self {
            case .invalidCredential:
                return "Invalid credentials provided."
            case .presentationError:
                return "Unable to present authentication flow."
            }
        }
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