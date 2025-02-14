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
    
    private let authService = AuthenticationService.shared
    private let journalService = JournalService.shared
    private let visionBoardService = VisionBoardService.shared
    private let coreDataManager = CoreDataManager.shared
    private let db = Firestore.firestore()
    private var networkMonitor: NetworkMonitor?
    
    private init() {
        setupNetworkMonitoring()
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor = NetworkMonitor()
        networkMonitor?.startMonitoring()
    }
    
    // MARK: - Network State
    
    private func ensureNetworkConnection() throws {
        guard networkMonitor?.isConnected == true else {
            throw NetworkError.noConnection
        }
    }
    
    // MARK: - Authentication
    
    func signUp(email: String, password: String) async throws -> User {
        try ensureNetworkConnection()
        return try await authService.signUp(email: email, password: password)
    }
    
    func signIn(email: String, password: String) async throws -> User {
        try ensureNetworkConnection()
        return try await authService.signIn(email: email, password: password)
    }
    
    func signOut() throws {
        try ensureNetworkConnection()
        try authService.signOut()
    }
    
    func signInWithGoogle() async throws -> User {
        try await authService.signInWithGoogle()
    }
    
    func startSignInWithApple() -> ASAuthorizationAppleIDRequest {
        authService.startSignInWithApple()
    }
    
    func handleSignInWithApple(authorization: ASAuthorization) async throws -> User {
        try await authService.handleSignInWithApple(authorization: authorization)
    }
    
    // MARK: - Journal Entries
    
    func saveJournalEntry(_ entry: JournalEntry) async throws {
        try ensureNetworkConnection()
        try await journalService.saveJournalEntry(entry)
    }
    
    func fetchJournalEntries(for userId: String) async throws -> [JournalEntry] {
        try await journalService.fetchJournalEntries(for: userId)
    }
    
    func deleteJournalEntry(withId id: String) async throws {
        try await journalService.deleteJournalEntry(withId: id)
    }
    
    func observeJournalEntries(for userId: String) -> AnyPublisher<[JournalEntry], Error> {
        journalService.observeJournalEntries(for: userId)
    }
    
    // MARK: - Vision Board
    
    func saveVisionBoard(_ visionBoard: VisionBoard) async throws {
        try await visionBoardService.saveVisionBoard(visionBoard)
    }
    
    func fetchVisionBoard(for userId: String) async throws -> VisionBoard? {
        try await visionBoardService.fetchVisionBoard(for: userId)
    }
    
    func observeVisionBoard(for userId: String) -> AnyPublisher<VisionBoard?, Error> {
        visionBoardService.observeVisionBoard(for: userId)
    }
    
    // MARK: - Synchronization
    
    func syncLocalData() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        Task {
            do {
                // Sync journal entries
                let pendingEntries = coreDataManager.fetchPendingEntries(for: userId)
                for entry in pendingEntries {
                    do {
                        try await journalService.saveJournalEntry(entry)
                        print("✅ Successfully synced entry: \(entry.id ?? "unknown")")
                    } catch {
                        print("❌ Failed to sync entry: \(error.localizedDescription)")
                        continue
                    }
                }
                
                // Sync vision board if needed
                if let visionBoard = coreDataManager.fetchVisionBoard(for: userId),
                   visionBoard.syncStatus == .pendingUpload {
                    do {
                        try await visionBoardService.saveVisionBoard(visionBoard)
                        print("✅ Successfully synced vision board")
                    } catch {
                        print("❌ Failed to sync vision board: \(error.localizedDescription)")
                    }
                }
            } catch {
                print("❌ Failed to sync data: \(error.localizedDescription)")
            }
        }
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
    
    // MARK: - Network Connectivity
    
    func startNetworkMonitoring() {
        // Implement network connectivity monitoring
        // When connection is restored, call syncLocalData()
    }
} 