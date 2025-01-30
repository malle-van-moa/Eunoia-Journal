import SwiftUI

struct MainTabView: View {
    @StateObject private var journalViewModel = JournalViewModel()
    @StateObject private var visionBoardViewModel = VisionBoardViewModel()
    @ObservedObject var authViewModel: AuthViewModel
    
    var body: some View {
        TabView {
            // Journal Tab
            NavigationView {
                JournalListView(viewModel: journalViewModel)
            }
            .tabItem {
                Label("Journal", systemImage: "book.fill")
            }
            
            // Vision Board Tab
            NavigationView {
                VisionBoardView(viewModel: visionBoardViewModel)
            }
            .tabItem {
                Label("Vision Board", systemImage: "star.fill")
            }
            
            // Profile Tab
            NavigationView {
                ProfileView(authViewModel: authViewModel)
            }
            .tabItem {
                Label("Profile", systemImage: "person.fill")
            }
        }
        .onAppear {
            // Load initial data
            journalViewModel.loadJournalEntries()
            visionBoardViewModel.loadVisionBoard()
        }
    }
}

#Preview {
    MainTabView(authViewModel: AuthViewModel())
} 