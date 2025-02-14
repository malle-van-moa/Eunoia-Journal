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
    @State private var identifiableError: IdentifiableError?
    @State private var showingProcessingIndicator = false
    
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
    
    private func setupInitialState() {
        if let entry = entry {
            Task { @MainActor in
                viewModel.currentEntry = entry
            }
        } else {
            Task { @MainActor in
                viewModel.createNewEntry()
            }
        }
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
    
    private var gratitudeBinding: Binding<String> {
        Binding(
            get: { entry?.gratitude ?? "" },
            set: { newValue in
                if var updatedEntry = entry {
                    updatedEntry.gratitude = newValue
                    viewModel.saveEntry(updatedEntry)
                }
            }
        )
    }
    
    // Neue Funktion zur Aktualisierung der Learning-Sektion
    private func updateLearningContent() {
        if let currentEntry = viewModel.currentEntry {
            learning = currentEntry.learning
            
            // Aktualisiere auch den Entry, falls vorhanden
            if var updatedEntry = entry {
                updatedEntry.learning = currentEntry.learning
                updatedEntry.learningNugget = currentEntry.learningNugget
                viewModel.saveEntry(updatedEntry)
            }
        }
    }
    
    private var errorBinding: Binding<Bool> {
        Binding(
            get: { identifiableError != nil },
            set: { if !$0 { identifiableError = nil } }
        )
    }
    
    private func handleError(_ error: Error) {
        DispatchQueue.main.async {
            let journalError: JournalError
            if let nsError = error as? NSError {
                switch nsError.code {
                case 401:
                    journalError = .authError
                case -1009:
                    journalError = .networkError("Keine Internetverbindung")
                default:
                    journalError = .saveError(nsError.localizedDescription)
                }
            } else {
                journalError = .saveError(error.localizedDescription)
            }
            self.identifiableError = IdentifiableError(journalError: journalError)
        }
    }
    
    var body: some View {
        Form {
            headerSection
            journalSections
            learningNuggetSection
            imagesSection
        }
        .navigationTitle(entry?.title ?? "Neuer Eintrag")
        .navigationBarItems(
            leading: cancelButton,
            trailing: HStack {
                deleteButton
                saveButton
            }
        )
        .sheet(isPresented: $showingAISuggestions) {
            AISuggestionsView(
                field: selectedField ?? .gratitude,
                suggestions: viewModel.aiSuggestions,
                onSelect: handleSuggestionSelection
            )
        }
        .sheet(isPresented: $showingLearningNugget) {
            LearningNuggetPickerView(viewModel: viewModel)
        }
        .alert("Eintrag löschen", isPresented: $showingDeleteConfirmation) {
            deleteConfirmationButtons
        } message: {
            Text("Bist du sicher, dass du diesen Eintrag löschen möchtest? Diese Aktion kann nicht rückgängig gemacht werden.")
        }
        .alert("Fehler", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                clearError()
            }
        } message: {
            errorContent
        }
        .task {
            setupInitialState()
        }
        .onChange(of: viewModel.currentLearningText) { newContent in
            // Entferne die automatische Übernahme
            // learning = newContent
        }
        .onChange(of: viewModel.learningNugget) { newNugget in
            // Entferne die automatische Übernahme
            // if let nugget = newNugget {
            //     learning = nugget.content
            // }
        }
        .onReceive(viewModel.$error) { error in
            if let error = error {
                handleError(error)
            }
        }
    }
    
    private var cancelButton: some View {
        Button("Abbrechen") {
            dismiss()
        }
    }
    
    private var deleteButton: some View {
        Group {
            if isEditing {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
    }
    
    private var saveButton: some View {
        Button("Fertig") {
            saveEntry()
        }
        .disabled(gratitude.isEmpty && highlight.isEmpty && learning.isEmpty)
    }
    
    private var deleteConfirmationButtons: some View {
        Group {
            Button("Löschen", role: .destructive) {
                if let entry = entry {
                    viewModel.deleteEntry(entry)
                    dismiss()
                }
            }
            Button("Abbrechen", role: .cancel) { }
        }
    }
    
    private var learningNuggetSection: some View {
        Group {
            if let nugget = viewModel.learningNugget ?? entry?.learningNugget {
                LearningNuggetView(nugget: nugget)
            } else {
                learningNuggetButton
            }
        }
    }
    
    private var learningNuggetButton: some View {
        Button(action: { showingLearningNugget = true }) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text("Tägliche Lernerkenntnis erhalten")
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(10)
        }
    }
    
    private func handleSuggestionSelection(_ suggestion: String) {
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
    
    private func clearError() {
        identifiableError = nil
        viewModel.error = nil
    }
    
    private var headerSection: some View {
        Group {
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
        }
    }
    
    private var journalSections: some View {
        Group {
            // Gratitude Section
            JournalSection(
                title: "Wofür bist du heute dankbar?",
                text: $gratitude,
                systemImage: "heart.fill",
                color: .red
            ) {
                selectedField = .gratitude
                showingAISuggestions = true
            }
            
            // Highlight Section
            JournalSection(
                title: "Was war dein Highlight heute?",
                text: $highlight,
                systemImage: "star.fill",
                color: .yellow
            ) {
                selectedField = .highlight
                showingAISuggestions = true
            }
            
            // Learning Section
            JournalSection(
                title: "Was hast du heute gelernt?",
                text: $learning,
                systemImage: "book.fill",
                color: .blue
            ) {
                selectedField = .learning
                showingAISuggestions = true
            }
        }
    }
    
    private var imagesSection: some View {
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
    
    private var errorContent: some View {
        if let error = identifiableError {
            Text(error.journalError.errorDescription ?? "Unbekannter Fehler")
        } else {
            Text("")
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
            learningNugget: viewModel.learningNugget ?? entry?.learningNugget,
            lastModified: Date(),
            syncStatus: .pendingUpload,
            title: entry?.title,
            content: entry?.content,
            location: entry?.location,
            imageURLs: nil,
            localImagePaths: nil
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
                    handleError(error)
                }
            }
        }
    }
}

// MARK: - Supporting Views

enum JournalError: LocalizedError {
    case authError
    case saveError(String)
    case loadError(String)
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .authError:
            return "Bitte melde dich an, um Einträge zu speichern."
        case .saveError(let message):
            return "Fehler beim Speichern: \(message)"
        case .loadError(let message):
            return "Fehler beim Laden: \(message)"
        case .networkError(let message):
            return "Netzwerkfehler: \(message)"
        }
    }
}

struct IdentifiableError: Identifiable {
    let id = UUID()
    let journalError: JournalError
}

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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text(nugget.title)
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
                .font(.body)
                .lineSpacing(4)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if nugget.isAddedToJournal {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Zum Journal hinzugefügt")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
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
    @State private var identifiableError: IdentifiableError?
    @State private var showingProcessingIndicator = false
    
    var body: some View {
        NavigationView {
            ZStack {
                categoryList
                loadingOverlay
            }
            .navigationTitle("Wähle eine Kategorie")
            .navigationBarItems(trailing: cancelButton)
            .onReceive(viewModel.$learningNugget) { nugget in
                handleNuggetChange(nugget)
            }
            .onReceive(viewModel.$error) { error in
                showingProcessingIndicator = false
                if let error = error {
                    handleError(error)
                }
            }
            .alert("Fehler", isPresented: errorBinding) {
                Button("OK", role: .cancel) {
                    clearError()
                }
            } message: {
                Text(identifiableError?.journalError.errorDescription ?? "")
            }
        }
    }
    
    private var categoryList: some View {
        List(LearningNugget.Category.allCases, id: \.self) { category in
            categoryButton(for: category)
        }
    }
    
    private func categoryButton(for category: LearningNugget.Category) -> some View {
        Button(action: { selectCategory(category) }) {
            HStack {
                Text(category.rawValue.capitalized)
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
            }
        }
        .disabled(viewModel.isLoading)
    }
    
    private var loadingOverlay: some View {
        Group {
            if viewModel.isLoading || showingProcessingIndicator {
                ZStack {
                    Color.black.opacity(0.3)
                        .edgesIgnoringSafeArea(.all)
                    VStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text(showingProcessingIndicator ? "Verarbeite Antwort..." : "Generiere Lernerkenntnis...")
                            .foregroundColor(.white)
                            .padding(.top)
                    }
                }
            }
        }
    }
    
    private var cancelButton: some View {
        Button("Abbrechen") {
            dismiss()
        }
    }
    
    private var errorBinding: Binding<Bool> {
        Binding(
            get: { identifiableError != nil },
            set: { if !$0 { clearError() } }
        )
    }
    
    private func selectCategory(_ category: LearningNugget.Category) {
        showingProcessingIndicator = true
        viewModel.generateLearningNugget(for: category)
    }
    
    private func handleNuggetChange(_ nugget: LearningNugget?) {
        showingProcessingIndicator = false
        if nugget != nil {
            dismiss()
        }
    }
    
    private func handleError(_ error: Error) {
        DispatchQueue.main.async {
            let journalError: JournalError
            if let nsError = error as? NSError {
                switch nsError.code {
                case 401:
                    journalError = .authError
                case -1009:
                    journalError = .networkError("Keine Internetverbindung")
                default:
                    journalError = .saveError(nsError.localizedDescription)
                }
            } else {
                journalError = .saveError(error.localizedDescription)
            }
            self.identifiableError = IdentifiableError(journalError: journalError)
        }
    }
    
    private func clearError() {
        identifiableError = nil
        viewModel.error = nil
    }
}

#Preview {
    NavigationView {
        JournalEntryView(viewModel: JournalViewModel())
    }
} 