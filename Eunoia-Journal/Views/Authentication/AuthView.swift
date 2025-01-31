import SwiftUI

struct AuthView: View {
    @StateObject private var viewModel = AuthViewModel()
    @State private var email = ""
    @State private var password = ""
    @State private var showSignUp = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 30) {
                    // App Logo or Title
                    Text("Eunoia")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.purple)
                    
                    Text("Welcome back!")
                        .font(.title2)
                        .fontWeight(.medium)
                    
                    // Email and Password Fields
                    VStack(spacing: 20) {
                        TextField("Email", text: $email)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
                        
                        SecureField("Password", text: $password)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textContentType(.password)
                        
                        Button(action: signIn) {
                            Text("Sign In")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.purple)
                                .cornerRadius(10)
                        }
                        .disabled(viewModel.isLoading || !isValidInput)
                    }
                    .padding(.horizontal)
                    
                    if !isValidInput {
                        Text("Please enter your email and password")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    
                    // Social Sign In Options
                    VStack(spacing: 16) {
                        Text("Or continue with")
                            .foregroundColor(.secondary)
                        
                        // Sign in with Google
                        Button(action: {
                            viewModel.signInWithGoogle()
                        }) {
                            HStack {
                                Image("google_logo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 24, height: 24)
                                Text("Sign in with Google")
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal)
                    
                    // Sign Up Link
                    Button(action: { showSignUp = true }) {
                        Text("Don't have an account? Sign Up")
                            .foregroundColor(.purple)
                            .underline()
                    }
                    .padding(.top)
                    
                    Spacer()
                }
                .padding()
                
                // Loading Overlay
                if viewModel.isLoading {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView()
                        .scaleEffect(1.5)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
            }
            .sheet(isPresented: $showSignUp) {
                SignUpView(viewModel: viewModel)
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.error != nil },
                set: { if !$0 { viewModel.error = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage)
            }
        }
    }
    
    private var isValidInput: Bool {
        !email.isEmpty && !password.isEmpty
    }
    
    private func signIn() {
        viewModel.signIn(email: email, password: password)
    }
}

#Preview {
    AuthView()
} 