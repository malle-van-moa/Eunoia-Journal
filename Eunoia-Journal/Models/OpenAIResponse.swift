import Foundation
import OSLog

struct OpenAIResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [Choice]
    let usage: Usage
    
    struct Choice: Codable {
        let index: Int
        let message: Message
        let finishReason: String
        
        enum CodingKeys: String, CodingKey {
            case index
            case message
            case finishReason = "finish_reason"
        }
    }
    
    struct Message: Codable {
        let role: String
        let content: String
        let refusal: String?
    }
    
    struct Usage: Codable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int
        
        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

extension OpenAIResponse {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Eunoia", category: "OpenAIResponse")
    
    func extractLearningContent() -> (title: String, content: String)? {
        guard let firstChoice = choices.first else {
            Self.logger.error("Keine Choices in der OpenAI-Antwort gefunden")
            return nil
        }
        
        let content = firstChoice.message.content
        Self.logger.debug("Verarbeite Message Content: \(content)")
        
        let components = content.components(separatedBy: "\n")
        var title = ""
        var contentText = ""
        
        for component in components {
            let lowercased = component.lowercased()
            if lowercased.contains("titel:") {
                title = component.replacingOccurrences(of: "(?i)titel:", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                Self.logger.debug("Extrahierter Titel: \(title)")
            } else if lowercased.contains("inhalt:") {
                contentText = component.replacingOccurrences(of: "(?i)inhalt:", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "\"", with: "")
                Self.logger.debug("Extrahierter Inhalt: \(contentText)")
            }
        }
        
        // Wenn kein expliziter Titel/Inhalt gefunden wurde, versuche alternative Formate
        if title.isEmpty || contentText.isEmpty {
            Self.logger.debug("Kein expliziter Titel/Inhalt gefunden, versuche alternatives Format")
            
            // Wenn nur ein Component vorhanden ist, nutze es als Inhalt
            if components.count == 1 {
                contentText = components[0].trimmingCharacters(in: .whitespaces)
                title = "Lernimpuls"
                Self.logger.debug("Einzelne Komponente als Inhalt verwendet")
            } else if components.count > 1 {
                // Erste nicht-leere Zeile als Titel, Rest als Inhalt
                title = components[0].trimmingCharacters(in: .whitespaces)
                contentText = components[1...].joined(separator: "\n").trimmingCharacters(in: .whitespaces)
                Self.logger.debug("Mehrere Komponenten in Titel und Inhalt aufgeteilt")
            }
        }
        
        // Validierung der Ergebnisse
        guard !title.isEmpty, !contentText.isEmpty else {
            Self.logger.error("Konnte keine gültigen Titel/Inhalt extrahieren")
            return nil
        }
        
        Self.logger.info("Erfolgreich extrahiert - Titel: \(title), Inhalt: \(String(contentText.prefix(50)))...")
        return (title: title, content: contentText)
    }
} 