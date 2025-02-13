import SwiftUI
import JournalingSuggestions

@available(iOS 17.2, *)
struct JournalingSuggestionsView: View {
    @StateObject private var viewModel = JournalViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showingSettingsInfo = false
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Lade Vorschläge...")
            } else {
                VStack {
                    JournalingSuggestionsPicker<JournalingSuggestion>("Vorschläge durchsuchen") { suggestion in
                        await createEntry(from: suggestion)
                    }
                    .navigationTitle("Journaling Vorschläge")
                }
            }
        }
        .alert("Keine Vorschläge?", isPresented: $showingSettingsInfo) {
            Button("Abbrechen", role: .cancel) {}
            Button("Einstellungen") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
        } message: {
            Text("Stelle sicher, dass:\n\n1. Du in den Einstellungen unter 'Datenschutz & Sicherheit' > 'Journaling Vorschläge' den Zugriff für Eunoia erlaubt hast.\n\n2. Du iOS 17.2 oder höher verwendest.\n\n3. Dein Gerät Aktivitäten aufzeichnet, die als Vorschläge dienen können.")
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingSettingsInfo = true }) {
                    Image(systemName: "info.circle")
                }
            }
        }
        .task {
            // Verzögerung für bessere UX
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            isLoading = false
        }
    }
    
    private func createEntry(from suggestion: JournalingSuggestion) async {
        await viewModel.createEntryFromSuggestion(suggestion)
        dismiss()
    }
}

#Preview {
    if #available(iOS 17.2, *) {
        NavigationView {
            JournalingSuggestionsView()
        }
    } else {
        Text("Nur verfügbar ab iOS 17.2")
    }
} 