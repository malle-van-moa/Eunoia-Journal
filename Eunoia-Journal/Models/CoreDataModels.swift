// Notwendige Importe für Core Data
import Foundation
import CoreData

// Extension für VisionBoardEntity zum Zugriff auf ValueCompass
extension VisionBoardEntity {
    // Setter und Getter für ValueCompass
    var valueCompass: ValueCompass? {
        get {
            guard let data = valueCompassData else { return nil }
            do {
                return try JSONDecoder().decode(ValueCompass.self, from: data)
            } catch {
                print("Fehler beim Dekodieren des ValueCompass: \(error)")
                return nil
            }
        }
        set {
            if let newValue = newValue {
                do {
                    valueCompassData = try JSONEncoder().encode(newValue)
                } catch {
                    print("Fehler beim Kodieren des ValueCompass: \(error)")
                    valueCompassData = nil
                }
            } else {
                valueCompassData = nil
            }
        }
    }
} 