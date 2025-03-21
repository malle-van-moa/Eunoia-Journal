import Foundation

enum ServiceError: LocalizedError {
    case userNotAuthenticated
    case invalidResponse
    case networkError
    case databaseError
    case serviceTemporarilyUnavailable
    case apiQuotaExceeded
    case aiServiceUnavailable
    case aiGeneration(String)
    
    var errorDescription: String? {
        switch self {
        case .userNotAuthenticated:
            return "Bitte melde dich an, um fortzufahren."
        case .invalidResponse:
            return "Ungültige Antwort vom Server erhalten."
        case .networkError:
            return "Netzwerkfehler aufgetreten. Bitte überprüfe deine Internetverbindung."
        case .databaseError:
            return "Fehler beim Zugriff auf die Datenbank."
        case .serviceTemporarilyUnavailable:
            return "Dieser Service ist vorübergehend nicht verfügbar. Wir arbeiten an einer Lösung."
        case .apiQuotaExceeded:
            return "Das Kontingent für KI-Generierungen wurde überschritten. Bitte versuche es später erneut."
        case .aiServiceUnavailable:
            return "Der KI-Service ist derzeit nicht verfügbar. Bitte versuche es später erneut."
        case .aiGeneration(let message):
            return "Fehler bei der KI-Generierung: \(message)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .apiQuotaExceeded:
            return "Dein monatliches Kontingent für KI-Generierungen wurde erreicht. Das Kontingent wird am Anfang des nächsten Monats zurückgesetzt."
        case .aiServiceUnavailable:
            return "Der KI-Service ist momentan nicht erreichbar. Du kannst es später erneut versuchen oder die App neu starten."
        case .networkError:
            return "Stelle sicher, dass deine Internetverbindung aktiv ist und versuche es erneut."
        default:
            return nil
        }
    }
} 