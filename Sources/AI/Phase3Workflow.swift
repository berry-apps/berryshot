import Foundation
import CoreGraphics

public class Phase3Workflow {
    public let provider: LLMProvider
    
    public init?(provider: LLMProvider? = AIProviderFactory.createProvider()) {
        guard let p = provider else { return nil }
        self.provider = p
    }
    
    public func generateSummary(transcript: String) async throws -> String {
        let prompt = """
        You are an expert technical assistant. Please summarize the following video transcript into a concise overview of what was demonstrated.
        
        Transcript:
        \(transcript)
        """
        
        return try await provider.generateText(prompt: prompt, image: nil)
    }
    
    public func generateStepByStepDocumentation(annotationsJSON: String, transcript: String) async throws -> String {
        let prompt = """
        You are an expert technical writer. Based on the following user interactions (annotations metadata) and the video transcript, generate a step-by-step tutorial.
        Format the output in clean Markdown.
        
        Annotations Metadata:
        \(annotationsJSON)
        
        Transcript:
        \(transcript)
        """
        
        return try await provider.generateText(prompt: prompt, image: nil)
    }
}
