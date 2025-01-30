import Foundation
import Network
import Combine

class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    @Published var isConnected = false
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        startMonitoring()
    }
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let wasConnected = self?.isConnected ?? false
                self?.isConnected = path.status == .satisfied
                
                // If connection was restored, trigger sync
                if !wasConnected && self?.isConnected == true {
                    Task {
                        await FirebaseService.shared.syncUnsyncedData()
                    }
                }
            }
        }
        
        monitor.start(queue: queue)
    }
    
    func stopMonitoring() {
        monitor.cancel()
    }
} 