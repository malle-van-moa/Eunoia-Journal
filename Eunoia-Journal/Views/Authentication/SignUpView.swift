import SwiftUI

struct SignUpView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AuthViewModel
    
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPasswordMismatch = false
    
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
                    Text("Create Account")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    VStack(spacing: 20) {
                        TextField("Email", text: $email)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
                        
                        SecureField("Password", text: $password)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textContentType(.newPassword)
                        
                        SecureField("Confirm Password", text: $confirmPassword)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textContentType(.newPassword)
                        
                        Button(action: signUp) {
                            Text("Sign Up")
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
                        Text("Password must be at least 6 characters")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    
                    Spacer()
                }
                .padding()
                .navigationBarItems(trailing: Button("Cancel") {
                    dismiss()
                })
                
                // Loading Overlay
                if viewModel.isLoading {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView()
                        .scaleEffect(1.5)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.error != nil },
                set: { if !$0 { viewModel.error = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage)
            }
            .alert("Passwords Don't Match", isPresented: $showPasswordMismatch) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please make sure your passwords match.")
            }
        }
    }
    
    private var isValidInput: Bool {
        !email.isEmpty && password.count >= 6 && !confirmPassword.isEmpty
    }
    
    private func signUp() {
        guard password == confirmPassword else {
            showPasswordMismatch = true
            return
        }
        
        viewModel.signUp(email: email, password: password)
        if viewModel.isAuthenticated {
            dismiss()
        }
    }
}

#Preview {
    SignUpView(viewModel: AuthViewModel())
} 