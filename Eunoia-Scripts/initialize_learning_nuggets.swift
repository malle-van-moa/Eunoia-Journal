import Foundation
import FirebaseCore
import FirebaseFirestore

// MARK: - Hauptfunktion zur Initialisierung der Datenbank

/// Hauptfunktion zur Initialisierung der Datenbank mit Learning Nuggets
@main
struct InitializeLearningNuggets {
    static func main() {
        // Konfiguriere Firebase
        // WICHTIG: Ersetze diese Werte durch deine tatsächlichen Firebase-Konfigurationswerte
        // Diese Werte findest du in der Firebase Console unter Projekteinstellungen > Allgemein > Deine Apps
        let options = FirebaseOptions(
            googleAppID: "1:190076633593:ios:040b87b1ef862c4550bd28",  // Ersetze durch deine App-ID
            gcmSenderID: "190076633593"  // Ersetze durch deine GCM-Sender-ID
        )
        options.apiKey = "AIzaSyAUvwQvxHP0HP57eLjKxi8UVPeO6mPVmik"  // Ersetze durch deinen API-Key
        options.projectID = "eunoia-journal"  // Ersetze durch deine Projekt-ID
        FirebaseApp.configure(options: options)
        
        // Führe die Initialisierung aus
        Task {
            await initializeDatabase()
            exit(0)
        }
        
        // Warte auf die Ausführung der Task
        RunLoop.main.run()
    }
    
    // MARK: - Kategorien und Beispiel-Nuggets
    
    // Kategorien für Learning Nuggets
    static let categories = [
        "Persönliches Wachstum",
        "Beziehungen",
        "Gesundheit",
        "Produktivität",
        "Finanzen",
        "Kreativität",
        "Achtsamkeit",
        "Karriere"
    ]
    
    // Anzahl der Nuggets pro Kategorie
    static let nuggetsPerCategory = 25
    
    // Beispiel-Nuggets für jede Kategorie
    static let exampleNuggets: [String: [(title: String, content: String)]] = [
        "Persönliches Wachstum": [
            (title: "Die Komfortzone verlassen", content: "Persönliches Wachstum findet außerhalb deiner Komfortzone statt. Kleine, tägliche Herausforderungen können langfristig zu großen Veränderungen führen."),
            (title: "Fehler als Lernchance", content: "Fehler sind keine Niederlagen, sondern wertvolle Lernchancen. Wer seine Fehler analysiert und daraus lernt, entwickelt sich schneller weiter als jemand, der Fehler vermeidet."),
            (title: "Gewohnheiten formen dich", content: "Deine täglichen Gewohnheiten formen langfristig deine Identität. Kleine, positive Gewohnheiten haben über die Zeit eine transformative Wirkung auf dein Leben.")
        ],
        "Beziehungen": [
            (title: "Aktives Zuhören", content: "Aktives Zuhören bedeutet, vollständig präsent zu sein, ohne an eine Antwort zu denken. Diese Fähigkeit vertieft Beziehungen mehr als jede andere Kommunikationstechnik."),
            (title: "Dankbarkeit ausdrücken", content: "Regelmäßig Dankbarkeit gegenüber anderen auszudrücken stärkt Beziehungen nachweislich. Es schafft positive Emotionen bei beiden Seiten und fördert Verbundenheit."),
            (title: "Konfliktlösung", content: "In gesunden Beziehungen geht es nicht darum, Konflikte zu vermeiden, sondern sie konstruktiv zu lösen. Der Fokus sollte auf dem Problem, nicht auf der Person liegen.")
        ],
        "Gesundheit": [
            (title: "Bewegung und Gehirn", content: "Regelmäßige körperliche Aktivität erhöht die Produktion von BDNF, einem Protein, das die Bildung neuer Nervenzellen fördert und die kognitive Funktion verbessert."),
            (title: "Schlafqualität", content: "Die Qualität des Schlafs ist wichtiger als die Quantität. Tiefschlafphasen sind entscheidend für die körperliche Erholung, während REM-Schlaf das Gedächtnis und die emotionale Verarbeitung unterstützt."),
            (title: "Mikronährstoffe", content: "Viele Menschen leiden unter einem Mangel an Mikronährstoffen wie Vitamin D, Magnesium und B-Vitaminen, was zu chronischer Müdigkeit und verminderter kognitiver Leistung führen kann.")
        ],
        "Produktivität": [
            (title: "Pareto-Prinzip", content: "Das Pareto-Prinzip besagt, dass 80% der Ergebnisse aus 20% der Anstrengungen resultieren. Identifiziere diese 20% deiner Aktivitäten und fokussiere dich darauf."),
            (title: "Tiefe Arbeit", content: "Tiefe Arbeit – konzentrierte, ungestörte Arbeit an anspruchsvollen Aufgaben – ist in der heutigen ablenkungsreichen Welt eine Superpower und führt zu überragenden Ergebnissen."),
            (title: "Energiemanagement", content: "Produktivität hängt mehr von Energiemanagement als von Zeitmanagement ab. Plane wichtige Aufgaben für Zeiten, in denen deine Energie am höchsten ist.")
        ],
        "Finanzen": [
            (title: "Zinseszins", content: "Der Zinseszinseffekt wird oft als 'achtes Weltwunder' bezeichnet. Eine früh begonnene, regelmäßige Investition von kleinen Beträgen kann durch diesen Effekt zu erstaunlichem Vermögenswachstum führen."),
            (title: "Lifestyle-Inflation", content: "Lifestyle-Inflation – die Tendenz, mehr auszugeben, wenn das Einkommen steigt – ist einer der Hauptgründe, warum Menschen trotz guten Einkommens keine finanzielle Freiheit erreichen."),
            (title: "Notgroschen", content: "Ein Notgroschen von 3-6 Monatsausgaben ist die Grundlage finanzieller Sicherheit und reduziert Stress erheblich. Er ermöglicht bessere finanzielle Entscheidungen ohne Druck.")
        ],
        "Kreativität": [
            (title: "Divergentes Denken", content: "Kreativität erfordert divergentes Denken – die Fähigkeit, viele mögliche Lösungen zu generieren. Diese Fähigkeit kann durch regelmäßige Übungen wie Brainstorming trainiert werden."),
            (title: "Kreative Verbindungen", content: "Die kreativsten Ideen entstehen oft durch ungewöhnliche Verbindungen zwischen scheinbar unzusammenhängenden Konzepten. Vielseitige Interessen fördern diese Art des Denkens."),
            (title: "Kreativitätsroutinen", content: "Die kreativsten Menschen haben oft strenge Routinen. Struktur schafft paradoxerweise den Raum für kreatives Denken, indem sie Entscheidungsmüdigkeit reduziert.")
        ],
        "Achtsamkeit": [
            (title: "Präsenz im Alltag", content: "Achtsamkeit muss keine formelle Meditation sein. Einfach vollständig präsent zu sein bei alltäglichen Aktivitäten wie Essen, Gehen oder Zuhören kann tiefgreifende Auswirkungen haben."),
            (title: "Gedanken beobachten", content: "In der Achtsamkeitspraxis lernt man, Gedanken als vorübergehende mentale Ereignisse zu beobachten, nicht als Realität. Diese Distanzierung reduziert Stress und emotionales Leiden."),
            (title: "Neuroplastizität", content: "Regelmäßige Achtsamkeitspraxis verändert nachweislich die Gehirnstruktur. Sie verstärkt Bereiche, die mit Aufmerksamkeit und emotionaler Regulation verbunden sind.")
        ],
        "Karriere": [
            (title: "T-förmige Fähigkeiten", content: "Menschen mit T-förmigen Fähigkeiten – tiefes Wissen in einem Bereich kombiniert mit breitem Wissen in verwandten Feldern – sind besonders wertvoll in modernen, komplexen Arbeitsumgebungen."),
            (title: "Netzwerkeffekt", content: "Der Wert deines beruflichen Netzwerks wächst exponentiell mit seiner Größe. Jede neue Verbindung multipliziert potenzielle Möglichkeiten durch deren eigenes Netzwerk."),
            (title: "Ikigai", content: "Das japanische Konzept 'Ikigai' beschreibt den süßen Spot, wo sich vier Elemente überschneiden: was du liebst, worin du gut bist, was die Welt braucht und wofür du bezahlt werden kannst.")
        ]
    ]
    
    // MARK: - Datenbankinitialisierung
    
    /// Initialisiert die Datenbank mit Learning Nuggets für alle Kategorien
    static func initializeDatabase() async {
        let db = Firestore.firestore()
        
        print("Initialisiere Datenbank mit Learning Nuggets...")
        
        var totalGenerated = 0
        
        for category in categories {
            print("Prüfe Kategorie: \(category)")
            
            // Prüfe, ob bereits Nuggets für diese Kategorie existieren
            let existingNuggets = try! await db.collection("learning_nuggets")
                .whereField("category", isEqualTo: category)
                .limit(to: 1)
                .getDocuments()
            
            if !existingNuggets.isEmpty {
                print("Kategorie \(category) hat bereits Nuggets, überspringe")
                continue
            }
            
            print("Generiere Nuggets für Kategorie: \(category)")
            
            // Hole Beispiel-Nuggets für diese Kategorie
            let examples = exampleNuggets[category] ?? []
            
            // Erstelle Batch für Firestore-Operationen
            let batch = db.batch()
            
            // Füge Beispiel-Nuggets hinzu
            for example in examples {
                let docRef = db.collection("learning_nuggets").document()
                batch.setData([
                    "id": docRef.documentID,
                    "category": category,
                    "title": example.title,
                    "content": example.content,
                    "created_at": FieldValue.serverTimestamp()
                ], forDocument: docRef)
                
                totalGenerated += 1
            }
            
            // Fülle mit generischen Nuggets auf, bis nuggetsPerCategory erreicht ist
            for i in examples.count..<nuggetsPerCategory {
                let docRef = db.collection("learning_nuggets").document()
                batch.setData([
                    "id": docRef.documentID,
                    "category": category,
                    "title": "Nugget \(i+1) für \(category)",
                    "content": "Dies ist ein generiertes Nugget für die Kategorie \(category). Es enthält wertvolle Informationen und Erkenntnisse zu diesem Thema.",
                    "created_at": FieldValue.serverTimestamp()
                ], forDocument: docRef)
                
                totalGenerated += 1
            }
            
            // Commit Batch
            try! await batch.commit()
            
            print("Erfolgreich \(nuggetsPerCategory) Nuggets für Kategorie \(category) generiert")
        }
        
        print("Initialisierung abgeschlossen: \(totalGenerated) Nuggets generiert")
    }
} 