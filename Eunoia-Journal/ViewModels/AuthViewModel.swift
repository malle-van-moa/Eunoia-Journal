import Foundation
import FirebaseAuth
import Combine

class AuthViewModel: ObservableObject {
    @Published var user: User?
    @Published var isAuthenticated = false
    @Published var error: Error?
    @Published var isLoading = false
    @Published var isGuestUser = false
    
    private let firebaseService = FirebaseService.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupAuthStateListener()
    }
    
    private func setupAuthStateListener() {
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.user = user
                self?.isAuthenticated = user != nil || (self?.isGuestUser ?? false)
            }
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
    
    var errorMessage: String {
        error?.localizedDescription ?? ""
    }
} 