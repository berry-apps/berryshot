import Foundation
import CoreGraphics
import AppKit

public final class OpenAICompatibleProvider: LLMProvider, Sendable {
    private let config: AIConfiguration
    private let defaultBaseURL: String
    
    public init(config: AIConfiguration, defaultBaseURL: String = "https://api.openai.com/v1") {
        self.config = config
        self.defaultBaseURL = defaultBaseURL
    }
    
    public func generateText(prompt: String, image: CGImage? = nil) async throws -> String {
        let request = try createRequest(prompt: prompt, image: image, stream: false)
        return try await executeRequest(request: request)
    }
    
    public func generateChatStream(messages: [AIChatMessage], image: CGImage?) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let request = try createChatRequest(messages: messages, image: image, stream: true)
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
                            
                            if jsonStr == "[DONE]" {
                                break
                            }
                            
                            guard let data = jsonStr.data(using: .utf8),
                                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                                continue
                            }
                            
                            if let errorObj = json["error"] as? [String: Any],
                               let message = errorObj["message"] as? String {
                                throw AIError.apiError(message)
                            }
                            
                            if let choices = json["choices"] as? [[String: Any]],
                               let firstChoice = choices.first,
                               let delta = firstChoice["delta"] as? [String: Any],
                               let content = delta["content"] as? String {
                                continuation.yield(content)
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
    
    private func createRequest(prompt: String, image: CGImage?, stream: Bool) throws -> URLRequest {
        var baseURLString = config.baseURL ?? defaultBaseURL
        if baseURLString.hasSuffix("/") {
            baseURLString = String(baseURLString.dropLast())
        }
        
        let urlString: String
        if baseURLString.hasSuffix("/chat/completions") {
            urlString = baseURLString
        } else {
            urlString = baseURLString + "/chat/completions"
        }
        
        guard let url = URL(string: urlString) else { throw AIError.invalidConfiguration }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let plan = config.plan {
            request.setValue(plan, forHTTPHeaderField: "X-Plan")
            request.setValue(plan, forHTTPHeaderField: "X-Mimo-Plan")
        }
        
        var messages: [[String: Any]] = []
        
        var contentArray: [[String: Any]] = [
            ["type": "text", "text": prompt]
        ]
        
        if let image = image {
            // Convert CGImage to base64
            let nsImage = NSImage(cgImage: image, size: NSZeroSize)
            if let tiff = nsImage.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let pngData = bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) {
                let base64String = pngData.base64EncodedString()
                contentArray.append([
                    "type": "image_url",
                    "image_url": [
                        "url": "data:image/png;base64,\(base64String)"
                    ]
                ])
            }
        }
        
        messages.append(["role": "user", "content": contentArray])
        
        var body: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "stream": stream
        ]
        
        if let plan = config.plan {
            body["plan"] = plan
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
    
    private func createChatRequest(messages: [AIChatMessage], image: CGImage?, stream: Bool) throws -> URLRequest {
        var baseURLString = config.baseURL ?? defaultBaseURL
        if baseURLString.hasSuffix("/") {
            baseURLString = String(baseURLString.dropLast())
        }
        
        let urlString = baseURLString.hasSuffix("/chat/completions") ? baseURLString : baseURLString + "/chat/completions"
        guard let url = URL(string: urlString) else { throw AIError.invalidConfiguration }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let plan = config.plan {
            request.setValue(plan, forHTTPHeaderField: "X-Plan")
            request.setValue(plan, forHTTPHeaderField: "X-Mimo-Plan")
        }
        
        var apiMessages: [[String: Any]] = []
        
        for msg in messages {
            if msg.role == .user, let img = image, msg == messages.last {
                // Attach image to the last user message
                var contentArray: [[String: Any]] = [
                    ["type": "text", "text": msg.content]
                ]
                
                let nsImage = NSImage(cgImage: img, size: NSZeroSize)
                if let tiff = nsImage.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiff),
                   let pngData = bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) {
                    let base64String = pngData.base64EncodedString()
                    contentArray.append([
                        "type": "image_url",
                        "image_url": [
                            "url": "data:image/png;base64,\(base64String)"
                        ]
                    ])
                }
                apiMessages.append(["role": msg.role.rawValue, "content": contentArray])
            } else {
                apiMessages.append(["role": msg.role.rawValue, "content": msg.content])
            }
        }
        
        var body: [String: Any] = [
            "model": config.model,
            "messages": apiMessages,
            "stream": stream
        ]
        
        if let plan = config.plan {
            body["plan"] = plan
        }
        
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
           let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
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
                            
                            if jsonStr == "[DONE]" {
                                break
                            }
                            
                            guard let data = jsonStr.data(using: .utf8),
                                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                                continue
                            }
                            
                            if let errorObj = json["error"] as? [String: Any],
                               let message = errorObj["message"] as? String {
                                throw AIError.apiError(message)
                            }
                            
                            if let choices = json["choices"] as? [[String: Any]],
                               let firstChoice = choices.first,
                               let delta = firstChoice["delta"] as? [String: Any],
                               let content = delta["content"] as? String {
                                continuation.yield(content)
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
