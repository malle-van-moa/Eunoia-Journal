import Foundation

class DeepSeekService {
    static let shared = DeepSeekService()
    private let apiKey = "sk-677c42a1195642bea31b4454eb4c02f5"
    private let baseURL = "https://api.deepseek.com"
    
    private init() {}
    
    struct ChatMessage: Codable {
        let role: String
        let content: String
    }
    
    struct ChatRequest: Codable {
        let messages: [ChatMessage]
        let model: String
        let temperature: Double
        let max_tokens: Int
    }
    
    struct ChatResponse: Codable {
        let choices: [Choice]
        let error: ErrorResponse?
        
        struct Choice: Codable {
            let message: ChatMessage
            let finish_reason: String?
        }
        
        struct ErrorResponse: Codable {
            let message: String
            let type: String
            let code: String?
        }
    }
    
    func generateResponse(systemPrompt: String, userPrompt: String) async throws -> String {
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let messages = [
            ChatMessage(role: "system", content: systemPrompt),
            ChatMessage(role: "user", content: userPrompt)
        ]
        
        let chatRequest = ChatRequest(
            messages: messages,
            model: "deepseek-chat",
            temperature: 0.7,
            max_tokens: 500
        )
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(chatRequest)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("HTTP Status Code: \(httpResponse.statusCode)")
                print("Response Headers: \(httpResponse.allHeaderFields)")
            }
            
            // Print raw response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                print("Raw Response: \(responseString)")
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse("Invalid HTTP Response")
            }
            
            // Try to decode error response first
            if httpResponse.statusCode != 200 {
                let decoder = JSONDecoder()
                if let errorResponse = try? decoder.decode(ChatResponse.self, from: data),
                   let error = errorResponse.error {
                    switch error.code {
                    case "invalid_request_error" where error.message.contains("Insufficient Balance"):
                        throw APIError.insufficientBalance
                    default:
                        throw APIError.apiError(error.message)
                    }
                }
            }
            
            switch httpResponse.statusCode {
            case 200:
                let decoder = JSONDecoder()
                let chatResponse = try decoder.decode(ChatResponse.self, from: data)
                
                if let error = chatResponse.error {
                    throw APIError.apiError(error.message)
                }
                
                guard let generatedText = chatResponse.choices.first?.message.content else {
                    throw APIError.invalidResponse("No content in response")
                }
                
                return generatedText
                
            case 401:
                throw APIError.unauthorized
            case 402:
                throw APIError.insufficientBalance
            case 429:
                throw APIError.rateLimitExceeded
            case 500...599:
                throw APIError.serverError
            default:
                throw APIError.requestFailed("HTTP Status: \(httpResponse.statusCode)")
            }
        } catch let decodingError as DecodingError {
            print("Decoding Error: \(decodingError)")
            throw APIError.invalidResponse("Decoding Error: \(decodingError.localizedDescription)")
        } catch {
            print("Network Error: \(error)")
            throw APIError.requestFailed("Network Error: \(error.localizedDescription)")
        }
    }
    
    enum APIError: LocalizedError {
        case requestFailed(String)
        case invalidResponse(String)
        case unauthorized
        case insufficientBalance
        case rateLimitExceeded
        case serverError
        case apiError(String)
        
        var errorDescription: String? {
            switch self {
            case .requestFailed(let message):
                return "Anfrage fehlgeschlagen: \(message)"
            case .invalidResponse(let message):
                return "Ungültige Antwort: \(message)"
            case .unauthorized:
                return "Nicht autorisiert. Bitte überprüfen Sie den API-Schlüssel."
            case .insufficientBalance:
                return "Unzureichendes Guthaben für die API-Nutzung. Bitte laden Sie Ihr Konto auf oder aktivieren Sie Ihren Account."
            case .rateLimitExceeded:
                return "API-Limit überschritten. Bitte versuchen Sie es später erneut."
            case .serverError:
                return "Server-Fehler. Bitte versuchen Sie es später erneut."
            case .apiError(let message):
                return "API-Fehler: \(message)"
            }
        }
    }
} 
