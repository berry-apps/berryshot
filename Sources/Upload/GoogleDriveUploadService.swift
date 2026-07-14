import Foundation

public final class GoogleDriveUploadService: UploadServiceProtocol, Sendable {
    public init() {}
    
    public func uploadImage(fileURL: URL) async throws -> URL {
        let config = await StorageConfiguration.shared
        let accessToken = await config.googleDriveAccessToken
        
        guard !accessToken.isEmpty else {
            throw NSError(domain: "GoogleDriveUpload", code: 401, userInfo: [NSLocalizedDescriptionKey: "Google Drive access token is missing"])
        }
        
        let fileData = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent
        let mimeType = "image/png"
        
        let url = URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let metadata: [String: Any] = ["name": filename]
        
        guard let metadataData = try? JSONSerialization.data(withJSONObject: metadata, options: []) else {
            throw NSError(domain: "GoogleDriveUpload", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to serialize metadata"])
        }
        
        var body = Data()
        let lineBreak = "\r\n"
        
        body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\(lineBreak)\(lineBreak)".data(using: .utf8)!)
        body.append(metadataData)
        body.append(lineBreak.data(using: .utf8)!)
        
        body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\(lineBreak)\(lineBreak)".data(using: .utf8)!)
        body.append(fileData)
        body.append(lineBreak.data(using: .utf8)!)
        
        body.append("--\(boundary)--\(lineBreak)".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            var errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let errorObj = json["error"] as? [String: Any],
               let message = errorObj["message"] as? String {
                errorMessage = message
            }
            
            if httpResponse.statusCode == 401 {
                errorMessage = "Invalid or expired Access Token. Please update your Google Drive token in Settings.\n\nDetails: \(errorMessage)"
            }
            
            throw NSError(domain: "GoogleDriveUpload", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Upload failed: \(errorMessage)"])
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let fileId = json["id"] as? String else {
            throw NSError(domain: "GoogleDriveUpload", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid response from Google Drive"])
        }
        
        return URL(string: "https://drive.google.com/file/d/\(fileId)/view")!
    }
}
