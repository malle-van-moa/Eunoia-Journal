import Foundation
import UIKit
import FirebaseCore
import FirebaseAuth
import GoogleSignIn
import AuthenticationServices
import CryptoKit

class AuthenticationService {
    static let shared = AuthenticationService()
    
    var currentUser: User? {
        Auth.auth().currentUser
    }
    
    private init() {}
    
    // MARK: - Authentication Methods
    
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
        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                do {
                    guard let clientID = FirebaseApp.app()?.options.clientID else {
                        throw AuthError.invalidCredential
                    }
                    
                    let config = GIDConfiguration(clientID: clientID)
                    GIDSignIn.sharedInstance.configuration = config
                    
                    // Get the root view controller
                    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                          let window = windowScene.windows.first,
                          let rootViewController = window.rootViewController?.topMostViewController() else {
                        throw AuthError.presentationError
                    }
                    
                    let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
                    
                    guard let idToken = result.user.idToken?.tokenString else {
                        throw AuthError.invalidCredential
                    }
                    
                    let credential = GoogleAuthProvider.credential(
                        withIDToken: idToken,
                        accessToken: result.user.accessToken.tokenString
                    )
                    
                    let authResult = try await Auth.auth().signIn(with: credential)
                    continuation.resume(returning: authResult.user)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
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
    
    private var currentNonce: String?
    
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
}

// MARK: - UIViewController Extension
private extension UIViewController {
    func topMostViewController() -> UIViewController {
        if let presented = self.presentedViewController {
            return presented.topMostViewController()
        }
        
        if let navigation = self as? UINavigationController {
            return navigation.visibleViewController?.topMostViewController() ?? navigation
        }
        
        if let tab = self as? UITabBarController {
            return tab.selectedViewController?.topMostViewController() ?? tab
        }
        
        return self
    }
} 