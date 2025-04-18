import Foundation
import FirebaseAuth

enum OpenAIError: Error {
    case invalidResponse
    case apiError(String)
    case encodingError
    case rateLimitExceeded
    case authenticationError
    case networkError
    case modelNotAvailable
    case contextLengthExceeded
    case invalidRequest
    
    var localizedDescription: String {
        switch self {
        case .invalidResponse:
            return "Ungültige Antwort vom OpenAI-Server"
        case .apiError(let message):
            return "OpenAI API Fehler: \(message)"
        case .encodingError:
            return "Fehler bei der Kodierung der Anfrage"
        case .rateLimitExceeded:
            return "Das API-Limit wurde überschritten. Bitte versuche es später erneut."
        case .authenticationError:
            return "Authentifizierungsfehler. Bitte überprüfe deinen API-Schlüssel."
        case .networkError:
            return "Netzwerkfehler. Bitte überprüfe deine Internetverbindung."
        case .modelNotAvailable:
            return "Das gewählte Modell ist derzeit nicht verfügbar. Ein alternatives Modell wird verwendet."
        case .contextLengthExceeded:
            return "Die maximale Textlänge wurde überschritten."
        case .invalidRequest:
            return "Die Anfrage konnte nicht verarbeitet werden. Bitte versuche es erneut."
        }
    }
}

actor OpenAIService {
    static let shared = OpenAIService()
    private let apiKey = APIKeys.openAIKey
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    
    private init() {}
    
    private func extractContentFromResponse(_ data: Data) throws -> String {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.invalidResponse
        }
        
        // Extrahiere den Inhalt zwischen "Inhalt:" und dem nächsten "\n" oder Ende
        if let contentRange = content.range(of: "Inhalt:") {
            let afterInhalt = content[contentRange.upperBound...].trimmingCharacters(in: .whitespaces)
            // Wenn es weitere Newlines gibt, nehmen wir nur den ersten Teil
            if let newlineRange = afterInhalt.range(of: "\n") {
                return String(afterInhalt[..<newlineRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            return afterInhalt
        }
        
        // Fallback: Wenn kein "Inhalt:" gefunden wird, gib den gesamten Content zurück
        return content.trimmingCharacters(in: .whitespaces)
    }
    
    func generateText(prompt: String) async throws -> String {
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "model": "gpt-4",
            "messages": [
                ["role": "system", "content": "Du bist ein hilfreicher Assistent für Journaling und Selbstreflexion."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": 150,
            "presence_penalty": 0.0,
            "frequency_penalty": 0.0
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw OpenAIError.encodingError
        }
        
        request.httpBody = jsonData
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenAIError.invalidResponse
            }
            
            if !(200...299).contains(httpResponse.statusCode) {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String,
                   let code = error["code"] as? String {
                    
                    #if DEBUG
                    print("OpenAI Error Code: \(code)")
                    print("OpenAI Error Message: \(message)")
                    #endif
                    
                    switch code {
                    case "invalid_api_key":
                        throw ServiceError.aiServiceUnavailable
                    case "rate_limit_exceeded", "quota_exceeded", "billing_quota_exceeded":
                        throw ServiceError.apiQuotaExceeded
                    case "model_not_found":
                        // Fallback auf gpt-3.5-turbo wenn gpt-4 nicht verfügbar
                        let fallbackBody = try? JSONSerialization.data(withJSONObject: [
                            "model": "gpt-3.5-turbo",
                            "messages": [
                                ["role": "system", "content": "Du bist ein hilfreicher Assistent für Journaling und Selbstreflexion."],
                                ["role": "user", "content": prompt]
                            ],
                            "temperature": 0.7,
                            "max_tokens": 150
                        ])
                        request.httpBody = fallbackBody
                        return try await generateText(prompt: prompt)
                    default:
                        throw ServiceError.aiGeneration("\(code): \(message)")
                    }
                }
                
                // Generic error handling based on HTTP status code
                switch httpResponse.statusCode {
                case 401, 403:
                    throw ServiceError.aiServiceUnavailable
                case 429:
                    throw ServiceError.apiQuotaExceeded
                case 500, 502, 503, 504:
                    throw ServiceError.aiServiceUnavailable
                default:
                    throw ServiceError.aiGeneration("HTTP Fehler \(httpResponse.statusCode)")
                }
            }
            
            #if DEBUG
            print("OpenAI Response Status: \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("OpenAI Response: \(responseString)")
            }
            #endif
            
            return try extractContentFromResponse(data)
        } catch {
            if let networkError = error as? URLError {
                switch networkError.code {
                case .notConnectedToInternet:
                    throw OpenAIError.networkError
                default:
                    throw OpenAIError.apiError(networkError.localizedDescription)
                }
            }
            throw error
        }
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
    
    func generateLearningNugget(category: String) async throws -> LearningNugget {
        let prompt = "Generiere einen kurzen, inspirierenden Lernimpuls zum Thema '\(category)'. Der Text sollte motivierend und zum Nachdenken anregend sein."
        let content = try await generateText(prompt: prompt)
        
        return LearningNugget(
            userId: Auth.auth().currentUser?.uid ?? "test",
            category: .aiGenerated,
            title: "Lernimpuls",
            content: content
        )
    }
    
    func parseResponse(_ jsonString: String) -> OpenAIResponse? {
        guard let jsonData = jsonString.data(using: .utf8) else {
            print("Fehler beim Konvertieren des JSON-Strings in Data")
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            let response = try decoder.decode(OpenAIResponse.self, from: jsonData)
            return response
        } catch {
            print("Fehler beim Decodieren der OpenAI-Antwort: \(error)")
            return nil
        }
    }
    
    func createLearningNugget(from response: OpenAIResponse) -> LearningNugget? {
        guard let (title, content) = response.extractLearningContent() else {
            return nil
        }
        
        return LearningNugget(
            userId: Auth.auth().currentUser?.uid ?? "",
            category: .aiGenerated,
            title: title,
            content: content,
            isAddedToJournal: true
        )
    }
    
    /// Generiert einen Lerninhalt basierend auf dem übergebenen Prompt
    /// - Parameter prompt: Der Prompt für die Textgenerierung
    /// - Returns: Der generierte Lerninhalt als LearningNugget
    func generateLearningNugget(from prompt: String) async throws -> LearningNugget {
        let content = try await generateText(prompt: prompt)
        
        return LearningNugget(
            userId: Auth.auth().currentUser?.uid ?? "test",
            category: .aiGenerated,
            title: "Lernimpuls",
            content: content
        )
    }
} 