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
        Task { @MainActor in
            if let entry = entry {
                print("🔄 [SETUP] Initialisiere viewModel.currentEntry mit existierendem Entry (ID: \(entry.id ?? "unknown"))")
                viewModel.currentEntry = JournalEntry(
                    id: entry.id,
                    userId: entry.userId,
                    date: entry.date,
                    gratitude: entry.gratitude,
                    highlight: entry.highlight,
                    learning: entry.learning,
                    learningNugget: entry.learningNugget,
                    lastModified: entry.lastModified,
                    syncStatus: entry.syncStatus,
                    title: entry.title,
                    content: entry.content,
                    location: entry.location,
                    imageURLs: entry.imageURLs,
                    localImagePaths: entry.localImagePaths,
                    images: entry.images
                )
            } else {
                print("🔄 [SETUP] Erstelle neuen Entry")
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
        // Verbesserter Navigationsbereich mit explizitem Layout
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(navigationTitle)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                cancelButton
                    .padding(.top, 5) // Mehr Platz nach oben
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    deleteButton
                    saveButton
                }
                .padding(.top, 5) // Mehr Platz nach oben
            }
        }
        // Einstellungen für Sheet-Anzeigen
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
        // Explizit keine Animation auf den TextEditor-Komponenten, nur auf Layoutänderungen
        .transaction { transaction in
            // Deaktiviere implizite Animationen für TextEditor
            if transaction.animation != nil {
                transaction.disablesAnimations = true
            }
        }
        .task {
            print("🔄 [VIEW] task ausgelöst")
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
                VStack(alignment: .leading, spacing: 8) {
                    Text("Lernimpuls")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .padding(.horizontal)
                    
                    LearningNuggetView(nugget: nugget) {
                        // Vermeide direkte Zustandsänderung in View-Builder
                        reloadLearningNugget()
                    }
                }
            } else {
                Section(header: Text("Lernimpuls")) {
                    learningNuggetButton
                }
            }
        }
    }
    
    private func reloadLearningNugget() {
        // Setze das aktuelle Learning Nugget zurück, damit ein neues geladen werden kann
        viewModel.learningNugget = nil
        
        // Verzögere das Öffnen des Auswahlfensters, damit die onReceive-Handler Zeit haben
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.showingLearningNugget = true
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
                color: .red,
                onSuggestionTap: {
                    selectedField = .gratitude
                    showingAISuggestions = true
                }
            )
            
            // Highlight Section - wieder standard
            JournalSection(
                title: "Was war dein Highlight heute?",
                text: $highlight,
                systemImage: "star.fill",
                color: .yellow,
                onSuggestionTap: {
                    selectedField = .highlight
                    showingAISuggestions = true
                }
            )
            
            // Learning Section
            JournalSection(
                title: "Was hast du heute gelernt?",
                text: $learning,
                systemImage: "book.fill",
                color: .blue,
                onSuggestionTap: {
                    selectedField = .learning
                    showingAISuggestions = true
                }
            )
        }
    }
    
    private func deleteImage(_ url: String) {
        print("📷 [DELETE-IMAGE] Lösche Bild mit URL: \(url)")
        
        // Gesamten Bildzählerstand vor der Löschung protokollieren
        let initialImageCount = (viewModel.currentEntry?.imageURLs?.count ?? 0) + selectedImages.count
        print("📊 [DELETE-IMAGE] Bildanzahl VOR Löschung: \(initialImageCount)/\(maxImages)")
        
        guard var currentEntry = viewModel.currentEntry else { 
            print("❌ [DELETE-IMAGE] Kein aktueller Eintrag gefunden")
            return 
        }
        
        // Prüfe, ob der Entry Bilder hat
        guard let imageUrls = currentEntry.imageURLs, !imageUrls.isEmpty else {
            print("❌ [DELETE-IMAGE] Entry hat keine Bilder")
            return
        }
        
        // Finde den Index des zu löschenden Bildes
        guard let index = imageUrls.firstIndex(where: { $0 == url }) else {
            print("❌ [DELETE-IMAGE] URL nicht gefunden: \(url)")
            return
        }
        
        print("✓ [DELETE-IMAGE] URL gefunden an Position \(index): \(url)")
        
        // Entferne die URL
        var updatedImageUrls = imageUrls
        updatedImageUrls.remove(at: index)
        
        // Wenn noch lokale Pfade vorhanden sind, entferne auch den entsprechenden lokalen Pfad
        if var localPaths = currentEntry.localImagePaths,
           index < localPaths.count,
           !localPaths.isEmpty {
            let localPath = localPaths[index]
            print("🗑 [DELETE-IMAGE] Entferne auch lokalen Pfad: \(localPath)")
            localPaths.remove(at: index)
            
            // Aktualisiere die localImagePaths im Entry
            currentEntry.localImagePaths = localPaths.isEmpty ? nil : localPaths
        }
        
        // Aktualisiere die imageURLs im Entry
        currentEntry.imageURLs = updatedImageUrls.isEmpty ? nil : updatedImageUrls
        
        // Protokolliere den neuen Zählerstand
        let newURLsCount = currentEntry.imageURLs?.count ?? 0
        print("📊 [DELETE-IMAGE] Neue URL-Anzahl: \(newURLsCount) (vorher: \(imageUrls.count))")
        
        // Lösche das Bild aus dem Storage und aktualisiere den Eintrag
        Task {
            do {
                // Versuche das Bild aus dem Cloud Storage zu löschen
                try await viewModel.deleteCloudImage(url: url)
                print("✅ [DELETE-IMAGE] Bild aus Cloud Storage gelöscht: \(url)")
            } catch {
                print("⚠️ [DELETE-IMAGE] Fehler beim Löschen aus Cloud: \(error.localizedDescription)")
                // Setze den Prozess fort, auch wenn das Löschen aus der Cloud fehlschlägt
            }
            
            // Aktualisiere das ViewModel und die Datenbank
            await MainActor.run {
                do {
                    // Speichere den aktualisierten Eintrag in CoreData
                    try viewModel.persistChanges(entry: currentEntry)
                    
                    // Aktualisiere das viewModel mit dem neuen Entry
                    viewModel.currentEntry = currentEntry
                    
                    // Aktualisiere auch den entry, von dem die View abhängt
                    if let entryId = currentEntry.id, let entryIndex = viewModel.journalEntries.firstIndex(where: { $0.id == entryId }) {
                        viewModel.journalEntries[entryIndex] = currentEntry
                        print("✅ [DELETE-IMAGE] Auch journalEntries-Liste aktualisiert an Position \(entryIndex)")
                    }
                    
                    // Sende explizit ein objectWillChange-Event, um die UI zu aktualisieren
                    viewModel.objectWillChange.send()
                    print("✅ [DELETE-IMAGE] UI-Aktualisierung angestoßen")
                    
                    // Protokolliere den finalen Zählerstand
                    let finalImageCount = (viewModel.currentEntry?.imageURLs?.count ?? 0) + selectedImages.count
                    print("📊 [DELETE-IMAGE] Bildanzahl NACH Löschung: \(finalImageCount)/\(maxImages)")
                    print("📊 [DELETE-IMAGE] Erfolgreich \(initialImageCount - finalImageCount) Bild(er) entfernt")
                } catch {
                    print("❌ [DELETE-IMAGE] Fehler beim Aktualisieren in CoreData: \(error.localizedDescription)")
                }
            }
        }
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
    
    private func logImageCounter() {
        let urlCount = viewModel.currentEntry?.imageURLs?.count ?? 0
        let selectedCount = selectedImages.count
        let currentImageCount = urlCount + selectedCount
        print("📊 BILD-COUNTER - URLs: \(urlCount), ausstehend: \(selectedCount), gesamt: \(currentImageCount)/\(maxImages)")
    }
    
    private var imagesSection: some View {
        // Hier die Debugausgaben in einer Methode aufrufen
        let _ = logImageCounter()
        
        // Berechne die Anzahl für die Anzeige
        let urlCount = viewModel.currentEntry?.imageURLs?.count ?? 0
        let selectedCount = selectedImages.count
        let currentImageCount = urlCount + selectedCount
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Bilder")
                    .font(.headline)
                
                // Zeige Bilderzähler an
                Text("\(currentImageCount)/\(maxImages)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(currentImageCount >= maxImages ? .red : .secondary)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.1))
                    )
                    .transition(.opacity)
                    .id("counter-\(currentImageCount)") // Forciert View-Update bei Counter-Änderungen
                
                Spacer()
                
                if !isProcessingImages {
                    Button(action: {
                        selectedImages = []
                        showingImagePicker = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(currentImageCount >= maxImages ? .gray : .orange)
                    }
                    .disabled(currentImageCount >= maxImages)
                }
            }
            
            // Lade und zeige bestehende URL-Bilder
            if let imageURLs = viewModel.currentEntry?.imageURLs, !imageURLs.isEmpty {
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
                            .id("image-\(url)") // Wichtig: Eindeutiger ID für jedes Bild
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            
            // Lade und zeige ausgewählte neue Bilder
            if !selectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(selectedImages.enumerated()), id: \.element) { index, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                // Füge auch hier einen Löschen-Button hinzu
                                .overlay(
                                    Button(action: {
                                        // Entferne Bild aus ausgewählten Bildern
                                        selectedImages.remove(at: index)
                                        // Kein viewModel.objectWillChange.send() hier
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
            
            // Informationstext, wenn keine Bilder hinzugefügt wurden
            if (viewModel.currentEntry?.imageURLs?.isEmpty ?? true) && selectedImages.isEmpty {
                HStack {
                    Spacer()
                    Text("Keine Bilder hinzugefügt")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        .sheet(isPresented: $showingImagePicker) {
            // Berechne verbleibende Slots mit einzelnen Zwischenschritten
            let existingImageCount = viewModel.currentEntry?.imageURLs?.count ?? 0
            let totalSelected = existingImageCount + selectedImages.count
            let remainingSlots = maxImages - totalSelected
            let finalLimit = remainingSlots > 0 ? remainingSlots : 0
            
            ImagePicker(selectedImages: $selectedImages, selectionLimit: finalLimit)
        }
        .onChange(of: selectedImages) { newSelectedImages in
            // Logge Änderungen an den ausgewählten Bildern
            let urlCount = viewModel.currentEntry?.imageURLs?.count ?? 0
            let selectedCount = newSelectedImages.count
            print("📊 [IMAGE-SELECTION] Neue Bildauswahl: URLs: \(urlCount), ausstehend: \(selectedCount), gesamt: \(urlCount + selectedCount)/\(maxImages)")
        }
        .onAppear {
            // Initialisiere currentEntry mit entry, falls noch nicht geschehen - hierhin verschoben
            if viewModel.currentEntry == nil && entry != nil {
                viewModel.currentEntry = entry
            }
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
        
        // Verwende ausschließlich die aktuelle Bildliste aus dem ViewModel
        let imageURLs = viewModel.currentEntry?.imageURLs
        let localImagePaths = viewModel.currentEntry?.localImagePaths
        
        print("🔄 [SAVE] Speichere Eintrag mit \(imageURLs?.count ?? 0) Bild-URLs und \(localImagePaths?.count ?? 0) lokalen Pfaden")
        
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
            imageURLs: imageURLs,  // Keine Fallback-Verwendung von entry?.imageURLs mehr
            localImagePaths: localImagePaths  // Keine Fallback-Verwendung von entry?.localImagePaths mehr
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
            // Header
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
            
            // Vereinfachter TextEditor ohne spezielle Features, die zu Decodierungsfehlern führen könnten
            if #available(iOS 16.0, *) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemBackground))
                    
                    TextEditor(text: $text)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .padding(8)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2))
                )
                .frame(height: 100)
            } else {
                // Fallback für ältere iOS-Versionen
                PlainTextEditor(text: $text)
                    .frame(height: 100)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2))
                    )
            }
        }
    }
}

// Vereinfachte PlainTextEditor-Implementierung
struct PlainTextEditor: UIViewRepresentable {
    @Binding var text: String
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.isScrollEnabled = true
        textView.isEditable = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        
        // Einfache Konfiguration ohne potenziell problematische Auto-Layout-Einstellungen
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        // Einfache Aktualisierung ohne komplexe Cursor-Positionserhaltung
        if uiView.text != text {
            uiView.text = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: PlainTextEditor
        
        init(_ parent: PlainTextEditor) {
            self.parent = parent
        }
        
        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
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

// Vereinfachter optimierter TextEditor ohne Layout-Probleme
struct EnhancedTextEditor: View {
    @Binding var text: String
    
    var body: some View {
        if #available(iOS 16.0, *) {
            ZStack {
                Rectangle()
                    .fill(Color(.systemBackground))
                    .cornerRadius(8)
                
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(8)
            }
            .frame(height: 100)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2))
            )
        } else {
            PlainTextEditor(text: $text)
                .frame(height: 100)
                .background(Color(.systemBackground))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2))
                )
        }
    }
}

#Preview {
    NavigationView {
        JournalEntryView(viewModel: JournalViewModel())
    }
} 