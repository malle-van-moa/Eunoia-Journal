# Rolling Refill-System für Learning Nuggets

## Übersicht

Das Rolling Refill-System ist eine optimierte Strategie zur Verwaltung von Learning Nuggets in der Eunoia Journal App. Es stellt sicher, dass jeder Nutzer nur Nuggets erhält, die er noch nicht gesehen hat, und dass neue Nuggets nur generiert werden, wenn ein Nutzer alle vorhandenen Nuggets verbraucht hat.

## Ziele

- **Individueller Fortschritt**: Kein Nutzer muss auf andere warten.
- **Kosteneffizienz**: Nur wenn ein Nutzer "leerläuft", werden neue Nuggets generiert.
- **Zentrale Datenverwaltung**: Keine Duplikate, kein unnötiger Speicherverbrauch.
- **Optimale Nutzererfahrung**: Immer sofort ein neues Nugget verfügbar.

## Datenmodell

### Firebase Firestore

1. **learning_nuggets** Collection
   - Speichert alle generierten Nuggets für jede Kategorie.
   - Dokumente:
     ```
     {
       "id": "123ABC",  // Eindeutige Nugget-ID
       "category": "Persönliches Wachstum",
       "title": "Titel des Nuggets",
       "content": "Inhalt des Nuggets",
       "created_at": Timestamp
     }
     ```

2. **user_nuggets** Collection
   - Speichert, welche Nuggets ein Nutzer bereits gesehen hat.
   - Dokumente:
     ```
     {
       "user_id": "USER_101",
       "category": "Persönliches Wachstum",
       "seen_nuggets": ["123ABC", "456DEF", "789GHI"],
       "last_updated": Timestamp
     }
     ```

### Swift-Modelle

1. **SharedLearningNugget**
   - Repräsentiert ein Learning Nugget, das von mehreren Nutzern gemeinsam genutzt werden kann.
   - Eigenschaften:
     - `id`: Eindeutige ID des Nuggets
     - `category`: Kategorie des Nuggets
     - `title`: Titel des Nuggets
     - `content`: Inhalt des Nuggets
     - `createdAt`: Erstellungsdatum des Nuggets

2. **UserNuggetRecord**
   - Repräsentiert die Zuordnung zwischen einem Benutzer und den von ihm gesehenen Learning Nuggets.
   - Eigenschaften:
     - `id`: Eindeutige ID des Records
     - `userId`: ID des Benutzers
     - `category`: Kategorie der Nuggets
     - `seenNuggetIds`: IDs der gesehenen Nuggets
     - `lastUpdated`: Datum der letzten Aktualisierung

## Funktionsweise

### Abrufen eines Nuggets

1. Der Nutzer fordert ein Nugget einer bestimmten Kategorie an.
2. Das System prüft, welche Nuggets der Nutzer bereits gesehen hat.
3. Das System sucht nach einem ungenutzten Nugget in der angegebenen Kategorie.
4. Wenn ein ungenutztes Nugget gefunden wird, wird es dem Nutzer angezeigt und als "gesehen" markiert.
5. Wenn kein ungenutztes Nugget gefunden wird, werden neue Nuggets generiert.

### Generieren neuer Nuggets

1. Wenn ein Nutzer alle Nuggets einer Kategorie verbraucht hat, werden neue Nuggets generiert.
2. Die Generierung erfolgt über eine Firebase Cloud Function.
3. Die Cloud Function generiert 25 neue Nuggets für die angegebene Kategorie.
4. Die neuen Nuggets werden in der `learning_nuggets` Collection gespeichert.
5. Der Nutzer erhält eines der neuen Nuggets.

## Implementierung

### SharedLearningNuggetService

Der `SharedLearningNuggetService` ist der zentrale Service für das Rolling Refill-System. Er bietet folgende Funktionen:

- `fetchLearningNugget(for:userId:)`: Ruft ein Learning Nugget für einen Benutzer ab.
- `migrateExistingNuggets()`: Migriert bestehende Learning Nuggets in das neue Schema.
- `initializeDatabase()`: Initialisiert die Datenbank mit Learning Nuggets für alle Kategorien.

### Firebase Cloud Functions

Die Firebase Cloud Functions sind für die Generierung neuer Nuggets zuständig:

- `initializeNuggetsForAllCategories`: Initialisiert die Datenbank mit Learning Nuggets für alle Kategorien.
- `generateNewNuggets`: Generiert neue Nuggets für eine bestimmte Kategorie.

## Vorteile

- **Effizienz**: Nuggets werden nur einmal generiert und von allen Nutzern geteilt.
- **Skalierbarkeit**: Das System skaliert gut mit steigender Nutzerzahl.
- **Kosteneffizienz**: API-Aufrufe werden minimiert, da Nuggets nur bei Bedarf generiert werden.
- **Benutzererfahrung**: Nutzer erhalten immer sofort ein neues Nugget, ohne Wartezeiten.

## Einrichtung

1. **Datenbank initialisieren**:
   - Führe die Cloud Function `initializeNuggetsForAllCategories` aus, um die Datenbank mit initialen Nuggets zu füllen.

2. **Bestehende Nuggets migrieren**:
   - Verwende die Methode `migrateExistingNuggets()` des `SharedLearningNuggetService`, um bestehende Nuggets in das neue Schema zu migrieren.

3. **In der App verwenden**:
   - Verwende die `SharedLearningNuggetView` oder integriere den `SharedLearningNuggetService` in bestehende Views.

## Fehlerbehebung

- **Keine Nuggets verfügbar**: Prüfe, ob die Datenbank initialisiert wurde und ob die Cloud Functions korrekt konfiguriert sind.
- **Fehler bei der Generierung**: Prüfe die API-Keys und die Konfiguration der Cloud Functions.
- **Duplikate**: Prüfe, ob die `markNuggetAsSeen` Methode korrekt funktioniert und ob die `user_nuggets` Collection korrekt aktualisiert wird. 