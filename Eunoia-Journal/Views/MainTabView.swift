import SwiftUI

struct MainTabView: View {
    @StateObject private var journalViewModel = JournalViewModel()
    @StateObject private var visionBoardViewModel = VisionBoardViewModel()
    @ObservedObject var authViewModel: AuthViewModel
    @State private var selectedTab = 1
    @State private var showingDashboard = true
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Journal Tab with Dashboard
            NavigationView {
                Group {
                    if showingDashboard {
                        DashboardView(selectedTab: $selectedTab, showingDashboard: $showingDashboard)
                    } else {
                        JournalListView(viewModel: journalViewModel)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Button {
                            withAnimation {
                                showingDashboard = true
                            }
                        } label: {
                            Text("Eunoia")
                                .font(.title2.bold())
                                .foregroundColor(.primary)
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
                                withAnimation {
                                    selectedTab = 1
                                    showingDashboard = true
                                }
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
            }
            .tabItem {
                Label(LocalizedStringKey("Profile"), systemImage: "person.fill")
            }
            .tag(3)
        }
        .onChange(of: selectedTab) { _, newValue in
            // Wenn wir zum Journal-Tab wechseln und das Dashboard nicht angezeigt wird,
            // zeigen wir die JournalListView
            if newValue == 1 && !showingDashboard {
                showingDashboard = false
            }
            // Wenn wir zu einem anderen Tab wechseln, merken wir uns den Dashboard-Status
            else if newValue != 1 {
                // Dashboard-Status bleibt erhalten
            }
        }
        .onAppear {
            journalViewModel.loadJournalEntries()
            visionBoardViewModel.loadVisionBoard()
        }
    }
}

#Preview {
    MainTabView(authViewModel: AuthViewModel())
} 