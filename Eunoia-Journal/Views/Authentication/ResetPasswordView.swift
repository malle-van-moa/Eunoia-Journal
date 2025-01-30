import SwiftUI

struct ResetPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AuthViewModel
    
    @State private var email = ""
    @State private var showSuccessAlert = false
    
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
                    Text("Reset Password")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Enter your email address and we'll send you a link to reset your password.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    
                    VStack(spacing: 20) {
                        TextField("Email", text: $email)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
                        
                        Button(action: resetPassword) {
                            Text("Send Reset Link")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.purple)
                                .cornerRadius(10)
                        }
                        .disabled(viewModel.isLoading || email.isEmpty)
                    }
                    .padding(.horizontal)
                    
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
            .alert("Check Your Email", isPresented: $showSuccessAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("We've sent you an email with instructions to reset your password.")
            }
        }
    }
    
    private func resetPassword() {
        viewModel.resetPassword(email: email)
        showSuccessAlert = true
    }
}

#Preview {
    ResetPasswordView(viewModel: AuthViewModel())
} 