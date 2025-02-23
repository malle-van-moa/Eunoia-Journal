import SwiftUI

struct MainTabView: View {
    @StateObject private var journalViewModel = JournalViewModel()
    @StateObject private var visionBoardViewModel = VisionBoardViewModel()
    @ObservedObject var authViewModel: AuthViewModel
    @State private var selectedTab = 1
    @State private var showingDashboard = true
    
    private var toolbarTitle: some View {
        HStack(spacing: 8) {
            Image(systemName: "house.fill")
                .imageScale(.large)
                .foregroundStyle(.purple)
            Text("Eunoia")
                .font(.headline)
                .fontWeight(.bold)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Journal/Dashboard Tab
            NavigationStack {
                Group {
                    if showingDashboard {
                        DashboardView(selectedTab: $selectedTab, showingDashboard: $showingDashboard)
                    } else {
                        JournalListView(viewModel: journalViewModel)
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .principal) {
                                    Button {
                                        withAnimation {
                                            showingDashboard = true
                                        }
                                    } label: {
                                        toolbarTitle
                                    }
                                }
                            }
                    }
                }
            }
            .tabItem {
                Image(systemName: "book.fill")
                Text("Journal")
            }
            .tag(1)
            
            // Vision Board Tab
            NavigationStack {
                Group {
                    if showingDashboard {
                        DashboardView(selectedTab: $selectedTab, showingDashboard: $showingDashboard)
                    } else {
                        VisionBoardView(viewModel: visionBoardViewModel)
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .principal) {
                                    Button {
                                        withAnimation {
                                            showingDashboard = true
                                        }
                                    } label: {
                                        toolbarTitle
                                    }
                                }
                            }
                    }
                }
            }
            .tabItem {
                Image(systemName: "star.fill")
                Text("Vision Board")
            }
            .tag(2)
            
            // Profile Tab
            NavigationStack {
                ProfileView(authViewModel: authViewModel)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Button {
                                withAnimation {
                                    selectedTab = 1
                                    showingDashboard = true
                                }
                            } label: {
                                toolbarTitle
                            }
                        }
                    }
            }
            .tabItem {
                Image(systemName: "person.fill")
                Text("Profile")
            }
            .tag(3)
        }
        .onChange(of: selectedTab) { newTab in
            if showingDashboard {
                showingDashboard = false
            }
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