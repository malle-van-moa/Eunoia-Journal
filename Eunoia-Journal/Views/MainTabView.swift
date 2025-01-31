import SwiftUI

struct MainTabView: View {
    @StateObject private var journalViewModel = JournalViewModel()
    @StateObject private var visionBoardViewModel = VisionBoardViewModel()
    @ObservedObject var authViewModel: AuthViewModel
    @State private var selectedTab = 1
    @State private var showingDashboard = true
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Journal/Dashboard Tab
            NavigationStack {
                if showingDashboard {
                    DashboardView(selectedTab: $selectedTab, showingDashboard: $showingDashboard)
                } else {
                    JournalListView(viewModel: journalViewModel)
                }
            }
            .tabItem {
                Image(systemName: "book.fill")
                Text("Journal")
            }
            .tag(1)
            
            // Vision Board Tab
            NavigationStack {
                VisionBoardView(viewModel: visionBoardViewModel)
            }
            .tabItem {
                Image(systemName: "star.fill")
                Text("Vision Board")
            }
            .tag(2)
            
            // Profile Tab
            NavigationStack {
                ProfileView(authViewModel: authViewModel)
            }
            .tabItem {
                Image(systemName: "person.fill")
                Text("Profile")
            }
            .tag(3)
        }
        .onAppear {
            journalViewModel.loadJournalEntries()
            visionBoardViewModel.loadVisionBoard()
            
            // TabBar Style konfigurieren
            if #available(iOS 15.0, *) {
                let appearance = UITabBarAppearance()
                appearance.configureWithOpaqueBackground()
                UITabBar.appearance().scrollEdgeAppearance = appearance
                UITabBar.appearance().standardAppearance = appearance
            }
        }
    }
}

#Preview {
    MainTabView(authViewModel: AuthViewModel())
} 