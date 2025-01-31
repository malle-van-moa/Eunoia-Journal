import Foundation
import FirebaseAuth
import Combine
import FirebaseStorage
import AuthenticationServices

class AuthViewModel: ObservableObject {
    @Published var user: User?
    @Published var isAuthenticated = false
    @Published var error: Error?
    @Published var isLoading = false
    @Published var isGuestUser = false
    
    private let firebaseService = FirebaseService.shared
    private var cancellables = Set<AnyCancellable>()
    private var authStateHandler: AuthStateDidChangeListenerHandle?
    
    init() {
        setupAuthStateListener()
    }
    
    private func setupAuthStateListener() {
        authStateHandler = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.user = user
                self?.isAuthenticated = user != nil || (self?.isGuestUser ?? false)
            }
        }
    }
    
    deinit {
        if let handler = authStateHandler {
            Auth.auth().removeStateDidChangeListener(handler)
        }
    }
    
    // MARK: - Authentication Methods
    
    func continueAsGuest() {
        DispatchQueue.main.async { [weak self] in
            self?.isGuestUser = true
            self?.isAuthenticated = true
        }
    }
    
    func signUp(email: String, password: String) {
        DispatchQueue.main.async { [weak self] in
            self?.isLoading = true
            self?.error = nil
        }
        
        Task {
            do {
                let newUser = try await firebaseService.signUp(email: email, password: password)
                DispatchQueue.main.async { [weak self] in
                    self?.user = newUser
                    self?.isLoading = false
                    self?.isAuthenticated = true
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.error = error
                    self?.isLoading = false
                }
            }
        }
    }
    
    func signIn(email: String, password: String) {
        DispatchQueue.main.async { [weak self] in
            self?.isLoading = true
            self?.error = nil
        }
        
        Task {
            do {
                let signedInUser = try await firebaseService.signIn(email: email, password: password)
                DispatchQueue.main.async { [weak self] in
                    self?.user = signedInUser
                    self?.isLoading = false
                    self?.isAuthenticated = true
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.error = error
                    self?.isLoading = false
                }
            }
        }
    }
    
    func signInWithGoogle() {
        DispatchQueue.main.async { [weak self] in
            self?.isLoading = true
            self?.error = nil
        }
        
        Task {
            do {
                let googleUser = try await firebaseService.signInWithGoogle()
                DispatchQueue.main.async { [weak self] in
                    self?.user = googleUser
                    self?.isLoading = false
                    self?.isAuthenticated = true
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.error = error
                    self?.isLoading = false
                }
            }
        }
    }
    
    func startSignInWithApple() -> ASAuthorizationAppleIDRequest {
        firebaseService.startSignInWithApple()
    }
    
    func handleSignInWithApple(authorization: ASAuthorization) {
        DispatchQueue.main.async { [weak self] in
            self?.isLoading = true
            self?.error = nil
        }
        
        Task {
            do {
                let appleUser = try await firebaseService.handleSignInWithApple(authorization: authorization)
                DispatchQueue.main.async { [weak self] in
                    self?.user = appleUser
                    self?.isLoading = false
                    self?.isAuthenticated = true
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.error = error
                    self?.isLoading = false
                }
            }
        }
    }
    
    func signOut() {
        do {
            try firebaseService.signOut()
            DispatchQueue.main.async { [weak self] in
                self?.user = nil
                self?.isAuthenticated = false
                self?.isGuestUser = false
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.error = error
            }
        }
    }
    
    func resetPassword(email: String) {
        DispatchQueue.main.async { [weak self] in
            self?.isLoading = true
            self?.error = nil
        }
        
        Task {
            do {
                try await Auth.auth().sendPasswordReset(withEmail: email)
                DispatchQueue.main.async { [weak self] in
                    self?.isLoading = false
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.error = error
                    self?.isLoading = false
                }
            }
        }
    }
    
    func updateProfileImage(imageData: Data) async {
        DispatchQueue.main.async { [weak self] in
            self?.isLoading = true
            self?.error = nil
        }
        
        do {
            // Upload image to Firebase Storage
            let storageRef = Storage.storage().reference().child("profile_images/\(user?.uid ?? "")/profile.jpg")
            _ = try await storageRef.putDataAsync(imageData)
            
            // Get download URL
            let downloadURL = try await storageRef.downloadURL()
            
            // Update user profile
            let changeRequest = user?.createProfileChangeRequest()
            changeRequest?.photoURL = downloadURL
            try await changeRequest?.commitChanges()
            
            DispatchQueue.main.async { [weak self] in
                self?.isLoading = false
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.error = error
                self?.isLoading = false
            }
        }
    }
    
    var errorMessage: String {
        error?.localizedDescription ?? ""
    }
} 