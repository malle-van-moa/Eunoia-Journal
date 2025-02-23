import Foundation
import CoreLocation
import OSLog

class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()
    private let manager = CLLocationManager()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Eunoia", category: "LocationManager")
    
    @Published var location: CLLocation?
    @Published var locationString: String?
    @Published var authorizationStatus: CLAuthorizationStatus?
    @Published var lastError: LocationError?
    
    private let geocoder = CLGeocoder()
    private var isUpdatingLocation = false
    
    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        authorizationStatus = manager.authorizationStatus
    }
    
    func requestAuthorization() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }
    
    func startUpdatingLocation() {
        guard !isUpdatingLocation else { return }
        
        // Setze einen Timer für die maximale Wartezeit
        let timeoutTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
            self?.handleTimeout()
        }
        
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            isUpdatingLocation = true
            manager.startUpdatingLocation()
        case .denied, .restricted:
            timeoutTimer.invalidate()
            lastError = .authorizationDenied
        case .notDetermined:
            timeoutTimer.invalidate()
            requestAuthorization()
        @unknown default:
            timeoutTimer.invalidate()
            lastError = .unknown
        }
    }
    
    private func handleTimeout() {
        stopUpdatingLocation()
        lastError = .timeout
    }
    
    func stopUpdatingLocation() {
        isUpdatingLocation = false
        manager.stopUpdatingLocation()
    }
    
    func getCurrentLocationString() async throws -> String {
        // Prüfe zuerst die Berechtigung
        guard manager.authorizationStatus == .authorizedWhenInUse || 
              manager.authorizationStatus == .authorizedAlways else {
            requestAuthorization()
            throw LocationError.authorizationDenied
        }
        
        // Starte Location Updates, falls noch nicht aktiv
        if !isUpdatingLocation {
            startUpdatingLocation()
        }
        
        // Implementiere eine graduelle Timeout-Strategie
        let timeoutIntervals = [3.0, 5.0, 7.0, 10.0] // Zunehmende Timeout-Intervalle
        
        for (attempt, timeout) in timeoutIntervals.enumerated() {
            let startTime = Date()
            
            // Warte auf Location mit exponentieller Verzögerung
            while location == nil {
                if Date().timeIntervalSince(startTime) > timeout {
                    if attempt == timeoutIntervals.count - 1 {
                        throw LocationError.timeout
                    }
                    break
                }
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 Sekunden Wartezeit
            }
            
            if let location = location {
                do {
                    let placemarks = try await geocoder.reverseGeocodeLocation(location)
                    guard let placemark = placemarks.first else {
                        if attempt == timeoutIntervals.count - 1 {
                            throw LocationError.geocodingFailed
                        }
                        continue
                    }
                    
                    let components = [
                        placemark.locality,
                        placemark.administrativeArea,
                        placemark.country
                    ].compactMap { $0 }
                    
                    guard !components.isEmpty else {
                        if attempt == timeoutIntervals.count - 1 {
                            throw LocationError.invalidLocationData
                        }
                        continue
                    }
                    
                    return components.joined(separator: ", ")
                } catch {
                    if attempt == timeoutIntervals.count - 1 {
                        throw error
                    }
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 1_000_000_000))
                    continue
                }
            }
        }
        
        throw LocationError.locationNotAvailable
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else { return }
        
        // Prüfe auf Alter und Genauigkeit der Location
        let locationAge = -newLocation.timestamp.timeIntervalSinceNow
        guard locationAge < 10 else { return } // Ignoriere Locations älter als 10 Sekunden
        
        guard newLocation.horizontalAccuracy >= 0 else { return }
        guard newLocation.horizontalAccuracy < 100 else { return } // Ignoriere ungenaue Locations
        
        // Setze die Location nur, wenn sie sich signifikant geändert hat
        if let currentLocation = location {
            let distance = newLocation.distance(from: currentLocation)
            guard distance > 10 else { return } // Mindestens 10 Meter Unterschied
        }
        
        location = newLocation
        lastError = nil
        
        // Stoppe die Updates, wenn wir eine gute Location haben
        if newLocation.horizontalAccuracy <= 65 { // Gute Genauigkeit
            stopUpdatingLocation()
        }
        
        Task {
            do {
                locationString = try await getCurrentLocationString()
            } catch {
                lastError = error as? LocationError ?? .unknown
                logger.error("Fehler beim Geocoding: \(error.localizedDescription)")
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
        
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            if !isUpdatingLocation {
                startUpdatingLocation()
            }
        case .denied, .restricted:
            stopUpdatingLocation()
            lastError = .authorizationDenied
        case .notDetermined:
            break
        @unknown default:
            lastError = .unknown
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                lastError = .authorizationDenied
                stopUpdatingLocation()
            case .network:
                // Bei Netzwerkfehlern warten wir kurz und versuchen es erneut
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 Sekunden warten
                    if isUpdatingLocation {
                        startUpdatingLocation() // Neustart
                    }
                }
                lastError = .networkError
            case .locationUnknown:
                lastError = .locationNotAvailable
            default:
                lastError = .unknown
            }
        } else {
            lastError = .unknown
        }
        logger.error("Standortfehler: \(error.localizedDescription)")
    }
}

enum LocationError: Error, LocalizedError {
    case locationNotAvailable
    case geocodingFailed
    case authorizationDenied
    case networkError
    case geocodingCancelled
    case invalidLocationData
    case unknown
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .locationNotAvailable:
            return "Standort ist derzeit nicht verfügbar"
        case .geocodingFailed:
            return "Adresse konnte nicht ermittelt werden"
        case .authorizationDenied:
            return "Keine Berechtigung für Standortzugriff"
        case .networkError:
            return "Netzwerkfehler beim Abrufen des Standorts"
        case .geocodingCancelled:
            return "Adressermittlung wurde abgebrochen"
        case .invalidLocationData:
            return "Ungültige Standortdaten"
        case .unknown:
            return "Unbekannter Standortfehler"
        case .timeout:
            return "Zeitüberschreitung beim Abrufen des Standorts"
        }
    }
} 