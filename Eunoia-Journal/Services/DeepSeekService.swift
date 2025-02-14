import Foundation

class DeepSeekService {
    static let shared = DeepSeekService()
    
    private init() {}
    
    func generateResponse(systemPrompt: String, userPrompt: String) async throws -> String {
        throw ServiceError.serviceTemporarilyUnavailable
    }
} 
