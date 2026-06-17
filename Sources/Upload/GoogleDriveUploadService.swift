import Foundation

public final class GoogleDriveUploadService: UploadServiceProtocol, Sendable {
    public init() {}
    
    public func uploadImage(fileURL: URL) async throws -> URL {
        let config = await StorageConfiguration.shared
        let accessToken = await config.googleDriveAccessToken
        
        guard !accessToken.isEmpty else {
            throw NSError(domain: "GoogleDriveUpload", code: 401, userInfo: [NSLocalizedDescriptionKey: "Google Drive access token is missing"])
        }
        
        // Mocking Google Drive upload
        print("Uploading to Google Drive using token: \(accessToken)")
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        return URL(string: "https://drive.google.com/file/d/mock-file-id/view")!
    }
}
