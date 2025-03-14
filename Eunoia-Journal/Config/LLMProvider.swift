import Foundation

/// Repräsentiert die verfügbaren KI-Anbieter für die Textgenerierung
enum LLMProvider: String, CaseIterable, Identifiable {
    case openAI = "OpenAI"
    case deepSeek = "DeepSeek"
    
    var id: String { self.rawValue }
    
    /// Gibt den aktuell ausgewählten Provider zurück
    static var current: LLMProvider {
        if let savedProvider = UserDefaults.standard.string(forKey: "selectedLLMProvider"),
           let provider = LLMProvider(rawValue: savedProvider) {
            return provider
        } else {
            // Standardmäßig DeepSeek verwenden
            return .deepSeek
        }
    }
    
    /// Speichert den ausgewählten Provider in UserDefaults
    static func save(_ provider: LLMProvider) {
        UserDefaults.standard.set(provider.rawValue, forKey: "selectedLLMProvider")
    }
} 