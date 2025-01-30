import SwiftUI

struct MainTabView: View {
    @StateObject private var journalViewModel = JournalViewModel()
    @StateObject private var visionBoardViewModel = VisionBoardViewModel()
    @ObservedObject var authViewModel: AuthViewModel
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Dashboard as main view
            NavigationView {
                DashboardView()
            }
            .tabItem {
                Label("", systemImage: "")
            }
            .tag(0)
            
            // Journal Tab
            NavigationView {
                JournalListView(viewModel: journalViewModel)
            }
            .tabItem {
                Label(LocalizedStringKey("Journal"), systemImage: "book.fill")
            }
            .tag(1)
            
            // Vision Board Tab
            NavigationView {
                VisionBoardView(viewModel: visionBoardViewModel)
            }
            .tabItem {
                Label(LocalizedStringKey("Vision Board"), systemImage: "star.fill")
            }
            .tag(2)
            
            // Profile Tab
            NavigationView {
                ProfileView(authViewModel: authViewModel)
            }
            .tabItem {
                Label(LocalizedStringKey("Profile"), systemImage: "person.fill")
            }
            .tag(3)
        }
        .onAppear {
            // Load initial data
            journalViewModel.loadJournalEntries()
            visionBoardViewModel.loadVisionBoard()
            // Ensure Dashboard is shown first
            selectedTab = 0
            
            // Hide the empty tab item
            UITabBar.appearance().items?[0].isEnabled = false
        }
    }
}

#Preview {
    MainTabView(authViewModel: AuthViewModel())
} 