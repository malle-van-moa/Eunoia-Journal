import SwiftUI

struct MainTabView: View {
    @StateObject private var journalViewModel = JournalViewModel()
    @StateObject private var visionBoardViewModel = VisionBoardViewModel()
    @ObservedObject var authViewModel: AuthViewModel
    @State private var selectedTab = 1
    @State private var showingDashboard = true
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Journal Tab
            NavigationView {
                ZStack {
                    if showingDashboard {
                        DashboardView()
                            .toolbar {
                                ToolbarItem(placement: .principal) {
                                    Button {
                                        showingDashboard = true
                                    } label: {
                                        Text("Eunoia")
                                            .font(.title2.bold())
                                            .foregroundColor(.primary)
                                    }
                                }
                            }
                    } else {
                        JournalListView(viewModel: journalViewModel)
                            .toolbar {
                                ToolbarItem(placement: .principal) {
                                    Button {
                                        showingDashboard = true
                                    } label: {
                                        Text("Eunoia")
                                            .font(.title2.bold())
                                            .foregroundColor(.primary)
                                    }
                                }
                            }
                    }
                }
            }
            .tabItem {
                Label(LocalizedStringKey("Journal"), systemImage: "book.fill")
            }
            .tag(1)
            
            // Vision Board Tab
            NavigationView {
                VisionBoardView(viewModel: visionBoardViewModel)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Button {
                                showingDashboard = true
                            } label: {
                                Text("Eunoia")
                                    .font(.title2.bold())
                                    .foregroundColor(.primary)
                            }
                        }
                    }
            }
            .tabItem {
                Label(LocalizedStringKey("Vision Board"), systemImage: "star.fill")
            }
            .tag(2)
            
            // Profile Tab
            NavigationView {
                ProfileView(authViewModel: authViewModel)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Button {
                                showingDashboard = true
                            } label: {
                                Text("Eunoia")
                                    .font(.title2.bold())
                                    .foregroundColor(.primary)
                            }
                        }
                    }
            }
            .tabItem {
                Label(LocalizedStringKey("Profile"), systemImage: "person.fill")
            }
            .tag(3)
        }
        .onChange(of: selectedTab) { newValue in
            if newValue == 1 {
                // Wenn Journal Tab ausgewählt wird und Dashboard aktiv ist, bleibe im Dashboard
                if !showingDashboard {
                    showingDashboard = false
                }
            } else {
                // Bei anderen Tabs Dashboard ausblenden
                showingDashboard = false
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