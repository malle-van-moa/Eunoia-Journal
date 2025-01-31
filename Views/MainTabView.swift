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
                                        Text("Eunoia")
                                            .font(.title2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.primary)
                                    }
                                }
                                ToolbarItem(placement: .navigationBarLeading) {
                                    Button(action: {
                                        // Calendar action
                                    }) {
                                        Image(systemName: "calendar")
                                    }
                                }
                                ToolbarItem(placement: .navigationBarTrailing) {
                                    Button(action: {
                                        // New entry action
                                    }) {
                                        Image(systemName: "square.and.pencil")
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
                                        Text("Eunoia")
                                            .font(.title2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.primary)
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
                                Text("Eunoia")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
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
        .onAppear {
            // Load data
            journalViewModel.loadJournalEntries()
            visionBoardViewModel.loadVisionBoard()
            
            // Configure TabBar appearance
            if #available(iOS 15.0, *) {
                let appearance = UITabBarAppearance()
                appearance.configureWithOpaqueBackground()
                UITabBar.appearance().scrollEdgeAppearance = appearance
                UITabBar.appearance().standardAppearance = appearance
            }
        }
    }
} 