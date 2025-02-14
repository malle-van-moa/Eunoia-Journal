import Foundation
import CoreLocation

class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()
    private let manager = CLLocationManager()
    
    @Published var location: CLLocation?
    @Published var locationString: String?
    @Published var authorizationStatus: CLAuthorizationStatus?
    
    private let geocoder = CLGeocoder()
    
    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
    }
    
    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }
    
    func startUpdatingLocation() {
        manager.startUpdatingLocation()
    }
    
    func stopUpdatingLocation() {
        manager.stopUpdatingLocation()
    }
    
    func getCurrentLocationString() async throws -> String {
        guard let location = location else {
            throw LocationError.locationNotAvailable
        }
        
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else {
                throw LocationError.geocodingFailed
            }
            
            let locationString = [
                placemark.locality,
                placemark.administrativeArea,
                placemark.country
            ].compactMap { $0 }.joined(separator: ", ")
            
            return locationString
        } catch {
            throw LocationError.geocodingFailed
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
        
        Task {
            do {
                locationString = try await getCurrentLocationString()
            } catch {
                print("Fehler beim Geocoding: \(error)")
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
        
        if status == .authorizedWhenInUse {
            startUpdatingLocation()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Standortfehler: \(error)")
    }
}

enum LocationError: Error {
    case locationNotAvailable
    case geocodingFailed
} 