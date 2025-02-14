import SwiftUI
import FirebaseAuth

struct JournalEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: JournalViewModel
    
    @State private var gratitude: String
    @State private var highlight: String
    @State private var learning: String
    @State private var showingAISuggestions = false
    @State private var showingLearningNugget = false
    @State private var selectedField: JournalField?
    @State private var showingDeleteConfirmation = false
    @State private var selectedImages: [UIImage] = []
    @State private var showingImageViewer = false
    @State private var selectedImageIndex: Int?
    
    private let entry: JournalEntry?
    private let isEditing: Bool
    private let maxImages = 5
    
    enum JournalField: String {
        case gratitude = "Dankbarkeit"
        case highlight = "Highlight"
        case learning = "Lernen"
    }
    
    init(viewModel: JournalViewModel, entry: JournalEntry? = nil) {
        self.viewModel = viewModel
        self.entry = entry
        self.isEditing = entry != nil
        
        _gratitude = State(initialValue: entry?.gratitude ?? "")
        _highlight = State(initialValue: entry?.highlight ?? "")
        _learning = State(initialValue: entry?.learning ?? "")
    }
    
    private func loadImages() -> [UIImage]? {
        guard let localPaths = entry?.localImagePaths else { return nil }
        let images = localPaths.compactMap { path -> UIImage? in
            guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
            let fileURL = documentsDirectory.appendingPathComponent(path)
            return UIImage(contentsOfFile: fileURL.path)
        }
        return images.isEmpty ? nil : images
    }
    
    var body: some View {
        Form {
            if let title = entry?.title {
                Section(header: Text("Titel")) {
                    Text(title)
                }
            }
            
            if let content = entry?.content {
                Section(header: Text("Inhalt")) {
                    Text(content)
                }
            }
            
            if let location = entry?.location {
                Section(header: Text("Ort")) {
                    Text(location)
                }
            }
            
            Section(header: Text("Dankbarkeit")) {
                TextEditor(text: Binding(
                    get: { entry?.gratitude ?? "" },
                    set: { newValue in
                        if var updatedEntry = entry {
                            updatedEntry.gratitude = newValue
                            viewModel.saveEntry(updatedEntry)
                        }
                    }
                ))
                .frame(height: 100)
            }
            
            // Gratitude Section
            JournalSection(
                title: LocalizedStringKey("Wofür bist du heute dankbar?"),
                text: $gratitude,
                systemImage: "heart.fill",
                color: .red
            ) {
                selectedField = .gratitude
                showingAISuggestions = true
            }
            
            // Highlight Section
            JournalSection(
                title: LocalizedStringKey("Was war dein Highlight heute?"),
                text: $highlight,
                systemImage: "star.fill",
                color: .yellow
            ) {
                selectedField = .highlight
                showingAISuggestions = true
            }
            
            // Learning Section
            JournalSection(
                title: LocalizedStringKey("Was hast du heute gelernt?"),
                text: $learning,
                systemImage: "book.fill",
                color: .blue
            ) {
                selectedField = .learning
                showingAISuggestions = true
            }
            
            // Learning Nugget
            if let nugget = entry?.learningNugget {
                LearningNuggetView(nugget: nugget)
            } else {
                Button(action: {
                    showingLearningNugget = true
                }) {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                        Text(LocalizedStringKey("Tägliche Lernerkenntnis erhalten"))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                }
            }
            
            // Bilder Section
            Section(header: Text("Bilder")) {
                VStack(alignment: .leading, spacing: 10) {
                    if !selectedImages.isEmpty {
                        ImageGalleryView(images: selectedImages) { index in
                            selectedImages.remove(at: index)
                        }
                        .frame(height: 120)
                    } else if let entry = entry, let urls = entry.imageURLs, !urls.isEmpty {
                        // Zeige Cloud-Bilder
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 10) {
                                ForEach(urls, id: \.self) { url in
                                    AsyncImage(url: URL(string: url)) { phase in
                                        switch phase {
                                        case .empty:
                                            ProgressView()
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 100, height: 100)
                                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                        case .failure:
                                            Image(systemName: "photo")
                                                .foregroundColor(.gray)
                                        @unknown default:
                                            EmptyView()
                                        }
                                    }
                                    .frame(width: 100, height: 100)
                                }
                            }
                            .padding(.horizontal)
                        }
                        .frame(height: 120)
                    }
                    
                    if selectedImages.count < maxImages {
                        ImagePickerButton(
                            selectedImages: $selectedImages,
                            maxImages: maxImages
                        )
                    }
                }
            }
        }
        .navigationTitle(entry?.title ?? "Neuer Eintrag")
        .navigationBarItems(
            leading: Button(LocalizedStringKey("Abbrechen")) {
                dismiss()
            },
            trailing: HStack {
                if isEditing {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
                
                Button("Fertig") {
                    saveEntry()
                }
                .disabled(gratitude.isEmpty && highlight.isEmpty && learning.isEmpty)
            }
        )
        .sheet(isPresented: $showingAISuggestions) {
            AISuggestionsView(
                field: selectedField ?? .gratitude,
                suggestions: viewModel.aiSuggestions
            ) { suggestion in
                switch selectedField {
                case .gratitude:
                    gratitude = suggestion
                case .highlight:
                    highlight = suggestion
                case .learning:
                    learning = suggestion
                case .none:
                    break
                }
            }
        }
        .sheet(isPresented: $showingLearningNugget) {
            LearningNuggetPickerView(viewModel: viewModel)
        }
        .alert(LocalizedStringKey("Eintrag löschen"), isPresented: $showingDeleteConfirmation) {
            Button(LocalizedStringKey("Löschen"), role: .destructive) {
                if let entry = entry {
                    viewModel.deleteEntry(entry)
                    dismiss()
                }
            }
            Button(LocalizedStringKey("Abbrechen"), role: .cancel) {}
        } message: {
            Text(LocalizedStringKey("Bist du sicher, dass du diesen Eintrag löschen möchtest? Diese Aktion kann nicht rückgängig gemacht werden."))
        }
        .alert("Fehler", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .onAppear {
            selectedImages = loadImages() ?? []
        }
    }
    
    private func saveEntry() {
        guard let userId = Auth.auth().currentUser?.uid else {
            viewModel.error = NSError(
                domain: "JournalEntryView",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Bitte melde dich an, um Einträge zu speichern."]
            )
            return
        }
        
        let updatedEntry = JournalEntry(
            id: entry?.id ?? UUID().uuidString,
            userId: userId,
            date: entry?.date ?? Date(),
            gratitude: gratitude,
            highlight: highlight,
            learning: learning,
            learningNugget: entry?.learningNugget,
            lastModified: Date(),
            syncStatus: .pendingUpload,
            title: entry?.title,
            content: entry?.content,
            location: entry?.location,
            imageURLs: nil,  // Setze URLs auf nil, da sie neu generiert werden
            localImagePaths: nil  // Setze Pfade auf nil, da sie neu generiert werden
        )
        
        Task {
            do {
                if !selectedImages.isEmpty {
                    let savedEntry = try await viewModel.saveEntryWithImages(updatedEntry, images: selectedImages)
                    print("Eintrag gespeichert mit URLs: \(String(describing: savedEntry.imageURLs))")
                    print("Lokale Pfade: \(String(describing: savedEntry.localImagePaths))")
                    
                    await MainActor.run {
                        dismiss()
                    }
                } else {
                    // Wenn keine neuen Bilder ausgewählt wurden, aber der Eintrag bereits Bilder hat
                    if let existingImages = loadImages(), !existingImages.isEmpty {
                        let savedEntry = try await viewModel.saveEntryWithImages(updatedEntry, images: existingImages)
                        print("Eintrag mit bestehenden Bildern gespeichert")
                        
                        await MainActor.run {
                            dismiss()
                        }
                    } else {
                        viewModel.saveEntry(updatedEntry)
                        await MainActor.run {
                            dismiss()
                        }
                    }
                }
            } catch {
                print("Fehler beim Speichern des Eintrags: \(error)")
                await MainActor.run {
                    viewModel.error = error
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct JournalSection: View {
    let title: LocalizedStringKey
    @Binding var text: String
    let systemImage: String
    let color: Color
    let onSuggestionTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
                Spacer()
                Button(action: onSuggestionTap) {
                    Image(systemName: "wand.and.stars")
                        .foregroundColor(.purple)
                }
            }
            
            TextEditor(text: $text)
                .frame(height: 100)
                .padding(8)
                .background(Color(.systemBackground))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2))
                )
        }
    }
}

struct LearningNuggetView: View {
    let nugget: LearningNugget
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text("Daily Learning Nugget")
                    .font(.headline)
                Spacer()
                Text(nugget.category.rawValue.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(8)
            }
            
            Text(nugget.content)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
        }
    }
}

struct AISuggestionsView: View {
    @Environment(\.dismiss) private var dismiss
    let field: JournalEntryView.JournalField
    let suggestions: [String]
    let onSelect: (String) -> Void
    
    var body: some View {
        NavigationView {
            List {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(action: {
                        onSelect(suggestion)
                        dismiss()
                    }) {
                        Text(suggestion)
                            .foregroundColor(.primary)
                    }
                }
            }
            .navigationTitle("Suggestions for \(field.rawValue)")
            .navigationBarItems(trailing: Button("Cancel") {
                dismiss()
            })
        }
    }
}

struct LearningNuggetPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: JournalViewModel
    
    var body: some View {
        NavigationView {
            List(LearningNugget.Category.allCases, id: \.self) { category in
                Button(action: {
                    viewModel.generateLearningNugget(for: category)
                    viewModel.addLearningNuggetToEntry()
                    dismiss()
                }) {
                    HStack {
                        Text(category.rawValue.capitalized)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle("Choose Category")
            .navigationBarItems(trailing: Button("Cancel") {
                dismiss()
            })
        }
    }
}

#Preview {
    NavigationView {
        JournalEntryView(viewModel: JournalViewModel())
    }
} 