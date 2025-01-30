import SwiftUI

struct AuthView: View {
    @EnvironmentObject var viewModel: AuthViewModel
    @State private var isShowingSignUp = false
    @State private var isShowingResetPassword = false
    @State private var email = ""
    @State private var password = ""
    
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
                    // Logo and Title
                    VStack(spacing: 20) {
                        Image(systemName: "book.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.purple)
                        
                        Text("Eunoia Journal")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Reflect, Grow, Transform")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 50)
                    
                    // Login Form
                    VStack(spacing: 20) {
                        TextField("Email", text: $email)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
                        
                        SecureField("Password", text: $password)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textContentType(.password)
                        
                        Button(action: {
                            viewModel.signIn(email: email, password: password)
                        }) {
                            Text("Sign In")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.purple)
                                .cornerRadius(10)
                        }
                        .disabled(viewModel.isLoading)
                        
                        Button("Forgot Password?") {
                            isShowingResetPassword = true
                        }
                        .foregroundColor(.purple)
                    }
                    .padding(.horizontal)
                    
                    // Sign Up Option
                    VStack {
                        Text("Don't have an account?")
                            .foregroundColor(.secondary)
                        
                        Button("Create Account") {
                            isShowingSignUp = true
                        }
                        .foregroundColor(.purple)
                        .fontWeight(.semibold)
                    }
                    
                    // Guest Mode Option
                    Button(action: {
                        viewModel.continueAsGuest()
                    }) {
                        Text("Continue as Guest")
                            .foregroundColor(.gray)
                            .padding(.top)
                    }
                    
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
            .sheet(isPresented: $isShowingSignUp) {
                SignUpView(viewModel: viewModel)
            }
            .sheet(isPresented: $isShowingResetPassword) {
                ResetPasswordView(viewModel: viewModel)
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
}

#Preview {
    AuthView()
} 