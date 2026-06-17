import Foundation
import Security

public final class KeychainHelper: Sendable {
    public static let shared = KeychainHelper()
    
    private init() {}
    
    public func save(key: String, data: Data) -> OSStatus {
        UserDefaults.standard.set(data, forKey: key)
        return errSecSuccess
    }
    
    public func read(key: String) -> Data? {
        return UserDefaults.standard.data(forKey: key)
    }
    
    public func delete(key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
