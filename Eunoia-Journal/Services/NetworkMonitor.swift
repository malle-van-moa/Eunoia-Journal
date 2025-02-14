import Foundation
import Network
import Combine

enum NetworkError: Error {
    case noConnection
    
    var localizedDescription: String {
        switch self {
        case .noConnection:
            return "Keine Internetverbindung verfügbar. Bitte überprüfe deine Verbindung und versuche es erneut."
        }
    }
}

class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    @Published private(set) var isConnected = true
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        monitor = NWPathMonitor()
        setupMonitor()
    }
    
    private func setupMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
            }
        }
    }
    
    func startMonitoring() {
        monitor.start(queue: queue)
    }
    
    func stopMonitoring() {
        monitor.cancel()
    }
    
    deinit {
        stopMonitoring()
    }
} 