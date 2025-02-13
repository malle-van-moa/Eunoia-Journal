import SwiftUI
import JournalingSuggestions

@available(iOS 17.2, *)
struct JournalingSuggestionsView: View {
    @StateObject private var viewModel = JournalViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showingSettingsInfo = false
    
    var body: some View {
        VStack {
            JournalingSuggestionsPicker("Vorschläge durchsuchen") { suggestion in
                await createEntry(from: suggestion)
            }
            .navigationTitle("Journaling Vorschläge")
        }
        .alert("Keine Vorschläge?", isPresented: $showingSettingsInfo) {
            Button("Abbrechen", role: .cancel) {}
            Button("Einstellungen") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
        } message: {
            Text("Stelle sicher, dass du in den Einstellungen unter 'Datenschutz & Sicherheit' > 'Journaling Vorschläge' den Zugriff für Eunoia erlaubt hast.")
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingSettingsInfo = true }) {
                    Image(systemName: "info.circle")
                }
            }
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