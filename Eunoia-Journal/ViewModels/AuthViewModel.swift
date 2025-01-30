import Foundation
import FirebaseAuth
import Combine
import FirebaseStorage

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
    
    func continueAsGuest() {
        isGuestUser = true
        isAuthenticated = true
    }
    
    func signUp(email: String, password: String) {
        isLoading = true
        error = nil
        
        Task {
            do {
                self.user = try await firebaseService.signUp(email: email, password: password)
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.isAuthenticated = true
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = error
                    self.isLoading = false
                }
            }
        }
    }
    
    func signIn(email: String, password: String) {
        isLoading = true
        error = nil
        
        Task {
            do {
                self.user = try await firebaseService.signIn(email: email, password: password)
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.isAuthenticated = true
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = error
                    self.isLoading = false
                }
            }
        }
    }
    
    func signOut() {
        do {
            try firebaseService.signOut()
            self.user = nil
            self.isAuthenticated = false
        } catch {
            self.error = error
        }
    }
    
    func resetPassword(email: String) {
        isLoading = true
        error = nil
        
        Task {
            do {
                try await Auth.auth().sendPasswordReset(withEmail: email)
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = error
                    self.isLoading = false
                }
            }
        }
    }
    
    func updateProfileImage(imageData: Data) async {
        isLoading = true
        error = nil
        
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
            
            DispatchQueue.main.async {
                self.isLoading = false
            }
        } catch {
            DispatchQueue.main.async {
                self.error = error
                self.isLoading = false
            }
        }
    }
    
    var errorMessage: String {
        error?.localizedDescription ?? ""
    }
} 