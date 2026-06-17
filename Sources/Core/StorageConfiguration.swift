import Foundation
import SwiftUI

public enum StorageProviderType: String, Codable, CaseIterable, Identifiable, Sendable {
    case local = "Local Directory"
    case googleDrive = "Google Drive"
    case custom = "Custom Service"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .local: return "macwindow"
        case .googleDrive: return "icloud"
        case .custom: return "network"
        }
    }
}

public enum CustomAuthType: String, Codable, CaseIterable, Identifiable, Sendable {
    case accessToken = "Access Token"
    case apiKey = "API Key + Access Key"
    
    public var id: String { rawValue }
}

@MainActor
public class StorageConfiguration: ObservableObject {
    public static let shared = StorageConfiguration()
    
    @AppStorage("default_local_directory") public var defaultLocalDirectory: String = ""
    @AppStorage("selected_provider") public var selectedProvider: StorageProviderType = .local
    
    @AppStorage("custom_endpoint_url") public var customEndpointURL: String = ""
    @AppStorage("custom_callback_url") public var customCallbackURL: String = ""
    @AppStorage("custom_auth_type") public var customAuthType: CustomAuthType = .accessToken
    
    @Published public var customAPIKey: String = ""
    @Published public var customAPISecret: String = ""
    @Published public var customAccessToken: String = ""
    
    @Published public var googleDriveAccessToken: String = ""
    @Published public var googleDriveRefreshToken: String = ""
    
    private init() {
        loadFromKeychain()
    }
    
    public func loadFromKeychain() {
        do {
            if let key = try KeychainManager.shared.get(key: "customAPIKey") { customAPIKey = key }
            if let secret = try KeychainManager.shared.get(key: "customAPISecret") { customAPISecret = secret }
            if let token = try KeychainManager.shared.get(key: "customAccessToken") { customAccessToken = token }
            
            if let gToken = try KeychainManager.shared.get(key: "googleDriveAccessToken") { googleDriveAccessToken = gToken }
            if let gRefreshToken = try KeychainManager.shared.get(key: "googleDriveRefreshToken") { googleDriveRefreshToken = gRefreshToken }
        } catch {
            print("Failed to load from keychain: \(error)")
        }
    }
    
    public func saveToKeychain() {
        do {
            try KeychainManager.shared.save(key: "customAPIKey", value: customAPIKey)
            try KeychainManager.shared.save(key: "customAPISecret", value: customAPISecret)
            try KeychainManager.shared.save(key: "customAccessToken", value: customAccessToken)
            
            try KeychainManager.shared.save(key: "googleDriveAccessToken", value: googleDriveAccessToken)
            try KeychainManager.shared.save(key: "googleDriveRefreshToken", value: googleDriveRefreshToken)
        } catch {
            print("Failed to save to keychain: \(error)")
        }
    }
}
