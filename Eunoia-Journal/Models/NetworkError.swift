import Foundation

enum NetworkError: Error {
    case noConnection
    case timeout
    case serverError
    
    var localizedDescription: String {
        switch self {
        case .noConnection:
            return "Keine Internetverbindung verfügbar. Die App arbeitet im Offline-Modus."
        case .timeout:
            return "Zeitüberschreitung bei der Serveranfrage. Bitte versuche es später erneut."
        case .serverError:
            return "Ein Serverfehler ist aufgetreten. Bitte versuche es später erneut."
        }
    }
} 