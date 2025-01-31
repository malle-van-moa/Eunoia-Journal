struct JournalListView: View {
    @ObservedObject var viewModel: JournalViewModel
    @State private var searchText = ""
    @State private var showingNewEntry = false
    @State private var selectedEntry: JournalEntry?
    @State private var showingDatePicker = false
    @State private var selectedDate = Date()
    
    private var filteredEntries: [JournalEntry] {
        if searchText.isEmpty {
            return viewModel.journalEntries
        } else {
            return viewModel.searchEntries(query: searchText)
        }
    }
    
    var body: some View {
        ZStack {
            // Background
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Streak Banner
                StreakBannerView(streak: viewModel.calculateCurrentStreak())
                
                // Search and Filter
                SearchBar(text: $searchText)
                    .padding()
                
                // Journal Entries List
                if filteredEntries.isEmpty {
                    EmptyStateView()
                } else {
                    List {
                        ForEach(filteredEntries) { entry in
                            JournalEntryRow(entry: entry)
                                .onTapGesture {
                                    selectedEntry = entry
                                }
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                }
            }
        }
        .sheet(isPresented: $showingNewEntry) {
            NavigationView {
                JournalEntryView(viewModel: viewModel)
            }
        }
        .sheet(item: $selectedEntry) { entry in
            NavigationView {
                JournalEntryView(viewModel: viewModel, entry: entry)
            }
        }
        .sheet(isPresented: $showingDatePicker) {
            DatePickerView(selectedDate: $selectedDate) { date in
                let entries = viewModel.entriesByDate(date: date)
                if let firstEntry = entries.first {
                    selectedEntry = firstEntry
                }
            }
        }
    }
} 