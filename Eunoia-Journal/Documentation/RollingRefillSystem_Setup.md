# Einrichtung und Verwendung des Rolling Refill-Systems

Diese Anleitung beschreibt die Schritte zur Einrichtung und Verwendung des Rolling Refill-Systems für Learning Nuggets in der Eunoia Journal App.

## Inhaltsverzeichnis

1. [Voraussetzungen](#voraussetzungen)
2. [Firebase-Konfiguration](#firebase-konfiguration)
3. [Initialisierung der Datenbank](#initialisierung-der-datenbank)
4. [Migration bestehender Nuggets](#migration-bestehender-nuggets)
5. [Deployment der Cloud Functions](#deployment-der-cloud-functions)
6. [Integration in die App](#integration-in-die-app)
7. [Testen des Systems](#testen-des-systems)
8. [Fehlerbehebung](#fehlerbehebung)

## Voraussetzungen

Bevor Sie mit der Einrichtung beginnen, stellen Sie sicher, dass folgende Voraussetzungen erfüllt sind:

- Firebase-Projekt ist eingerichtet
- Firebase CLI ist installiert
- Node.js und npm sind installiert
- Xcode und Swift-Entwicklungsumgebung sind eingerichtet
- API-Schlüssel für OpenAI und/oder DeepSeek sind vorhanden

## Firebase-Konfiguration

1. **Firestore-Datenbank einrichten**

   Stellen Sie sicher, dass Firestore in Ihrem Firebase-Projekt aktiviert ist. Erstellen Sie die folgenden Collections:

   - `learning_nuggets`: Speichert die geteilten Learning Nuggets
   - `user_nuggets`: Speichert die Benutzer-Nugget-Zuordnungen

2. **Sicherheitsregeln konfigurieren**

   Fügen Sie die folgenden Sicherheitsregeln zu Ihrer Firestore-Datenbank hinzu:

   ```
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       // Learning Nuggets können von allen authentifizierten Benutzern gelesen werden
       match /learning_nuggets/{nuggetId} {
         allow read: if request.auth != null;
         allow write: if false; // Nur über Cloud Functions schreibbar
       }
       
       // Benutzer-Nugget-Zuordnungen können nur vom jeweiligen Benutzer gelesen und geschrieben werden
       match /user_nuggets/{recordId} {
         allow read: if request.auth != null && request.auth.uid == resource.data.user_id;
         allow create: if request.auth != null && request.auth.uid == request.resource.data.user_id;
         allow update: if request.auth != null && request.auth.uid == resource.data.user_id;
         allow delete: if false;
       }
     }
   }
   ```

3. **API-Schlüssel konfigurieren**

   Konfigurieren Sie die API-Schlüssel für die Cloud Functions:

   ```bash
   firebase functions:config:set openai.apikey="YOUR_OPENAI_API_KEY"
   firebase functions:config:set deepseek.apikey="YOUR_DEEPSEEK_API_KEY"
   ```

## Initialisierung der Datenbank

1. **Skript ausführen**

   Führen Sie das Initialisierungsskript aus, um die Datenbank mit initialen Learning Nuggets zu füllen:

   ```bash
   cd Eunoia-Journal/Scripts
   swift initialize_learning_nuggets.swift
   ```

   Alternativ können Sie die Initialisierung auch über die `RollingRefillTestView` in der App durchführen.

2. **Kategorien prüfen**

   Überprüfen Sie in der Firebase Console, ob die Learning Nuggets für alle Kategorien erstellt wurden.

## Migration bestehender Nuggets

Wenn Sie bereits Learning Nuggets in Ihrer App haben, können Sie diese in das neue Schema migrieren:

1. **Migrationsskript ausführen**

   ```bash
   cd Eunoia-Journal/Scripts
   swift migrate_learning_nuggets.swift
   ```

2. **Migration in der App**

   Alternativ können Sie die Migration auch über den `SharedLearningNuggetService` in der App durchführen:

   ```swift
   Task {
       do {
           let migratedCount = try await SharedLearningNuggetService.shared.migrateExistingNuggets()
           print("Migration abgeschlossen: \(migratedCount) Nuggets migriert")
       } catch {
           print("Fehler bei der Migration: \(error.localizedDescription)")
       }
   }
   ```

## Deployment der Cloud Functions

1. **Cloud Functions deployen**

   ```bash
   cd Eunoia-Journal/CloudFunctions
   firebase deploy --only functions
   ```

2. **Funktionen überprüfen**

   Überprüfen Sie in der Firebase Console, ob die Cloud Functions erfolgreich deployt wurden:

   - `generateLearningNuggets`: Callable Function zum manuellen Generieren von Nuggets
   - `scheduledNuggetRefill`: Scheduled Function zum automatischen Auffüllen von Nuggets

## Integration in die App

1. **SharedLearningNuggetService verwenden**

   Verwenden Sie den `SharedLearningNuggetService`, um Learning Nuggets abzurufen:

   ```swift
   let service = SharedLearningNuggetService.shared
   
   // Learning Nugget abrufen
   Task {
       do {
           let nugget = try await service.fetchLearningNugget(for: .personalGrowth, userId: currentUserId)
           // Nugget anzeigen
       } catch {
           // Fehler behandeln
       }
   }
   
   // Nugget als zum Journal hinzugefügt markieren
   Task {
       do {
           try await service.markNuggetAddedToJournal(nuggetId: nuggetId, for: currentUserId)
       } catch {
           // Fehler behandeln
       }
   }
   ```

2. **RollingRefillTestView integrieren**

   Fügen Sie die `RollingRefillTestView` zu Ihrer App hinzu, um das System zu testen:

   ```swift
   NavigationLink(destination: RollingRefillTestView()) {
       Text("Rolling Refill System testen")
   }
   ```

## Testen des Systems

1. **Testansicht verwenden**

   Verwenden Sie die `RollingRefillTestView`, um das System zu testen:

   - Wählen Sie eine Kategorie aus
   - Rufen Sie ein Learning Nugget ab
   - Fügen Sie das Nugget zum Journal hinzu
   - Zeigen Sie die Statistik an

2. **Cloud Functions testen**

   Testen Sie die Cloud Function zum Generieren neuer Nuggets:

   ```swift
   let functions = Functions.functions()
   
   let data: [String: Any] = [
       "category": "Persönliches Wachstum",
       "count": 5,
       "model": "openai"
   ]
   
   functions.httpsCallable("generateLearningNuggets").call(data) { result, error in
       if let error = error {
           print("Fehler: \(error.localizedDescription)")
           return
       }
       
       if let data = result?.data as? [String: Any], let count = data["count"] as? Int {
           print("\(count) Nuggets generiert")
       }
   }
   ```

## Fehlerbehebung

### Keine Nuggets verfügbar

Wenn keine Nuggets verfügbar sind, überprüfen Sie:

1. Ob die Datenbank initialisiert wurde
2. Ob der Benutzer bereits alle verfügbaren Nuggets gesehen hat
3. Ob die Cloud Function zum Generieren neuer Nuggets funktioniert

### Fehler bei der Generierung von Nuggets

Wenn Fehler bei der Generierung von Nuggets auftreten, überprüfen Sie:

1. Ob die API-Schlüssel korrekt konfiguriert sind
2. Die Logs der Cloud Functions in der Firebase Console
3. Ob das gewählte KI-Modell verfügbar ist

### Probleme mit der Migration

Wenn Probleme bei der Migration bestehender Nuggets auftreten, überprüfen Sie:

1. Das Format der bestehenden Nuggets
2. Die Logs des Migrationsskripts
3. Ob die Firestore-Sicherheitsregeln die Migration zulassen

### Allgemeine Fehler

Bei allgemeinen Fehlern:

1. Überprüfen Sie die Logs in der Firebase Console
2. Überprüfen Sie die Logs in der Xcode-Konsole
3. Stellen Sie sicher, dass der Benutzer authentifiziert ist
4. Überprüfen Sie die Netzwerkverbindung 