import Foundation

enum ServiceError: LocalizedError {
    case userNotAuthenticated
    case invalidResponse
    case networkError
    case databaseError
    case serviceTemporarilyUnavailable
    
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
        }
    }
} 