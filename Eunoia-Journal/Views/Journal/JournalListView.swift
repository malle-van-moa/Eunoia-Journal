import SwiftUI
import JournalingSuggestions

struct JournalListView: View {
    @ObservedObject var viewModel: JournalViewModel
    @State private var searchText = ""
    @State private var showingNewEntry = false
    @State private var selectedEntry: JournalEntry?
    @State private var showingDatePicker = false
    @State private var selectedDate = Date()
    @State private var showingSuggestionsPicker = false
    
    private var filteredEntries: [JournalEntry] {
        if searchText.isEmpty {
            return viewModel.journalEntries
        } else {
            return viewModel.searchEntries(query: searchText)
        }
    }
    
    var body: some View {
        NavigationView {
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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        if #available(iOS 17.2, *) {
                            Button {
                                showingSuggestionsPicker = true
                            } label: {
                                Image(systemName: "lightbulb.fill")
                            }
                        }
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
            .sheet(isPresented: $showingSuggestionsPicker) {
                if #available(iOS 17.2, *) {
                    JournalingSuggestionsPicker("") { suggestion in
                        Task {
                            await viewModel.createEntryFromSuggestion(suggestion)
                            showingSuggestionsPicker = false
                        }
                    }
                    .presentationDetents([.medium])
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
            Text(LocalizedStringKey("\(streak) Tage in Folge"))
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
            
            TextField(LocalizedStringKey("Einträge durchsuchen..."), text: $text)
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
                Text(LocalizedStringKey("Dankbar für: \(entry.gratitude)"))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            if !entry.highlight.isEmpty {
                Text(LocalizedStringKey("Highlight: \(entry.highlight)"))
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
            
            Text(LocalizedStringKey("Keine Journal Einträge"))
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(LocalizedStringKey("Tippe auf das Stift-Symbol oben, um deinen ersten Eintrag zu erstellen."))
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
                LocalizedStringKey("Datum auswählen"),
                selection: $selectedDate,
                displayedComponents: .date
            )
            .datePickerStyle(GraphicalDatePickerStyle())
            .padding()
            .navigationTitle(LocalizedStringKey("Datum auswählen"))
            .navigationBarItems(
                trailing: Button(LocalizedStringKey("Fertig")) {
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