import Foundation
import Network
import Combine

class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    @Published private(set) var isConnected = true
    private var connectionType: NWInterface.InterfaceType?
    private var completionHandler: ((Bool) -> Void)?
    
    private init() {
        startMonitoring()
    }
    
    func startMonitoring(completion: ((Bool) -> Void)? = nil) {
        completionHandler = completion
        
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isConnected = path.status == .satisfied
            self?.connectionType = self?.checkConnectionType(path: path)
            
            if let completionHandler = self?.completionHandler {
                DispatchQueue.main.async {
                    completionHandler(path.status == .satisfied)
                }
            }
            
            #if DEBUG
            self?.logNetworkStatus(path: path)
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
            return "Unknown"
        }
    }
    
    private func checkConnectionType(path: NWPath) -> NWInterface.InterfaceType? {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .wiredEthernet
        } else {
            return nil
        }
    }
    
    #if DEBUG
    private func logNetworkStatus(path: NWPath) {
        print("Network Status Changed:")
        print("Connected: \(isConnected)")
        print("Connection Type: \(networkType)")
        print("Interface Types: \(path.availableInterfaces.map { $0.type })")
        print("Path Status: \(path.status)")
    }
    #endif
} 