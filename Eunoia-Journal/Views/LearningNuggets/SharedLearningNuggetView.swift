import SwiftUI
import FirebaseAuth
import OSLog

struct SharedLearningNuggetView: View {
    @State private var selectedCategory: LearningNugget.Category = .persönlichesWachstum
    @State private var currentNugget: LearningNugget?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    
    private let logger = Logger(subsystem: "com.eunoia.journal", category: "SharedLearningNuggetView")
    
    var body: some View {
        VStack {
            // Kategorie-Auswahl
            Picker("Kategorie", selection: $selectedCategory) {
                ForEach(LearningNugget.Category.allCases.filter { $0 != .aiGenerated }, id: \.self) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .padding()
            .onChange(of: selectedCategory) { _ in
                loadNugget()
            }
            
            // Learning Nugget Anzeige
            if isLoading {
                ProgressView()
                    .padding()
            } else if let nugget = currentNugget {
                VStack(alignment: .leading, spacing: 16) {
                    Text(nugget.title)
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    Text(nugget.content)
                        .font(.body)
                    
                    HStack {
                        Spacer()
                        Text("Kategorie: \(nugget.category.rawValue)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                )
                .padding()
            } else {
                Text("Kein Learning Nugget verfügbar")
                    .foregroundColor(.secondary)
                    .padding()
            }
            
            // Buttons
            HStack {
                Button(action: {
                    loadNugget()
                }) {
                    Label("Neues Nugget", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
                
                if let nugget = currentNugget {
                    Button(action: {
                        addToJournal(nugget)
                    }) {
                        Label("Zum Journal hinzufügen", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)
                }
            }
            .padding()
            
            Spacer()
        }
        .navigationTitle("Learning Nuggets")
        .onAppear {
            loadNugget()
        }
        .alert("Fehler", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Ein unbekannter Fehler ist aufgetreten.")
        }
    }
    
    private func loadNugget() {
        guard let userId = Auth.auth().currentUser?.uid else {
            errorMessage = "Bitte melde dich an, um Learning Nuggets zu sehen."
            showError = true
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                logger.debug("Lade Learning Nugget für Kategorie \(selectedCategory.rawValue)")
                let nugget = try await SharedLearningNuggetService.shared.fetchLearningNugget(for: selectedCategory, userId: userId)
                
                DispatchQueue.main.async {
                    self.currentNugget = nugget
                    self.isLoading = false
                }
            } catch {
                logger.error("Fehler beim Laden des Learning Nuggets: \(error.localizedDescription)")
                
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                    self.isLoading = false
                }
            }
        }
    }
    
    private func addToJournal(_ nugget: LearningNugget) {
        // Hier würde die Logik zum Hinzufügen des Nuggets zum Journal implementiert werden
        // Dies könnte z.B. über einen ViewModel oder einen Service erfolgen
        logger.debug("Füge Learning Nugget zum Journal hinzu: \(nugget.id)")
    }
}

#Preview {
    NavigationView {
        SharedLearningNuggetView()
    }
} 