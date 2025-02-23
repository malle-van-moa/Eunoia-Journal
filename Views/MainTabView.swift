struct MainTabView: View {
    @StateObject private var journalViewModel = JournalViewModel()
    @StateObject private var visionBoardViewModel = VisionBoardViewModel()
    @ObservedObject var authViewModel: AuthViewModel
    @State private var selectedTab = 1
    @State private var showingDashboard = true
    @State private var showingNewEntry = false
    
    private var toolbarBackground: some View {
        Color(.systemBackground)
            .ignoresSafeArea(edges: .top)
            .frame(height: 50)
    }
    
    private var toolbarTitle: some View {
        Text("Eunoia")
            .font(.title2)
            .fontWeight(.bold)
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.systemBackground))
                    .shadow(radius: 2)
            )
            .padding(.horizontal)
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Journal/Dashboard Tab
            NavigationStack {
                ZStack(alignment: .top) {
                    Color(.systemGroupedBackground)
                        .ignoresSafeArea()
                    
                    Group {
                        if showingDashboard {
                            DashboardView(selectedTab: $selectedTab, showingDashboard: $showingDashboard)
                        } else {
                            JournalListView(viewModel: journalViewModel)
                        }
                    }
                }
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
                    if !showingDashboard {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(action: {
                                // Calendar action
                            }) {
                                Image(systemName: "calendar")
                            }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: {
                                showingNewEntry = true
                            }) {
                                Image(systemName: "square.and.pencil")
                            }
                        }
                    }
                }
                .toolbarBackground(toolbarBackground, for: .navigationBar)
            }
            .tabItem {
                Image(systemName: "book.fill")
                Text("Journal")
            }
            .tag(1)
            
            // Vision Board Tab
            NavigationStack {
                ZStack(alignment: .top) {
                    Color(.systemGroupedBackground)
                        .ignoresSafeArea()
                    
                    Group {
                        if showingDashboard {
                            DashboardView(selectedTab: $selectedTab, showingDashboard: $showingDashboard)
                        } else {
                            VisionBoardView(viewModel: visionBoardViewModel)
                        }
                    }
                }
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
                .toolbarBackground(toolbarBackground, for: .navigationBar)
            }
            .tabItem {
                Image(systemName: "star.fill")
                Text("Vision Board")
            }
            .tag(2)
            
            // Profile Tab
            NavigationStack {
                ZStack(alignment: .top) {
                    Color(.systemGroupedBackground)
                        .ignoresSafeArea()
                    
                    ProfileView(authViewModel: authViewModel)
                }
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
                .toolbarBackground(toolbarBackground, for: .navigationBar)
            }
            .tabItem {
                Image(systemName: "person.fill")
                Text("Profile")
            }
            .tag(3)
        }
        .sheet(isPresented: $showingNewEntry) {
            NavigationView {
                JournalEntryView(viewModel: journalViewModel)
            }
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