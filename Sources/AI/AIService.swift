import Foundation

public protocol AIServiceProtocol {
    func analyzeScreenshot(imagePath: String) async throws -> String
}

public class AIService: AIServiceProtocol {
    public init() {}
    
    public func analyzeScreenshot(imagePath: String) async throws -> String {
        // Simulate AI analysis delay
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return "AI Analysis: This screenshot contains text and UI elements."
    }
}
