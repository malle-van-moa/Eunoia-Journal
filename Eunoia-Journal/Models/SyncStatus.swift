import Foundation

enum SyncStatus: String, Codable {
    case synced
    case pendingUpload
    case pendingUpdate
    case pendingDelete
} 