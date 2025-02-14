import Foundation

enum OpenAIError: Error {
    case invalidResponse
    case apiError(String)
    case encodingError
    
    var localizedDescription: String {
        switch self {
        case .invalidResponse:
            return "Ungültige Antwort vom OpenAI-Server"
        case .apiError(let message):
            return "OpenAI API Fehler: \(message)"
        case .encodingError:
            return "Fehler bei der Kodierung der Anfrage"
        }
    }
}

actor OpenAIService {
    static let shared = OpenAIService()
    private let apiKey = APIKeys.openAIKey
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    
    private init() {}
    
    func generateText(prompt: String) async throws -> String {
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": [
                ["role": "system", "content": "Du bist ein hilfreicher Assistent für Journaling und Selbstreflexion."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": 150
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw OpenAIError.encodingError
        }
        
        request.httpBody = jsonData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw OpenAIError.invalidResponse
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.invalidResponse
        }
        
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func generateJournalSuggestion(for type: String) async throws -> String {
        let prompt: String
        switch type.lowercased() {
        case "dankbarkeit":
            prompt = "Generiere eine tiefgründige Frage zur Selbstreflexion über Dankbarkeit, die zum Nachdenken anregt."
        case "highlight":
            prompt = "Erstelle eine nachdenkliche Frage, die hilft, die bedeutendsten Momente des Tages zu reflektieren."
        case "lernen":
            prompt = "Formuliere eine Frage, die dazu anregt, über die wichtigsten Lernerfahrungen des Tages nachzudenken."
        default:
            prompt = "Generiere eine allgemeine Frage zur Selbstreflexion für das Journaling."
        }
        
        return try await generateText(prompt: prompt)
    }
    
    func generateLearningNugget(category: String) async throws -> String {
        let prompt = "Generiere einen kurzen, inspirierenden Lernimpuls zum Thema '\(category)'. Der Text sollte motivierend und zum Nachdenken anregend sein."
        return try await generateText(prompt: prompt)
    }
} 