import GoogleSignIn
import FirebaseAuth

class FirebaseService {
    func signInWithGoogle() async throws -> User {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthError.invalidCredential
        }
        
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        // Get the root view controller on the main thread
        let rootViewController = try await MainActor.run {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let rootViewController = window.rootViewController?.topMostViewController() else {
                throw AuthError.presentationError
            }
            return rootViewController
        }
        
        // Perform sign in on the main thread
        let result = try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                do {
                    let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        
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
} 