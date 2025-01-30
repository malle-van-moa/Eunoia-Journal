import SwiftUI

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
        .navigationTitle("Journal")
        .navigationBarItems(
            leading: Button(action: {
                showingDatePicker.toggle()
            }) {
                Image(systemName: "calendar")
            },
            trailing: Button(action: {
                showingNewEntry.toggle()
            }) {
                Image(systemName: "square.and.pencil")
            }
        )
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
                // Filter entries by selected date
                let entries = viewModel.entriesByDate(date: date)
                if let firstEntry = entries.first {
                    selectedEntry = firstEntry
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct StreakBannerView: View {
    let streak: Int
    
    var body: some View {
        HStack {
            Image(systemName: "flame.fill")
                .foregroundColor(.orange)
            Text("\(streak) Day Streak")
                .font(.headline)
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }
}

struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            
            TextField("Search entries...", text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

struct JournalEntryRow: View {
    let entry: JournalEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.date, style: .date)
                    .font(.headline)
                Spacer()
                if entry.learningNugget != nil {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                }
            }
            
            if !entry.gratitude.isEmpty {
                Text("Grateful for: \(entry.gratitude)")
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            if !entry.highlight.isEmpty {
                Text("Highlight: \(entry.highlight)")
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 8)
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "book.closed")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Journal Entries")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Start writing your first entry by tapping the pencil icon above.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
        }
        .padding()
    }
}

struct DatePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedDate: Date
    let onDateSelected: (Date) -> Void
    
    var body: some View {
        NavigationView {
            DatePicker(
                "Select Date",
                selection: $selectedDate,
                displayedComponents: .date
            )
            .datePickerStyle(GraphicalDatePickerStyle())
            .padding()
            .navigationTitle("Select Date")
            .navigationBarItems(
                trailing: Button("Done") {
                    onDateSelected(selectedDate)
                    dismiss()
                }
            )
        }
    }
}

#Preview {
    NavigationView {
        JournalListView(viewModel: JournalViewModel())
    }
} 