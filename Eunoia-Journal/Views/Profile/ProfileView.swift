import SwiftUI
import FirebaseAuth

struct ProfileView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @State private var showingLogoutConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var showingNotificationSettings = false
    @State private var showingAbout = false
    @State private var showingPrivacyPolicy = false
    
    var body: some View {
        List {
            // Account Section
            Section("Account") {
                if let user = authViewModel.user {
                    HStack {
                        Text("Email")
                        Spacer()
                        Text(user.email ?? "")
                            .foregroundColor(.secondary)
                    }
                }
                
                Button(role: .destructive) {
                    showingLogoutConfirmation = true
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            
            // Notifications Section
            Section("Notifications") {
                Button {
                    showingNotificationSettings = true
                } label: {
                    Label("Notification Settings", systemImage: "bell")
                }
            }
            
            // App Settings Section
            Section("App Settings") {
                NavigationLink {
                    NotificationScheduleView()
                } label: {
                    Label("Journal Reminders", systemImage: "clock")
                }
                
                NavigationLink {
                    DataManagementView()
                } label: {
                    Label("Data Management", systemImage: "externaldrive")
                }
            }
            
            // Information Section
            Section("Information") {
                Button {
                    showingAbout = true
                } label: {
                    Label("About Eunoia", systemImage: "info.circle")
                }
                
                Button {
                    showingPrivacyPolicy = true
                } label: {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
                
                Link(destination: URL(string: "mailto:support@eunoia-app.com")!) {
                    Label("Contact Support", systemImage: "envelope")
                }
            }
            
            // Danger Zone
            Section {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete Account", systemImage: "person.crop.circle.badge.minus")
                }
            } header: {
                Text("Danger Zone")
            } footer: {
                Text("Deleting your account will permanently remove all your data.")
            }
        }
        .navigationTitle("Profile")
        .alert("Sign Out", isPresented: $showingLogoutConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                authViewModel.signOut()
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .alert("Delete Account", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                // TODO: Implement account deletion
            }
        } message: {
            Text("This action cannot be undone. All your data will be permanently deleted.")
        }
        .sheet(isPresented: $showingNotificationSettings) {
            NavigationView {
                NotificationSettingsView()
            }
        }
        .sheet(isPresented: $showingAbout) {
            NavigationView {
                AboutView()
            }
        }
        .sheet(isPresented: $showingPrivacyPolicy) {
            NavigationView {
                PrivacyPolicyView()
            }
        }
    }
}

// MARK: - Supporting Views

struct NotificationScheduleView: View {
    @State private var isEnabled = true
    @State private var selectedTime = Date()
    @State private var selectedDays: Set<Int> = [1, 2, 3, 4, 5, 6, 7]
    
    let weekdays = [
        (1, "Sunday"),
        (2, "Monday"),
        (3, "Tuesday"),
        (4, "Wednesday"),
        (5, "Thursday"),
        (6, "Friday"),
        (7, "Saturday")
    ]
    
    var body: some View {
        Form {
            Section {
                Toggle("Enable Daily Reminders", isOn: $isEnabled)
                
                if isEnabled {
                    DatePicker(
                        "Reminder Time",
                        selection: $selectedTime,
                        displayedComponents: .hourAndMinute
                    )
                }
            }
            
            Section("Repeat On") {
                ForEach(weekdays, id: \.0) { day in
                    Toggle(day.1, isOn: Binding(
                        get: { selectedDays.contains(day.0) },
                        set: { isSelected in
                            if isSelected {
                                selectedDays.insert(day.0)
                            } else {
                                selectedDays.remove(day.0)
                            }
                        }
                    ))
                }
            }
        }
        .navigationTitle("Journal Reminders")
        .onChange(of: isEnabled) { newValue in
            if newValue {
                // TODO: Schedule notifications
            } else {
                // TODO: Cancel notifications
            }
        }
    }
}

struct NotificationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var journalReminders = true
    @State private var streakAlerts = true
    @State private var weeklyDigest = true
    
    var body: some View {
        List {
            Section {
                Toggle("Journal Reminders", isOn: $journalReminders)
                Toggle("Streak Alerts", isOn: $streakAlerts)
                Toggle("Weekly Digest", isOn: $weeklyDigest)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarItems(trailing: Button("Done") {
            dismiss()
        })
    }
}

struct DataManagementView: View {
    @State private var showingExportConfirmation = false
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        List {
            Section {
                Button {
                    showingExportConfirmation = true
                } label: {
                    Label("Export Data", systemImage: "square.and.arrow.up")
                }
                
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete All Data", systemImage: "trash")
                }
            }
        }
        .navigationTitle("Data Management")
        .alert("Export Data", isPresented: $showingExportConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Export") {
                // TODO: Implement data export
            }
        } message: {
            Text("Your data will be exported as a JSON file.")
        }
        .alert("Delete All Data", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                // TODO: Implement data deletion
            }
        } message: {
            Text("This action cannot be undone. All your journal entries and vision boards will be permanently deleted.")
        }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            Section {
                VStack(spacing: 20) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.purple)
                    
                    Text("Eunoia Journal")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Version 1.0.0")
                        .foregroundColor(.secondary)
                    
                    Text("Eunoia helps you reflect on your daily experiences, track your personal growth, and visualize your future through journaling and vision boarding.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding()
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            
            Section("Credits") {
                Text("Developed by Your Name")
                Text("Design by Your Designer")
            }
        }
        .navigationTitle("About")
        .navigationBarItems(trailing: Button("Done") {
            dismiss()
        })
    }
}

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Privacy Policy")
                    .font(.title)
                    .fontWeight(.bold)
                
                Group {
                    Text("Data Collection")
                        .font(.headline)
                    Text("We collect minimal personal information necessary to provide our services. This includes your email address and the content you create within the app.")
                    
                    Text("Data Usage")
                        .font(.headline)
                    Text("Your data is used solely to provide and improve our services. We do not sell or share your personal information with third parties.")
                    
                    Text("Data Security")
                        .font(.headline)
                    Text("We use industry-standard security measures to protect your data. All data is encrypted both in transit and at rest.")
                    
                    Text("Your Rights")
                        .font(.headline)
                    Text("You have the right to access, modify, or delete your personal data at any time through the app settings.")
                }
            }
            .padding()
        }
        .navigationTitle("Privacy Policy")
        .navigationBarItems(trailing: Button("Done") {
            dismiss()
        })
    }
}

#Preview {
    NavigationView {
        ProfileView(authViewModel: AuthViewModel())
    }
} 