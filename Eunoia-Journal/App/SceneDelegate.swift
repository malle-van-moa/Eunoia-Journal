import UIKit
import CoreData

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Core Data Stack initialisieren und Reparatur durchführen
        do {
            try CoreDataManager.shared.performFullRepair()
        } catch {
            print("❌ Core Data Reparatur fehlgeschlagen: \(error.localizedDescription)")
            
            // Versuche einen Reset als letzte Option
            do {
                try CoreDataManager.shared.resetStore()
            } catch {
                print("❌ Core Data Reset fehlgeschlagen: \(error.localizedDescription)")
            }
        }
        
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
        window = UIWindow(windowScene: windowScene)
        // Hier folgt Ihre normale Window-Setup-Logik
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Optional: Aufräumen wenn die Scene disconnected wird
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Optional: Aktionen wenn die Scene aktiv wird
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Optional: Aktionen wenn die Scene inaktiv wird
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Optional: Aktionen wenn die Scene in den Vordergrund kommt
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Speichere Änderungen beim Übergang in den Hintergrund
        do {
            try CoreDataManager.shared.saveContext()
        } catch {
            print("❌ Fehler beim Speichern des Contexts: \(error.localizedDescription)")
        }
    }
} 