import Foundation
import Security

enum APIKeys {
    // MARK: - API Keys
    private static let openAIKeyIdentifier = "com.eunoia.openai.apikey"
    private static let deepSeekKeyIdentifier = "com.eunoia.deepseek.apikey"
    
    // MARK: - Keychain Access
    
    /// Speichert einen API-Key sicher im Keychain
    /// - Parameters:
    ///   - key: Der zu speichernde API-Key
    ///   - identifier: Der eindeutige Identifier für den Key
    /// - Returns: True, wenn das Speichern erfolgreich war
    static func saveAPIKey(_ key: String, forIdentifier identifier: String) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: identifier,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        // Lösche vorhandenen Key, falls vorhanden
        SecItemDelete(query as CFDictionary)
        
        // Speichere neuen Key
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    /// Lädt einen API-Key aus dem Keychain
    /// - Parameter identifier: Der eindeutige Identifier für den Key
    /// - Returns: Der API-Key oder nil, wenn nicht gefunden
    static func loadAPIKey(forIdentifier identifier: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: identifier,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let data = dataTypeRef as? Data, let key = String(data: data, encoding: .utf8) {
            return key
        } else {
            return nil
        }
    }
    
    /// Löscht einen API-Key aus dem Keychain
    /// - Parameter identifier: Der eindeutige Identifier für den Key
    /// - Returns: True, wenn das Löschen erfolgreich war
    static func deleteAPIKey(forIdentifier identifier: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: identifier
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess
    }
    
    // MARK: - API Key Access
    
    /// Gibt den OpenAI API-Key zurück
    /// - Returns: Der OpenAI API-Key oder ein Fallback-Wert, wenn nicht im Keychain gefunden
    static var openAIKey: String {
        if let key = loadAPIKey(forIdentifier: openAIKeyIdentifier) {
            return key
        } else {
            // Fallback für Entwicklung - NICHT für Produktion verwenden!
            let fallbackKey = "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"
            _ = saveAPIKey(fallbackKey, forIdentifier: openAIKeyIdentifier)
            return fallbackKey
        }
    }
    
    /// Gibt den DeepSeek API-Key zurück
    /// - Returns: Der DeepSeek API-Key oder ein Fallback-Wert, wenn nicht im Keychain gefunden
    static var deepSeekKey: String {
        if let key = loadAPIKey(forIdentifier: deepSeekKeyIdentifier) {
            return key
        } else {
            // Fallback für Entwicklung - NICHT für Produktion verwenden!
            // DeepSeek erwartet möglicherweise ein anderes Format für den API-Key
            // Hier wird "Bearer " vorangestellt, falls es erforderlich ist
            let fallbackKey = "Bearer sk-80532930325549a5afa7acb570582148"
            _ = saveAPIKey(fallbackKey, forIdentifier: deepSeekKeyIdentifier)
            return fallbackKey
        }
    }
    
    /// Speichert den OpenAI API-Key im Keychain
    /// - Parameter key: Der zu speichernde API-Key
    /// - Returns: True, wenn das Speichern erfolgreich war
    static func saveOpenAIKey(_ key: String) -> Bool {
        return saveAPIKey(key, forIdentifier: openAIKeyIdentifier)
    }
    
    /// Speichert den DeepSeek API-Key im Keychain
    /// - Parameter key: Der zu speichernde API-Key
    /// - Returns: True, wenn das Speichern erfolgreich war
    static func saveDeepSeekKey(_ key: String) -> Bool {
        return saveAPIKey(key, forIdentifier: deepSeekKeyIdentifier)
    }
} 