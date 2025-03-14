import Foundation
import OSLog
import FirebaseAuth

enum DeepSeekError: Error, LocalizedError {
    case invalidResponse
    case apiError(String)
    case encodingError
    case decodingError
    case networkError
    case modelNotFound
    case authenticationError
    case rateLimitExceeded
    case unknownError
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Ungültige Antwort vom Server erhalten."
        case .apiError(let message):
            return "API-Fehler: \(message)"
        case .encodingError:
            return "Fehler bei der Kodierung der Anfrage."
        case .decodingError:
            return "Fehler bei der Dekodierung der Antwort."
        case .networkError:
            return "Netzwerkfehler bei der Kommunikation mit dem Server."
        case .modelNotFound:
            return "Das angeforderte Modell wurde nicht gefunden."
        case .authenticationError:
            return "Authentifizierungsfehler: Ungültiger API-Key."
        case .rateLimitExceeded:
            return "Das Anfragelimit wurde überschritten. Bitte versuche es später erneut."
        case .unknownError:
            return "Ein unbekannter Fehler ist aufgetreten."
        }
    }
}

actor DeepSeekService {
    // MARK: - Properties
    private let apiKey: String
    private let baseURL = "https://api.deepseek.com/v1"
    private let logger = Logger(subsystem: "com.eunoia.journal", category: "DeepSeekService")
    
    // MARK: - Singleton
    static let shared = DeepSeekService()
    
    private init() {
        self.apiKey = APIKeys.deepSeekKey
    }
    
    // MARK: - Helper Methods
    
    /// Extrahiert den Inhalt aus der Antwort des DeepSeek-API
    /// - Parameter response: Die Antwort des DeepSeek-API
    /// - Returns: Der extrahierte Inhalt
    private func extractContentFromResponse(_ response: String) -> String {
        // Versuche, strukturierte Antworten zu erkennen
        
        // Suche nach "Inhalt:" im Text
        if let range = response.range(of: "Inhalt:") {
            let contentStart = range.upperBound
            let content = String(response[contentStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return content
        }
        
        // Wenn "Inhalt:" nicht gefunden wurde, versuche "Content:"
        if let range = response.range(of: "Content:") {
            let contentStart = range.upperBound
            let content = String(response[contentStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return content
        }
        
        // Suche nach Titel/Inhalt-Format
        let titlePattern = #"Titel:\s*(.*?)[\n\r]"#
        let contentPattern = #"(?:Inhalt|Content):\s*(.*?)(?:$|[\n\r])"#
        
        if let titleMatch = response.range(of: titlePattern, options: .regularExpression),
           let contentMatch = response.range(of: contentPattern, options: .regularExpression) {
            let title = response[titleMatch].replacingOccurrences(of: "Titel:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            let content = response[contentMatch].replacingOccurrences(of: "Inhalt:", with: "").replacingOccurrences(of: "Content:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(title): \(content)"
        }
        
        // Wenn keine der Markierungen gefunden wurde, gib die gesamte Antwort zurück
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Public Methods
    
    /// Generiert Text mit dem DeepSeek-API
    /// - Parameter prompt: Der Prompt für die Textgenerierung
    /// - Returns: Der generierte Text
    func generateText(prompt: String) async throws -> String {
        let endpoint = "\(baseURL)/chat/completions"
        
        guard let url = URL(string: endpoint) else {
            throw DeepSeekError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Stelle sicher, dass der API-Key korrekt formatiert ist
        // Wenn der API-Key bereits mit "Bearer " beginnt, verwende ihn direkt,
        // andernfalls füge "Bearer " hinzu
        if self.apiKey.hasPrefix("Bearer ") {
            request.addValue(self.apiKey, forHTTPHeaderField: "Authorization")
        } else {
            request.addValue("Bearer \(self.apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        // Logging für Debugging-Zwecke
        logger.debug("DeepSeek API Key: \(self.apiKey)")
        logger.debug("DeepSeek Endpoint: \(endpoint)")
        
        let requestBody: [String: Any] = [
            "model": "deepseek-chat",
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": 500
        ]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw DeepSeekError.encodingError
        }
        
        request.httpBody = httpBody
        
        // Logging des Request-Bodies für Debugging
        if let requestBodyString = String(data: httpBody, encoding: .utf8) {
            logger.debug("DeepSeek Request Body: \(requestBodyString)")
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw DeepSeekError.invalidResponse
            }
            
            // Logging der Response für Debugging
            logger.debug("DeepSeek Response Status: \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                logger.debug("DeepSeek Response: \(responseString)")
            }
            
            if !(200...299).contains(httpResponse.statusCode) {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String,
                   let code = error["code"] as? String {
                    
                    logger.error("DeepSeek Error Code: \(code)")
                    logger.error("DeepSeek Error Message: \(message)")
                    
                    switch code {
                    case "invalid_api_key", "invalid_request_error":
                        throw DeepSeekError.authenticationError
                    case "rate_limit_exceeded":
                        throw DeepSeekError.rateLimitExceeded
                    case "model_not_found":
                        // Fallback auf ein anderes Modell, falls verfügbar
                        let fallbackBody = try? JSONSerialization.data(withJSONObject: [
                            "model": "deepseek-lite", // Anpassen an ein alternatives DeepSeek-Modell
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
                        throw DeepSeekError.apiError("\(code): \(message)")
                    }
                }
                throw DeepSeekError.apiError("Status Code: \(httpResponse.statusCode)")
            }
            
            // Versuche, die Antwort zu parsen
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                return extractContentFromResponse(content)
            }
            
            if let responseString = String(data: data, encoding: .utf8) {
                return extractContentFromResponse(responseString)
            }
            
            throw DeepSeekError.decodingError
        } catch {
            logger.error("DeepSeek Error: \(error.localizedDescription)")
            if let networkError = error as? URLError {
                switch networkError.code {
                case .notConnectedToInternet:
                    throw DeepSeekError.networkError
                default:
                    throw DeepSeekError.apiError(networkError.localizedDescription)
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
        // Wir verwenden hier noch die OpenAIResponse-Struktur, da das Format ähnlich sein sollte
        // Bei Bedarf könnte eine eigene DeepSeekResponse-Struktur erstellt werden
        guard let jsonData = jsonString.data(using: .utf8) else {
            logger.error("Fehler beim Konvertieren des JSON-Strings in Data")
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            let response = try decoder.decode(OpenAIResponse.self, from: jsonData)
            return response
        } catch {
            logger.error("Fehler beim Decodieren der DeepSeek-Antwort: \(error.localizedDescription)")
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
    
    func generateLearningNugget(from prompt: String) async throws -> LearningNugget {
        let content = try await generateText(prompt: prompt)
        
        return LearningNugget(
            userId: Auth.auth().currentUser?.uid ?? "test",
            category: .aiGenerated,
            title: "Lernimpuls",
            content: content
        )
    }
    
    // MARK: - Test Methods
    
    /// Testet die DeepSeek-Integration
    /// - Returns: Der generierte Text oder eine Fehlermeldung
    func testDeepSeekIntegration() async -> String {
        do {
            logger.debug("Starte DeepSeek-Integrationstest")
            logger.debug("API-Key: \(self.apiKey)")
            
            // Teste zuerst die API-Verbindung mit einer einfachen Anfrage
            let endpoint = "\(baseURL)/chat/completions"
            guard let url = URL(string: endpoint) else {
                return "DeepSeek-Test fehlgeschlagen: Ungültige URL"
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Korrigiere das Format des API-Keys im Authorization-Header
            // Wenn der API-Key bereits mit "Bearer " beginnt, verwende ihn direkt,
            // andernfalls füge "Bearer " hinzu
            if self.apiKey.hasPrefix("Bearer ") {
                request.addValue(self.apiKey, forHTTPHeaderField: "Authorization")
            } else {
                request.addValue("Bearer \(self.apiKey)", forHTTPHeaderField: "Authorization")
            }
            
            let simpleRequestBody: [String: Any] = [
                "model": "deepseek-chat",
                "messages": [
                    ["role": "user", "content": "Hallo"]
                ],
                "max_tokens": 5
            ]
            
            guard let httpBody = try? JSONSerialization.data(withJSONObject: simpleRequestBody) else {
                return "DeepSeek-Test fehlgeschlagen: Fehler bei der Kodierung der Anfrage"
            }
            
            request.httpBody = httpBody
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    return "DeepSeek-Test fehlgeschlagen: Ungültige Antwort"
                }
                
                logger.debug("DeepSeek API-Verbindungstest Status: \(httpResponse.statusCode)")
                
                if !(200...299).contains(httpResponse.statusCode) {
                    if let responseString = String(data: data, encoding: .utf8) {
                        logger.error("DeepSeek API-Verbindungstest Fehler: \(responseString)")
                        return "DeepSeek-Test fehlgeschlagen: Status \(httpResponse.statusCode), Antwort: \(responseString)"
                    } else {
                        return "DeepSeek-Test fehlgeschlagen: Status \(httpResponse.statusCode)"
                    }
                }
                
                logger.debug("DeepSeek API-Verbindungstest erfolgreich")
            } catch {
                logger.error("DeepSeek API-Verbindungstest Fehler: \(error.localizedDescription)")
                return "DeepSeek API-Verbindungstest fehlgeschlagen: \(error.localizedDescription)"
            }
            
            // Wenn der Verbindungstest erfolgreich war, führe den eigentlichen Test durch
            let prompt = "Erkläre in einem Satz, was Swift ist."
            let result = try await generateText(prompt: prompt)
            return "DeepSeek-Test erfolgreich: \(result)"
        } catch {
            logger.error("DeepSeek-Test fehlgeschlagen: \(error.localizedDescription)")
            return "DeepSeek-Test fehlgeschlagen: \(error.localizedDescription)"
        }
    }
} 
