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
    @State private var showingImagePicker = false
    @State private var isProcessingImages = false
    
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
        // Verwende viewModel.currentEntry?.localImagePaths als primäre Datenquelle und entry?.localImagePaths als Fallback
        guard let localPaths = viewModel.currentEntry?.localImagePaths ?? entry?.localImagePaths, !localPaths.isEmpty else {
            print("Keine lokalen Bildpfade gefunden")
            return nil 
        }
        
        print("Versuche \(localPaths.count) Bilder zu laden")
        
        let images = localPaths.compactMap { path -> UIImage? in
            // Bestimme, ob es sich um einen vollständigen oder relativen Pfad handelt
            let isFullPath = path.hasPrefix("/")
            
            let fileURL: URL
            if isFullPath {
                // Verwende den vollständigen Pfad direkt
                fileURL = URL(fileURLWithPath: path)
                print("Vollständiger Pfad erkannt: \(path)")
            } else {
                // Relativer Pfad: füge Documents-Verzeichnis hinzu
                guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                    print("⚠️ Konnte Documents-Verzeichnis nicht finden")
                    return nil
                }
                fileURL = documentsDirectory.appendingPathComponent(path)
                print("Relativer Pfad zu absolut konvertiert: \(fileURL.path)")
            }
            
            // Überprüfe, ob die Datei existiert
            let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
            print("Prüfe Bild an Pfad: \(fileURL.path) - Existiert: \(fileExists)")
            
            if !fileExists {
                print("⚠️ Bilddatei nicht gefunden: \(fileURL.path)")
                return nil
            }
            
            // Versuche das Bild zu laden
            guard let imageData = try? Data(contentsOf: fileURL),
                  let image = UIImage(data: imageData) else {
                print("⚠️ Fehler beim Laden des Bildes von: \(fileURL.path)")
                return nil
            }
            
            print("✅ Bild erfolgreich geladen: \(fileURL.path)")
            return image
        }
        
        if images.isEmpty {
            print("Keine Bilder konnten geladen werden")
            return nil
        } else {
            print("Erfolgreich \(images.count) Bilder geladen")
            return images
        }
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
        // Verzögerung, um sicherzustellen, dass nur ein Alert angezeigt wird
        let workItem = DispatchWorkItem {
            // Wenn die Processing-Anzeige noch aktiv ist, diese zuerst deaktivieren
            self.showingProcessingIndicator = false
            
            let journalError: JournalError
            
            // Behandlung von ServiceError-Typen
            if let serviceError = error as? ServiceError {
                switch serviceError {
                case .apiQuotaExceeded:
                    journalError = .quotaError("Das Kontingent für KI-Generierungen wurde überschritten. Bitte versuche es später erneut.")
                case .aiServiceUnavailable:
                    journalError = .aiServiceError("Der KI-Service ist derzeit nicht verfügbar. Bitte versuche es später erneut.")
                case .userNotAuthenticated:
                    journalError = .authError
                case .networkError:
                    journalError = .networkError("Netzwerkfehler: Bitte überprüfe deine Internetverbindung.")
                case .databaseError:
                    journalError = .databaseError("Fehler beim Zugriff auf die Datenbank.")
                case .aiGeneration(let message):
                    journalError = .aiGenerationError(message)
                default:
                    journalError = .saveError(serviceError.localizedDescription)
                }
            } else if let nsError = error as? NSError {
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
        
        // Führe den WorkItem aus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }
    
    var body: some View {
        Form {
            headerSection
            journalSections
            learningNuggetSection
            imagesSection
        }
        .navigationTitle(navigationTitle)
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
            if let error = identifiableError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error.journalError.errorDescription ?? "")
                        .fontWeight(.medium)
                    
                    if let recoverySuggestion = error.journalError.recoverySuggestion {
                        Text(recoverySuggestion)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .task {
            setupInitialState()
        }
        .onChange(of: viewModel.currentEntry) { newEntry in
            if let entry = newEntry {
                gratitude = entry.gratitude
                highlight = entry.highlight
                learning = entry.learning
            }
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
                LearningNuggetView(nugget: nugget) {
                    // Setze das aktuelle Learning Nugget zurück, damit ein neues geladen werden kann
                    viewModel.learningNugget = nil
                    
                    // Verzögere das Öffnen des Auswahlfensters, damit die onReceive-Handler Zeit haben
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        showingLearningNugget = true
                    }
                }
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
    
    private func deleteImage(_ url: String) {
        guard var currentEntry = viewModel.currentEntry else { return }
        
        // Entferne die URL aus den imageURLs
        currentEntry.imageURLs = currentEntry.imageURLs?.filter { $0 != url }
        
        // Speichere den aktualisierten Eintrag
        viewModel.saveEntry(currentEntry)
    }
    
    private func saveNewImages(_ images: [UIImage]) async {
        guard !images.isEmpty else { return }
        guard var currentEntry = viewModel.currentEntry else {
            await MainActor.run {
                showingProcessingIndicator = false
                identifiableError = IdentifiableError(journalError: .saveError("Kein aktiver Eintrag gefunden"))
            }
            return
        }
        
        // Sicherheitsmaßnahme: Überprüfe, ob alle Bilder gültig sind
        let validImages = images.filter { $0.size.width > 0 && $0.size.height > 0 }
        if validImages.count != images.count {
            print("⚠️ Einige Bilder waren ungültig und wurden gefiltert")
        }
        
        await MainActor.run {
            isProcessingImages = true
        }
        
        do {
            // Speichere die neuen Bilder und erhalte die aktualisierten URLs
            let savedEntry = try await viewModel.saveEntryWithImages(currentEntry, images: validImages)
            
            // Aktualisiere den currentEntry mit den neuen URLs
            await MainActor.run {
                viewModel.currentEntry = savedEntry
                // Setze selectedImages zurück, da sie jetzt gespeichert sind
                selectedImages = []
                isProcessingImages = false
                print("✅ Bilder erfolgreich gespeichert: \(savedEntry.imageURLs?.count ?? 0) URLs, \(savedEntry.localImagePaths?.count ?? 0) lokale Pfade")
            }
        } catch {
            await MainActor.run {
                isProcessingImages = false
                print("❌ Fehler beim Speichern der Bilder: \(error.localizedDescription)")
                handleError(error)
                // Setze selectedImages zurück, um erneutes Speichern zu ermöglichen
                selectedImages = []
            }
        }
    }
    
    private var imagesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Bilder")
                    .font(.headline)
                Spacer()
                if !isProcessingImages {
                    Button(action: {
                        selectedImages = []
                        showingImagePicker = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.orange)
                    }
                    .disabled(((viewModel.currentEntry?.imageURLs?.count ?? entry?.imageURLs?.count) ?? 0) + selectedImages.count >= maxImages)
                }
            }
            
            // Lade und zeige bestehende URL-Bilder
            let imageURLs = viewModel.currentEntry?.imageURLs ?? entry?.imageURLs
            if let imageURLs = imageURLs, !imageURLs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(imageURLs, id: \.self) { url in
                            AsyncImage(url: URL(string: url)) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } placeholder: {
                                ProgressView()
                                    .frame(width: 100, height: 100)
                            }
                            .overlay(
                                Button(action: {
                                    deleteImage(url)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.white)
                                        .background(Color.black.opacity(0.5))
                                        .clipShape(Circle())
                                }
                                .padding(4),
                                alignment: .topTrailing
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            
            // Lade und zeige ausgewählte neue Bilder
            if !selectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(selectedImages, id: \.self) { image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(selectedImages: $selectedImages, selectionLimit: maxImages - (viewModel.currentEntry?.imageURLs?.count ?? entry?.imageURLs?.count ?? 0))
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
        
        // Verwende die neuesten Bildinformationen aus viewModel.currentEntry als primäre Quelle
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
            imageURLs: viewModel.currentEntry?.imageURLs ?? entry?.imageURLs,
            localImagePaths: viewModel.currentEntry?.localImagePaths ?? entry?.localImagePaths
        )
        
        print("Speichere Eintrag mit: \(updatedEntry.imageURLs?.count ?? 0) URLs und \(updatedEntry.localImagePaths?.count ?? 0) lokalen Pfaden")
        
        Task {
            do {
                // Wenn neue Bilder ausgewählt wurden
                if !selectedImages.isEmpty {
                    let savedEntry = try await viewModel.saveEntryWithImages(updatedEntry, images: selectedImages)
                    print("Eintrag gespeichert mit URLs: \(String(describing: savedEntry.imageURLs))")
                    print("Lokale Pfade: \(String(describing: savedEntry.localImagePaths))")
                    
                    await MainActor.run {
                        dismiss()
                    }
                } 
                // Wenn keine neuen Bilder ausgewählt wurden, speichere nur den Text-Eintrag ohne Bilder zu verarbeiten
                else {
                    viewModel.saveEntry(updatedEntry)
                    print("Eintrag ohne neue Bilder gespeichert")
                    
                    await MainActor.run {
                        dismiss()
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
    
    private var navigationTitle: String {
        if let entry = entry {
            // Formatiere das Datum
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .none
            dateFormatter.locale = Locale(identifier: "de_DE")
            return dateFormatter.string(from: entry.date)
        } else {
            return "Neuer Eintrag"
        }
    }
}

// MARK: - Supporting Views

enum JournalError: LocalizedError {
    case authError
    case saveError(String)
    case loadError(String)
    case networkError(String)
    case quotaError(String)
    case aiServiceError(String)
    case aiGenerationError(String)
    case databaseError(String)
    
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
        case .quotaError(let message):
            return message
        case .aiServiceError(let message):
            return message
        case .aiGenerationError(let message):
            return "Fehler bei der KI-Generierung: \(message)"
        case .databaseError(let message):
            return "Datenbankfehler: \(message)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .quotaError:
            return "Dein monatliches Kontingent für KI-Generierungen wurde erreicht. Das Kontingent wird am Anfang des nächsten Monats zurückgesetzt."
        case .aiServiceError:
            return "Der KI-Service ist momentan nicht erreichbar. Du kannst es später erneut versuchen oder die App neu starten."
        case .networkError:
            return "Stelle sicher, dass deine Internetverbindung aktiv ist und versuche es erneut."
        case .databaseError:
            return "Bitte folge dem Link in der Fehlermeldung, um den erforderlichen Datenbankindex zu erstellen, oder kontaktiere den Support."
        default:
            return nil
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
    var onReload: (() -> Void)?
    
    private var formattedTitle: String {
        // Entferne Anführungszeichen (einfache und doppelte) am Anfang und Ende des Titels
        var title = nugget.title
        if title.hasPrefix("\"") && title.hasSuffix("\"") {
            title = String(title.dropFirst().dropLast())
        } else if title.hasPrefix("'") && title.hasSuffix("'") {
            title = String(title.dropFirst().dropLast())
        } else if title.hasPrefix("**") && title.hasSuffix("**") {
            title = String(title.dropFirst(2).dropLast(2))
        }
        return title
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text(formattedTitle)
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
            
            HStack {
                if nugget.isAddedToJournal {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Zum Journal hinzugefügt")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if let onReload = onReload {
                    Button(action: onReload) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Neues Nugget")
                                .font(.caption)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
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
    @State private var selectedCategory: LearningNugget.Category = .persönlichesWachstum
    
    var body: some View {
        NavigationView {
            ZStack {
                categoryList
                loadingOverlay
            }
            .navigationTitle("Wähle eine Kategorie")
            .navigationBarItems(trailing: cancelButton)
            .onReceive(viewModel.$learningNugget) { nugget in
                // Nur reagieren, wenn ein Nugget gesetzt wird, nicht wenn es gelöscht wird
                if nugget != nil {
                    handleNuggetChange(nugget)
                }
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
                if let error = identifiableError {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error.journalError.errorDescription ?? "")
                            .fontWeight(.medium)
                        
                        if let recoverySuggestion = error.journalError.recoverySuggestion {
                            Text(recoverySuggestion)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
    
    private var categoryList: some View {
        List(LearningNugget.Category.allCases.filter { $0 != .aiGenerated }, id: \.self) { category in
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
                        Text(showingProcessingIndicator ? "Verarbeite Antwort..." : "Lade Learning Nugget...")
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
        // Vermeide doppelte Aktionen, wenn bereits ein Generierungsvorgang läuft
        guard !viewModel.isLoading && !showingProcessingIndicator else { return }
        
        // Zurücksetzen von Fehler vor dem Start der Generierung
        clearError()
        
        showingProcessingIndicator = true
        selectedCategory = category
        
        Task {
            do {
                guard let userId = Auth.auth().currentUser?.uid else {
                    throw ServiceError.userNotAuthenticated
                }
                
                let nugget = try await SharedLearningNuggetService.shared.fetchLearningNugget(for: category, userId: userId)
                await MainActor.run {
                    viewModel.learningNugget = nugget
                    showingProcessingIndicator = false
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                    showingProcessingIndicator = false
                }
            }
        }
    }
    
    private func handleNuggetChange(_ nugget: LearningNugget?) {
        showingProcessingIndicator = false
        if nugget != nil {
            dismiss()
        }
    }
    
    private func handleError(_ error: Error) {
        // Verzögerung, um sicherzustellen, dass nur ein Alert angezeigt wird
        let workItem = DispatchWorkItem {
            // Wenn die Processing-Anzeige noch aktiv ist, diese zuerst deaktivieren
            self.showingProcessingIndicator = false
            
            let journalError: JournalError
            
            // Behandlung von ServiceError-Typen
            if let serviceError = error as? ServiceError {
                switch serviceError {
                case .apiQuotaExceeded:
                    journalError = .quotaError("Das Kontingent für KI-Generierungen wurde überschritten. Bitte versuche es später erneut.")
                case .aiServiceUnavailable:
                    journalError = .aiServiceError("Der KI-Service ist derzeit nicht verfügbar. Bitte versuche es später erneut.")
                case .userNotAuthenticated:
                    journalError = .authError
                case .networkError:
                    journalError = .networkError("Netzwerkfehler: Bitte überprüfe deine Internetverbindung.")
                case .databaseError:
                    journalError = .databaseError("Fehler beim Zugriff auf die Datenbank.")
                case .aiGeneration(let message):
                    journalError = .aiGenerationError(message)
                default:
                    journalError = .saveError(serviceError.localizedDescription)
                }
            } else if let nsError = error as? NSError {
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
        
        // Führe den WorkItem aus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
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