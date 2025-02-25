# Eunoia Journal

Eunoia Journal ist eine moderne iOS-Journaling-App, die das neue Journal-Framework von iOS 17 nutzt. Die App bietet eine intuitive Benutzeroberfläche für tägliche Journaling-Aktivitäten und unterstützt verschiedene Funktionen zur Selbstreflexion und persönlichen Entwicklung.

## Features

- **iOS 17 Journal Integration**: Nahtlose Integration mit dem nativen iOS Journal-Framework
- **Google Sign-In**: Sichere Authentifizierung über Google-Konto
- **Core Data**: Lokale Datenpersistenz mit vollständiger Offline-Unterstützung
- **Vision Board**: Persönliche Zielvisualisierung und Tracking
- **Mehrsprachig**: Unterstützung für Deutsch und Englisch

## Technische Voraussetzungen

- iOS 17.0 oder höher
- Xcode 15.0 oder höher
- CocoaPods als Dependency Manager
- Gültiges Apple Developer Konto für Journal-Framework-Berechtigungen

## Installation

1. Repository klonen:
```bash
git clone https://github.com/malle-van-moa/Eunoia-Journal.git
```

2. In das Projektverzeichnis wechseln:
```bash
cd Eunoia-Journal
```

3. Dependencies installieren:
```bash
pod install
```

4. Öffnen Sie `Eunoia-Journal.xcworkspace` in Xcode

## Konfiguration

1. Stellen Sie sicher, dass Ihre Apple Developer Account-Berechtigungen das Journal-Framework einschließen
2. Überprüfen Sie die Entitlements-Einstellungen in Xcode
3. Konfigurieren Sie die Google Sign-In Credentials in der Firebase Console

## Architektur

- **MVVM**: Model-View-ViewModel Architektur
- **SwiftUI**: Moderne deklarative UI
- **Combine**: Reaktive Programmierung für Datenflüsse
- **Core Data**: Lokale Datenpersistenz
- **Firebase**: Backend-Services und Authentifizierung

## Lizenz

Copyright © 2024 Eunoia Journal. Alle Rechte vorbehalten. 