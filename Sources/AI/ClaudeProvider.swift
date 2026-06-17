import Foundation
import CoreGraphics
import AppKit

public final class ClaudeProvider: LLMProvider, Sendable {
    private let config: AIConfiguration
    
    public init(config: AIConfiguration) {
        self.config = config
    }
    
    public func generateText(prompt: String, image: CGImage? = nil) async throws -> String {
        let request = try createRequest(prompt: prompt, image: image, stream: false)
        return try await executeRequest(request: request)
    }
    
    private func createRequest(prompt: String, image: CGImage?, stream: Bool) throws -> URLRequest {
        var baseURLString = config.baseURL ?? "https://api.anthropic.com"
        if baseURLString.hasSuffix("/") {
            baseURLString = String(baseURLString.dropLast())
        }
        
        let urlString: String
        if baseURLString.hasSuffix("/v1/messages") || baseURLString.hasSuffix("/messages") {
            urlString = baseURLString
        } else if baseURLString.hasSuffix("/v1") {
            urlString = baseURLString + "/messages"
        } else {
            urlString = baseURLString + "/v1/messages"
        }
        
        guard let url = URL(string: urlString) else { throw AIError.invalidConfiguration }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var content: [[String: Any]] = []
        
        if let image = image {
            let nsImage = NSImage(cgImage: image, size: .zero)
            if let tiff = nsImage.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                let base64String = pngData.base64EncodedString()
                content.append([
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": "image/png",
                        "data": base64String
                    ]
                ])
            }
        }
        
        content.append(["type": "text", "text": prompt])
        
        let body: [String: Any] = [
            "model": config.model,
            "max_tokens": 4096,
            "stream": stream,
            "messages": [
                [
                    "role": "user",
                    "content": content
                ]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
    
    private func executeRequest(request: URLRequest) async throws -> String {
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            let errorString = String(data: data, encoding: .utf8) ?? "Unknown Error"
            throw AIError.apiError("Status \(httpResponse.statusCode): \(errorString)")
        }
        
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let contentArray = json["content"] as? [[String: Any]],
           let firstContent = contentArray.first,
           let text = firstContent["text"] as? String {
            return text
        }
        
        throw AIError.invalidResponse
    }
    
    public func generateTextStream(prompt: String, image: CGImage?) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let request = try createRequest(prompt: prompt, image: image, stream: true)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AIError.invalidResponse
                    }
                    
                    if httpResponse.statusCode != 200 {
                        var errorData = Data()
                        for try await byte in bytes {
                            errorData.append(byte)
                        }
                        let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown Error"
                        throw AIError.apiError("Status \(httpResponse.statusCode): \(errorString)")
                    }
                    
                    for try await line in bytes.lines {
                        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmedLine.hasPrefix("data:") {
                            let contentStart = trimmedLine.index(trimmedLine.startIndex, offsetBy: 5)
                            let jsonStr = trimmedLine[contentStart...].trimmingCharacters(in: .whitespacesAndNewlines)
                            
                            guard let data = jsonStr.data(using: .utf8),
                                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                                continue
                            }
                            
                            if let errorObj = json["error"] as? [String: Any],
                               let message = errorObj["message"] as? String {
                                throw AIError.apiError(message)
                            }
                            
                            if let type = json["type"] as? String {
                                if type == "content_block_delta",
                                   let delta = json["delta"] as? [String: Any],
                                   let text = delta["text"] as? String {
                                    continuation.yield(text)
                                } else if type == "message_stop" {
                                    break
                                }
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
