import SwiftUI
import JournalingSuggestions

@available(iOS 17.0, *)
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
                    Button(action: {
                        showingSuggestionsPicker = true
                    }) {
                        Image(systemName: "lightbulb")
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
                NavigationView {
                    JournalingSuggestionsPicker(label: {
                        Text("Vorschläge")
                    }, onCompletion: { suggestion in
                        Task {
                            do {
                                try await viewModel.createEntryFromSuggestion(suggestion)
                                await MainActor.run {
                                    showingSuggestionsPicker = false
                                }
                            } catch {
                                print("Fehler beim Erstellen des Eintrags: \(error)")
                                // Zeige dem Benutzer einen Fehler an
                                await MainActor.run {
                                    // TODO: Implementiere eine Fehleranzeige
                                    showingSuggestionsPicker = false
                                }
                            }
                        }
                    })
                    .navigationTitle("Vorschläge")
                    .navigationBarItems(trailing: Button("Fertig") {
                        showingSuggestionsPicker = false
                    })
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
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.string(from: entry.date)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.title ?? formattedDate)
                .font(.headline)
            
            if let content = entry.content {
                Text(content)
                    .font(.subheadline)
                    .lineLimit(2)
            }
            
            if let location = entry.location {
                HStack {
                    Image(systemName: "location")
                    Text(location)
                        .font(.caption)
                }
            }
            
            if let imageURLs = entry.imageURLs, !imageURLs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(imageURLs, id: \.self) { url in
                            AsyncImage(url: URL(string: url)) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                case .failure:
                                    Image(systemName: "photo")
                                        .foregroundColor(.gray)
                                @unknown default:
                                    EmptyView()
                                }
                            }
                            .frame(width: 60, height: 60)
                        }
                    }
                }
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

@available(iOS 17.0, *)
extension JournalViewModel {
    static func previewMock() -> JournalViewModel {
        let viewModel = JournalViewModel()
        // Füge einige Mock-Einträge hinzu
        let mockEntry = JournalEntry(
            id: UUID().uuidString,
            userId: "preview-user",
            date: Date(),
            gratitude: "Dankbar für einen neuen Tag",
            highlight: "Erfolgreicher Projektabschluss",
            learning: "Neue SwiftUI Techniken gelernt",
            learningNugget: nil,
            lastModified: Date(),
            syncStatus: .synced,
            serverTimestamp: nil,
            title: "Mein erster Eintrag",
            content: "Dies ist ein Beispieleintrag für die Preview",
            location: "Berlin, Deutschland",
            imageURLs: nil
        )
        viewModel.journalEntries = [mockEntry]
        return viewModel
    }
}

@available(iOS 17.0, *)
struct JournalListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            JournalListView(viewModel: JournalViewModel.previewMock())
        }
    }
} 