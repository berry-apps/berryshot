import Foundation

public final class CustomUploadService: UploadServiceProtocol, Sendable {
    public init() {}
    
    public func uploadImage(fileURL: URL) async throws -> URL {
        let config = await StorageConfiguration.shared
        let endpoint = await config.customEndpointURL
        let authType = await config.customAuthType
        
        guard !endpoint.isEmpty, let targetURL = URL(string: endpoint) else {
            throw NSError(domain: "CustomUpload", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid custom endpoint URL"])
        }
        
        var request = URLRequest(url: targetURL)
        request.httpMethod = "POST"
        
        if authType == .accessToken {
            let accessToken = await config.customAccessToken
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        } else {
            let apiKey = await config.customAPIKey
            let apiSecret = await config.customAPISecret
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
            request.setValue(apiSecret, forHTTPHeaderField: "X-API-Secret")
        }
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        let filename = fileURL.lastPathComponent
        let mimeType = "image/png"
        let fileData = try Data(contentsOf: fileURL)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "CustomUpload", code: status, userInfo: [NSLocalizedDescriptionKey: "Server returned error code \(status)"])
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let callback = await config.customCallbackURL
            if !callback.isEmpty {
                var parsedURLString = callback
                let regex = try! NSRegularExpression(pattern: "\\{json:([a-zA-Z0-9_\\.]+)\\}")
                let matches = regex.matches(in: callback, range: NSRange(callback.startIndex..., in: callback))
                
                for match in matches.reversed() {
                    if let range = Range(match.range(at: 1), in: callback) {
                        let keyPath = String(callback[range])
                        let keys = keyPath.split(separator: ".")
                        var current: Any? = json
                        for key in keys {
                            if let dict = current as? [String: Any] {
                                current = dict[String(key)]
                            } else {
                                current = nil
                                break
                            }
                        }
                        let replacement = (current as? String) ?? "\(current ?? "")"
                        if let fullRange = Range(match.range, in: parsedURLString) {
                            parsedURLString.replaceSubrange(fullRange, with: replacement)
                        }
                    }
                }
                if let url = URL(string: parsedURLString) {
                    return url
                }
            } else {
                if let urlString = json["url"] as? String, let url = URL(string: urlString) {
                    return url
                }
            }
        }
        
        return targetURL
    }
}
