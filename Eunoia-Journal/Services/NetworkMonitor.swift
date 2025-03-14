import Foundation
import Network
import Combine

class NetworkMonitor: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var connectionType: NWInterface.InterfaceType?
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    private var completionHandler: ((Bool) -> Void)?
    
    static let shared = NetworkMonitor()
    
    private init() {}
    
    func startMonitoring(completion: ((Bool) -> Void)? = nil) {
        completionHandler = completion
        
        // Stoppe vorherige Überwachung, um sicherzustellen, dass keine doppelten Verbindungen bestehen
        stopMonitoring()
        
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isConnected = path.status == .satisfied
                self.connectionType = self.getConnectionType(path: path)
                self.completionHandler?(self.isConnected)
            }
            
            #if DEBUG
            self.logNetworkStatus(path: path)
            #endif
        }
        
        monitor.start(queue: queue)
    }
    
    func stopMonitoring() {
        monitor.cancel()
        completionHandler = nil
    }
    
    var isNetworkAvailable: Bool {
        return isConnected
    }
    
    var networkType: String {
        guard let type = connectionType else {
            return isConnected ? "Unknown" : "No Connection"
        }
        
        switch type {
        case .cellular:
            return "Cellular"
        case .wifi:
            return "WiFi"
        case .wiredEthernet:
            return "Ethernet"
        case .loopback:
            return "Loopback"
        default:
            return "Other"
        }
    }
    
    private func getConnectionType(path: NWPath) -> NWInterface.InterfaceType? {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .wiredEthernet
        } else if path.usesInterfaceType(.loopback) {
            return .loopback
        }
        
        return nil
    }
    
    #if DEBUG
    private func logNetworkStatus(path: NWPath) {
        print("Network Status: \(path.status)")
        print("Network Type: \(networkType)")
        print("Is Expensive: \(path.isExpensive)")
        print("Interfaces: \(path.availableInterfaces.map { $0.name })")
    }
    #endif
    
    // Hilfsmethode, um zu prüfen, ob eine Netzwerkverbindung sicher hergestellt werden kann
    func ensureNetworkConnection() -> Bool {
        return isNetworkAvailable
    }
    
    // Hilfsmethode, um auf eine Netzwerkverbindung zu warten
    func waitForConnection(timeout: TimeInterval = 30.0) -> AnyPublisher<Bool, Never> {
        // Wenn bereits verbunden, sofort true zurückgeben
        if isNetworkAvailable {
            return Just(true).eraseToAnyPublisher()
        }
        
        // Auf Verbindung warten mit Timeout
        return $isConnected
            .filter { $0 }
            .first()
            .timeout(.seconds(timeout), scheduler: RunLoop.main)
            .replaceError(with: false)
            .eraseToAnyPublisher()
    }
} 