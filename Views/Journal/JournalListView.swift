struct JournalHeaderView: View {
    var onCalendarTap: () -> Void
    var onSuggestionTap: () -> Void
    var onNewEntryTap: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Text("Journal")
                .font(.largeTitle)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.bottom, 8)
            
            HStack {
                Button(action: onCalendarTap) {
                    Image(systemName: "calendar")
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                }
                
                Spacer()
                
                Button(action: onSuggestionTap) {
                    Image(systemName: "lightbulb")
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                }
                
                Button(action: onNewEntryTap) {
                    Image(systemName: "square.and.pencil")
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .background(
            Color(.systemBackground)
                .ignoresSafeArea(edges: .horizontal)
        )
    }
}

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
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                JournalHeaderView(
                    onCalendarTap: { showingDatePicker.toggle() },
                    onSuggestionTap: { /* Suggestion Action */ },
                    onNewEntryTap: { showingNewEntry.toggle() }
                )
                
                // Streak Banner
                StreakBannerView(streak: viewModel.calculateCurrentStreak())
                    .frame(maxWidth: .infinity)
                    .background(
                        Color(.systemBackground)
                            .ignoresSafeArea(edges: .horizontal)
                    )
                
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
            JournalEntryView(viewModel: viewModel)
        }
        .sheet(item: $selectedEntry) { entry in
            JournalEntryView(viewModel: viewModel, entry: entry)
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