import Foundation
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth
import Combine
import AuthenticationServices
import GoogleSignIn
import CryptoKit
import CoreData
import UIKit

class FirebaseService {
    static let shared = FirebaseService()
    
    private let authService = AuthenticationService.shared
    private let journalService = JournalService.shared
    private let visionBoardService = VisionBoardService.shared
    private let coreDataManager = CoreDataManager.shared
    private let db: Firestore
    private let networkMonitor = NetworkMonitor.shared
    
    private var cancellables = Set<AnyCancellable>()
    private var appStateObservers = Set<AnyCancellable>()
    
    private init() {
        // Konfiguriere Firestore
        let settings = FirestoreSettings()
        settings.isPersistenceEnabled = true
        
        // Cache-Größe als NSNumber (100 MB)
        let cacheSize: Int64 = 100 * 1024 * 1024
        settings.cacheSettings = PersistentCacheSettings(sizeBytes: NSNumber(value: cacheSize))
        
        let db = Firestore.firestore()
        db.settings = settings
        self.db = db
        
        setupNetworkMonitoring()
        setupAppStateObservers()
        
        #if DEBUG
        print("Firestore konfiguriert mit Persistence und \(cacheSize / 1024 / 1024) MB Cache")
        #endif
    }
    
    private func setupNetworkMonitoring() {
        // Stoppe vorherige Überwachung, um sicherzustellen, dass keine doppelten Verbindungen bestehen
        networkMonitor.stopMonitoring()
        
        // Starte Netzwerküberwachung mit verbesserter Fehlerbehandlung
        networkMonitor.startMonitoring { [weak self] isConnected in
            guard let self = self else { return }
            
            if isConnected {
                // Wenn Verbindung hergestellt wurde, synchronisiere lokale Daten
                self.syncLocalData()
            } else {
                // Wenn Verbindung verloren wurde, logge dies
                print("⚠️ Netzwerkverbindung verloren. Offline-Modus aktiviert.")
            }
        }
    }
    
    private func setupAppStateObservers() {
        // Entferne bestehende Observer
        appStateObservers.removeAll()
        
        // Beobachte App-Zustandsänderungen
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                self?.handleAppBackgrounding()
            }
            .store(in: &appStateObservers)
        
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.handleAppForegrounding()
            }
            .store(in: &appStateObservers)
    }
    
    private func handleAppBackgrounding() {
        print("📱 App wechselt in den Hintergrund - Pausiere Firestore-Streams")
        
        // Statt die Firestore-Einstellungen zu ändern, entfernen wir alle aktiven Listener
        // und speichern den aktuellen Zustand, falls nötig
        
        // Speichere ausstehende Änderungen
        if let userId = Auth.auth().currentUser?.uid {
            Task {
                do {
                    // Prüfe, ob ausstehende Änderungen vorhanden sind
                    let pendingEntries = try coreDataManager.fetchPendingEntries(for: userId)
                    if !pendingEntries.isEmpty {
                        print("📝 \(pendingEntries.count) ausstehende Einträge gespeichert für spätere Synchronisation")
                    }
                } catch {
                    print("⚠️ Fehler beim Prüfen auf ausstehende Änderungen: \(error.localizedDescription)")
                }
            }
        }
        
        // Wir setzen keine Firestore-Einstellungen mehr, da dies nach der Initialisierung nicht erlaubt ist
    }
    
    private func handleAppForegrounding() {
        print("📱 App kehrt in den Vordergrund zurück - Stelle Firestore-Streams wieder her")
        
        // Überprüfe Netzwerkverbindung und synchronisiere bei Bedarf
        if networkMonitor.isNetworkAvailable {
            syncLocalData()
        }
        
        // Stelle sicher, dass die Subscriptions neu aufgebaut werden
        if let userId = Auth.auth().currentUser?.uid {
            // Benachrichtige die ViewModels, dass sie ihre Subscriptions neu aufbauen sollen
            NotificationCenter.default.post(name: NSNotification.Name("RefreshFirestoreSubscriptions"), object: nil)
        }
    }
    
    // MARK: - Network State
    
    private func ensureNetworkConnection() throws {
        guard networkMonitor.isNetworkAvailable else {
            print("⚠️ Keine Netzwerkverbindung verfügbar. Operation wird in den Offline-Modus verschoben.")
            throw NetworkError.noConnection
        }
    }
    
    /// Wartet auf eine Netzwerkverbindung mit Timeout
    /// - Parameter timeout: Timeout in Sekunden
    /// - Returns: Publisher, der true zurückgibt, wenn eine Verbindung hergestellt wurde
    private func waitForNetworkConnection(timeout: TimeInterval = 10.0) -> AnyPublisher<Bool, Never> {
        return networkMonitor.waitForConnection(timeout: timeout)
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
        // Prüfe zuerst, ob eine Netzwerkverbindung verfügbar ist
        if !networkMonitor.isNetworkAvailable {
            print("⚠️ Keine Netzwerkverbindung verfügbar. Verwende lokale Daten.")
            
            // Versuche, lokale Daten aus CoreData zu laden
            do {
                let localEntries = try coreDataManager.fetchJournalEntries(for: userId)
                return Just(localEntries)
                    .setFailureType(to: Error.self)
                    .eraseToAnyPublisher()
            } catch {
                print("⚠️ Fehler beim Laden lokaler Daten: \(error.localizedDescription)")
            }
            
            // Warte auf Netzwerkverbindung und versuche dann erneut
            return waitForNetworkConnection()
                .filter { $0 }
                .flatMap { [weak self] _ -> AnyPublisher<[JournalEntry], Error> in
                    guard let self = self else {
                        return Fail(error: NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "FirebaseService wurde freigegeben"]))
                            .eraseToAnyPublisher()
                    }
                    return self.journalService.observeJournalEntries(for: userId)
                }
                .eraseToAnyPublisher()
        }
        
        // Wenn Netzwerkverbindung verfügbar ist, verwende den normalen Pfad
        return journalService.observeJournalEntries(for: userId)
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
                // Prüfe zuerst, ob eine Netzwerkverbindung verfügbar ist
                guard networkMonitor.isNetworkAvailable else {
                    print("⚠️ Keine Netzwerkverbindung verfügbar. Synchronisation wird verschoben.")
                    return
                }
                
                // Sync journal entries
                let pendingEntries = try coreDataManager.fetchPendingEntries(for: userId)
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