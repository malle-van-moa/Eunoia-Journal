#if canImport(JournalingSuggestions)
import JournalingSuggestions
#endif
import SwiftUI

@available(iOS 17.0, *)
struct JournalListView: View {
    @ObservedObject var viewModel: JournalViewModel
    @State private var searchText = ""
    @State private var showingNewEntry = false
    @State private var selectedEntry: JournalEntry?
    @State private var showingDatePicker = false
    @State private var selectedDate = Date()
    @State private var showingSuggestionsPicker = false
    @State private var selectedImages: [UIImage] = []
    
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
                    #if canImport(JournalingSuggestions)
                    if #available(iOS 17.2, *) {
                        Button(action: {
                            showingSuggestionsPicker = true
                        }) {
                            Image(systemName: "lightbulb")
                        }
                    }
                    #endif
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
            #if canImport(JournalingSuggestions)
            .sheet(isPresented: $showingSuggestionsPicker) {
                if #available(iOS 17.2, *) {
                    NavigationView {
                        VStack {
                            JournalingSuggestionsPicker(label: {
                                Text("Vorschläge")
                            }, onCompletion: { suggestion in
                                Task {
                                    do {
                                        let entry = try await viewModel.createEntryFromSuggestion(suggestion)
                                        if !selectedImages.isEmpty {
                                            _ = try await viewModel.saveEntryWithImages(entry, images: selectedImages)
                                        }
                                        await MainActor.run {
                                            selectedImages = []
                                            showingSuggestionsPicker = false
                                        }
                                    } catch {
                                        print("Fehler beim Erstellen des Eintrags: \(error)")
                                        await MainActor.run {
                                            selectedImages = []
                                            showingSuggestionsPicker = false
                                        }
                                    }
                                }
                            })
                            
                            if selectedImages.count < 5 {
                                ImagePickerButton(
                                    selectedImages: $selectedImages,
                                    maxImages: 5
                                )
                                .padding()
                            }
                            
                            if !selectedImages.isEmpty {
                                ImageGalleryView(images: selectedImages) { index in
                                    selectedImages.remove(at: index)
                                }
                                .frame(height: 120)
                                .padding(.horizontal)
                            }
                        }
                        .navigationTitle("Vorschläge")
                        .navigationBarItems(trailing: Button("Fertig") {
                            showingSuggestionsPicker = false
                        })
                    }
                }
            }
            #endif
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
            
            // Bilder-Anzeige mit Fallback-Logik
            Group {
                if let imageURLs = entry.imageURLs, !imageURLs.isEmpty {
                    // Cloud-Bilder
                    ImageScrollView(urls: imageURLs)
                } else if let localPaths = entry.localImagePaths, !localPaths.isEmpty {
                    // Lokale Bilder
                    LocalImageScrollView(paths: localPaths)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

struct ImageScrollView: View {
    let urls: [String]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(urls, id: \.self) { url in
                    AsyncImage(url: URL(string: url)) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(width: 60, height: 60)
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        case .failure:
                            VStack {
                                Image(systemName: "photo")
                                    .foregroundColor(.gray)
                                Text("Fehler")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .frame(width: 60, height: 60)
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

struct LocalImageScrollView: View {
    let paths: [String]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(paths, id: \.self) { path in
                    Group {
                        if let image = loadImage(from: path) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            VStack {
                                Image(systemName: "photo")
                                    .foregroundColor(.gray)
                                Text("Nicht verfügbar")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .frame(width: 60, height: 60)
                        }
                    }
                    .frame(width: 60, height: 60)
                }
            }
        }
    }
    
    private func loadImage(from path: String) -> UIImage? {
        guard let imageData = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let image = UIImage(data: imageData) else {
            return nil
        }
        return image
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