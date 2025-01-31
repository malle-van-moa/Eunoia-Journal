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
        guard let id = entry.id else {
            throw FirebaseError.invalidData("Entry ID is missing")
        }
        
        // Create the dictionary manually to avoid JSON encoding issues with Timestamps
        var dict: [String: Any] = [
            "userId": entry.userId,
            "date": Timestamp(date: entry.date),
            "gratitude": entry.gratitude,
            "highlight": entry.highlight,
            "learning": entry.learning,
            "lastModified": Timestamp(date: entry.lastModified),
            "syncStatus": entry.syncStatus.rawValue
        ]
        
        // Add optional fields
        if let learningNugget = entry.learningNugget {
            let nuggetDict: [String: Any] = [
                "category": learningNugget.category.rawValue,
                "content": learningNugget.content,
                "isAddedToJournal": learningNugget.isAddedToJournal
            ]
            dict["learningNugget"] = nuggetDict
        }
        
        // Add server timestamp
        dict["serverTimestamp"] = FieldValue.serverTimestamp()
        
        do {
            try await db.collection("journalEntries").document(id).setData(dict)
            
            // Update local entry status to synced
            var updatedEntry = entry
            updatedEntry.syncStatus = .synced
            coreDataManager.saveJournalEntry(updatedEntry)
        } catch {
            throw FirebaseError.saveFailed("Failed to save entry: \(error.localizedDescription)")
        }
    }
    
    func fetchJournalEntries(for userId: String) async throws -> [JournalEntry] {
        do {
            // First try with server timestamp ordering
            do {
                let snapshot = try await db.collection("journalEntries")
                    .whereField("userId", isEqualTo: userId)
                    .order(by: "serverTimestamp", descending: true)
                    .getDocuments()
                
                return try snapshot.documents.compactMap { document -> JournalEntry? in
                    let data = document.data()
                    
                    // Extract timestamps
                    guard let dateTimestamp = data["date"] as? Timestamp,
                          let lastModifiedTimestamp = data["lastModified"] as? Timestamp,
                          let userId = data["userId"] as? String,
                          let gratitude = data["gratitude"] as? String,
                          let highlight = data["highlight"] as? String,
                          let learning = data["learning"] as? String,
                          let syncStatusRaw = data["syncStatus"] as? String,
                          let syncStatus = SyncStatus(rawValue: syncStatusRaw) else {
                        return nil
                    }
                    
                    // Handle optional learning nugget
                    var learningNugget: LearningNugget?
                    if let nuggetData = data["learningNugget"] as? [String: Any],
                       let categoryRaw = nuggetData["category"] as? String,
                       let category = LearningNugget.Category(rawValue: categoryRaw),
                       let content = nuggetData["content"] as? String,
                       let isAddedToJournal = nuggetData["isAddedToJournal"] as? Bool {
                        learningNugget = LearningNugget(
                            category: category,
                            content: content,
                            isAddedToJournal: isAddedToJournal
                        )
                    }
                    
                    // Handle server timestamp
                    let serverTimestamp = data["serverTimestamp"] as? Timestamp
                    
                    return JournalEntry(
                        id: document.documentID,
                        userId: userId,
                        date: dateTimestamp.dateValue(),
                        gratitude: gratitude,
                        highlight: highlight,
                        learning: learning,
                        learningNugget: learningNugget,
                        lastModified: lastModifiedTimestamp.dateValue(),
                        syncStatus: syncStatus,
                        serverTimestamp: serverTimestamp
                    )
                }
            } catch let error as NSError {
                // Check if error is due to missing index
                if error.domain == "FIRFirestoreErrorDomain" && error.code == 9 {
                    // Fallback to client-side sorting if index is missing
                    let snapshot = try await db.collection("journalEntries")
                        .whereField("userId", isEqualTo: userId)
                        .getDocuments()
                    
                    return try snapshot.documents.compactMap { document -> JournalEntry? in
                        let data = document.data()
                        
                        // Extract timestamps
                        guard let dateTimestamp = data["date"] as? Timestamp,
                              let lastModifiedTimestamp = data["lastModified"] as? Timestamp,
                              let userId = data["userId"] as? String,
                              let gratitude = data["gratitude"] as? String,
                              let highlight = data["highlight"] as? String,
                              let learning = data["learning"] as? String,
                              let syncStatusRaw = data["syncStatus"] as? String,
                              let syncStatus = SyncStatus(rawValue: syncStatusRaw) else {
                            return nil
                        }
                        
                        // Handle optional learning nugget
                        var learningNugget: LearningNugget?
                        if let nuggetData = data["learningNugget"] as? [String: Any],
                           let categoryRaw = nuggetData["category"] as? String,
                           let category = LearningNugget.Category(rawValue: categoryRaw),
                           let content = nuggetData["content"] as? String,
                           let isAddedToJournal = nuggetData["isAddedToJournal"] as? Bool {
                            learningNugget = LearningNugget(
                                category: category,
                                content: content,
                                isAddedToJournal: isAddedToJournal
                            )
                        }
                        
                        // Handle server timestamp
                        let serverTimestamp = data["serverTimestamp"] as? Timestamp
                        
                        return JournalEntry(
                            id: document.documentID,
                            userId: userId,
                            date: dateTimestamp.dateValue(),
                            gratitude: gratitude,
                            highlight: highlight,
                            learning: learning,
                            learningNugget: learningNugget,
                            lastModified: lastModifiedTimestamp.dateValue(),
                            syncStatus: syncStatus,
                            serverTimestamp: serverTimestamp
                        )
                    }.sorted { $0.date > $1.date }
                } else {
                    throw error
                }
            }
        } catch {
            throw FirebaseError.fetchFailed("Failed to fetch entries: \(error.localizedDescription)")
        }
    }
    
    func deleteJournalEntry(withId id: String) async throws {
        try await db.collection("journalEntries").document(id).delete()
    }
    
    // MARK: - Vision Board
    
    func saveVisionBoard(_ visionBoard: VisionBoard) async throws {
        guard let id = visionBoard.id else { return }
        
        // Create dictionary manually to avoid JSON encoding issues
        var dict: [String: Any] = [
            "userId": visionBoard.userId,
            "lastModified": Timestamp(date: visionBoard.lastModified),
            "syncStatus": visionBoard.syncStatus.rawValue
        ]
        
        // Convert personal values
        let personalValuesData = visionBoard.personalValues.map { value -> [String: Any] in
            return [
                "name": value.name,
                "description": value.description,
                "importance": value.importance
            ]
        }
        dict["personalValues"] = personalValuesData
        
        // Convert goals
        let goalsData = visionBoard.goals.map { goal -> [String: Any] in
            var goalDict: [String: Any] = [
                "title": goal.title,
                "description": goal.description,
                "category": goal.category.rawValue
            ]
            
            // Add optional target date if available
            if let targetDate = goal.targetDate {
                goalDict["targetDate"] = Timestamp(date: targetDate)
            }
            
            // Add milestones
            let milestonesData = goal.milestones.map { milestone -> [String: Any] in
                var milestoneDict: [String: Any] = [
                    "description": milestone.description,
                    "isCompleted": milestone.isCompleted
                ]
                if let targetDate = milestone.targetDate {
                    milestoneDict["targetDate"] = Timestamp(date: targetDate)
                }
                return milestoneDict
            }
            goalDict["milestones"] = milestonesData
            
            return goalDict
        }
        dict["goals"] = goalsData
        
        // Convert lifestyle vision
        let lifestyleVisionData: [String: Any] = [
            "dailyRoutine": visionBoard.lifestyleVision.dailyRoutine,
            "livingEnvironment": visionBoard.lifestyleVision.livingEnvironment,
            "workStyle": visionBoard.lifestyleVision.workStyle,
            "leisureActivities": visionBoard.lifestyleVision.leisureActivities,
            "relationships": visionBoard.lifestyleVision.relationships
        ]
        dict["lifestyleVision"] = lifestyleVisionData
        
        // Convert desired personality
        let desiredPersonalityData: [String: Any] = [
            "corePrinciples": visionBoard.desiredPersonality.corePrinciples,
            "strengths": visionBoard.desiredPersonality.strengths,
            "areasOfGrowth": visionBoard.desiredPersonality.areasOfGrowth,
            "habits": visionBoard.desiredPersonality.habits
        ]
        dict["desiredPersonality"] = desiredPersonalityData
        
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
    
    // MARK: - Error Types
    
    enum FirebaseError: LocalizedError {
        case invalidData(String)
        case saveFailed(String)
        case fetchFailed(String)
        case syncFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidData(let message),
                 .saveFailed(let message),
                 .fetchFailed(let message),
                 .syncFailed(let message):
                return message
            }
        }
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
                        try await saveJournalEntry(entry)
                        print("✅ Successfully synced entry: \(entry.id ?? "unknown")")
                    } catch {
                        print("❌ Failed to sync entry: \(error.localizedDescription)")
                        // Continue with next entry even if one fails
                        continue
                    }
                }
                
                // Sync vision board if needed
                if let visionBoard = coreDataManager.fetchVisionBoard(for: userId),
                   visionBoard.syncStatus == .pendingUpload {
                    do {
                        try await saveVisionBoard(visionBoard)
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
    
    // MARK: - Network Connectivity
    
    func startNetworkMonitoring() {
        // Implement network connectivity monitoring
        // When connection is restored, call syncLocalData()
    }
    
    // MARK: - Real-time Updates
    
    func observeJournalEntries(for userId: String) -> AnyPublisher<[JournalEntry], Error> {
        let subject = PassthroughSubject<[JournalEntry], Error>()
        
        let query = db.collection("journalEntries")
            .whereField("userId", isEqualTo: userId)
        
        query.addSnapshotListener { snapshot, error in
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
                    let data = document.data()
                    
                    // Extract timestamps
                    guard let dateTimestamp = data["date"] as? Timestamp,
                          let lastModifiedTimestamp = data["lastModified"] as? Timestamp,
                          let userId = data["userId"] as? String,
                          let gratitude = data["gratitude"] as? String,
                          let highlight = data["highlight"] as? String,
                          let learning = data["learning"] as? String,
                          let syncStatusRaw = data["syncStatus"] as? String,
                          let syncStatus = SyncStatus(rawValue: syncStatusRaw) else {
                        return nil
                    }
                    
                    // Handle optional learning nugget
                    var learningNugget: LearningNugget?
                    if let nuggetData = data["learningNugget"] as? [String: Any],
                       let categoryRaw = nuggetData["category"] as? String,
                       let category = LearningNugget.Category(rawValue: categoryRaw),
                       let content = nuggetData["content"] as? String,
                       let isAddedToJournal = nuggetData["isAddedToJournal"] as? Bool {
                        learningNugget = LearningNugget(
                            category: category,
                            content: content,
                            isAddedToJournal: isAddedToJournal
                        )
                    }
                    
                    // Handle server timestamp
                    let serverTimestamp = data["serverTimestamp"] as? Timestamp
                    
                    return JournalEntry(
                        id: document.documentID,
                        userId: userId,
                        date: dateTimestamp.dateValue(),
                        gratitude: gratitude,
                        highlight: highlight,
                        learning: learning,
                        learningNugget: learningNugget,
                        lastModified: lastModifiedTimestamp.dateValue(),
                        syncStatus: syncStatus,
                        serverTimestamp: serverTimestamp
                    )
                }.sorted { $0.date > $1.date }
                
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
                    let data = document.data()
                    
                    // Extract required fields
                    guard let userId = data["userId"] as? String,
                          let lastModifiedTimestamp = data["lastModified"] as? Timestamp,
                          let syncStatusRaw = data["syncStatus"] as? String,
                          let syncStatus = SyncStatus(rawValue: syncStatusRaw),
                          let personalValuesData = data["personalValues"] as? [[String: Any]],
                          let goalsData = data["goals"] as? [[String: Any]] else {
                        subject.send(nil)
                        return
                    }
                    
                    // Convert personal values
                    let personalValues = personalValuesData.compactMap { valueData -> PersonalValue? in
                        guard let name = valueData["name"] as? String,
                              let description = valueData["description"] as? String,
                              let importance = valueData["importance"] as? Int else {
                            return nil
                        }
                        return PersonalValue(
                            name: name,
                            description: description,
                            importance: importance
                        )
                    }
                    
                    // Convert goals
                    let goals = goalsData.compactMap { goalData -> Goal? in
                        guard let title = goalData["title"] as? String,
                              let description = goalData["description"] as? String,
                              let categoryRaw = goalData["category"] as? String,
                              let category = Goal.Category(rawValue: categoryRaw) else {
                            return nil
                        }
                        
                        // Handle optional target date
                        let targetDate = (goalData["targetDate"] as? Timestamp)?.dateValue()
                        
                        // Handle milestones
                        let milestonesData = goalData["milestones"] as? [[String: Any]] ?? []
                        let milestones = milestonesData.compactMap { milestoneData -> Milestone? in
                            guard let description = milestoneData["description"] as? String,
                                  let isCompleted = milestoneData["isCompleted"] as? Bool else {
                                return nil
                            }
                            let targetDate = (milestoneData["targetDate"] as? Timestamp)?.dateValue()
                            return Milestone(
                                description: description,
                                isCompleted: isCompleted,
                                targetDate: targetDate
                            )
                        }
                        
                        return Goal(
                            category: category,
                            title: title,
                            description: description,
                            targetDate: targetDate,
                            milestones: milestones
                        )
                    }
                    
                    // Extract lifestyle vision
                    let lifestyleVision: LifestyleVision
                    if let lifestyleData = data["lifestyleVision"] as? [String: Any],
                       let dailyRoutine = lifestyleData["dailyRoutine"] as? String,
                       let livingEnvironment = lifestyleData["livingEnvironment"] as? String,
                       let workStyle = lifestyleData["workStyle"] as? String,
                       let leisureActivities = lifestyleData["leisureActivities"] as? [String],
                       let relationships = lifestyleData["relationships"] as? String {
                        lifestyleVision = LifestyleVision(
                            dailyRoutine: dailyRoutine,
                            livingEnvironment: livingEnvironment,
                            workStyle: workStyle,
                            leisureActivities: leisureActivities,
                            relationships: relationships
                        )
                    } else {
                        lifestyleVision = LifestyleVision(
                            dailyRoutine: "",
                            livingEnvironment: "",
                            workStyle: "",
                            leisureActivities: [],
                            relationships: ""
                        )
                    }
                    
                    // Extract desired personality
                    let desiredPersonality: DesiredPersonality
                    if let personalityData = data["desiredPersonality"] as? [String: Any],
                       let corePrinciples = personalityData["corePrinciples"] as? [String],
                       let strengths = personalityData["strengths"] as? [String],
                       let areasOfGrowth = personalityData["areasOfGrowth"] as? [String],
                       let habits = personalityData["habits"] as? [String] {
                        desiredPersonality = DesiredPersonality(
                            corePrinciples: corePrinciples,
                            strengths: strengths,
                            areasOfGrowth: areasOfGrowth,
                            habits: habits
                        )
                    } else {
                        desiredPersonality = DesiredPersonality(
                            corePrinciples: [],
                            strengths: [],
                            areasOfGrowth: [],
                            habits: []
                        )
                    }
                    
                    let visionBoard = VisionBoard(
                        id: document.documentID,
                        userId: userId,
                        lastModified: lastModifiedTimestamp.dateValue(),
                        personalValues: personalValues,
                        goals: goals,
                        lifestyleVision: lifestyleVision,
                        desiredPersonality: desiredPersonality,
                        syncStatus: syncStatus
                    )
                    
                    subject.send(visionBoard)
                } catch {
                    subject.send(completion: .failure(error))
                }
            }
        
        return subject.eraseToAnyPublisher()
    }
} 