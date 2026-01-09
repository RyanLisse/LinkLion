import Foundation
import Security

/// Secure credential storage using macOS Keychain
public struct CredentialStore: Sendable {
    private static let serviceName = "com.linkedinkit.credentials"
    private static let cookieKey = "li_at_cookie"
    
    public init() {}
    
    /// Save the LinkedIn cookie to Keychain
    public func saveCookie(_ cookie: String) throws {
        // Clean up the cookie value
        let cleanCookie = cookie.hasPrefix("li_at=") ? String(cookie.dropFirst(6)) : cookie
        
        // Delete any existing item first
        try? deleteCookie()
        
        guard let data = cleanCookie.data(using: .utf8) else {
            throw CredentialError.invalidData
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: Self.cookieKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw CredentialError.keychainError(status)
        }
    }
    
    /// Load the LinkedIn cookie from Keychain
    public func loadCookie() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: Self.cookieKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            return nil
        }
        
        guard status == errSecSuccess else {
            throw CredentialError.keychainError(status)
        }
        
        guard let data = result as? Data,
              let cookie = String(data: data, encoding: .utf8) else {
            throw CredentialError.invalidData
        }
        
        return cookie
    }
    
    /// Delete the LinkedIn cookie from Keychain
    public func deleteCookie() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: Self.cookieKey,
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status != errSecSuccess && status != errSecItemNotFound {
            throw CredentialError.keychainError(status)
        }
    }
    
    /// Check if a cookie is stored
    public func hasCookie() -> Bool {
        do {
            return try loadCookie() != nil
        } catch {
            return false
        }
    }
}

public enum CredentialError: Error, LocalizedError {
    case invalidData
    case keychainError(OSStatus)
    case notFound
    
    public var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Invalid credential data"
        case .keychainError(let status):
            return "Keychain error: \(status)"
        case .notFound:
            return "Credential not found"
        }
    }
}
