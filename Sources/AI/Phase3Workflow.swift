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
    
    public func generateMeetingMinutes(transcript: [TranscriptSegment]) async throws -> String {
        let formatted = transcript
            .sorted { $0.timestamp < $1.timestamp }
            .map { seg -> String in
                let speaker = seg.source == .mic ? "You" : "Other"
                let m = Int(seg.timestamp) / 60
                let s = Int(seg.timestamp) % 60
                return String(format: "[%02d:%02d] \(speaker): \(seg.text)", m, s)
            }
            .joined(separator: "\n")

        let prompt = """
        You are a professional meeting minutes assistant. Based on the following meeting transcript, \
        create minutes in Markdown format with: \
        **Summary**, **Key Discussion Points**, **Decisions Made**, **Action Items**.

        Transcript:
        \(formatted)
        """
        return try await provider.generateText(prompt: prompt, image: nil)
    }

    public func generateStepByStepDocumentation(annotationsJSON: String, transcript: String, screenshot: CGImage? = nil, language: String = "English") async throws -> String {
        let hasAnnotations = annotationsJSON != "[]" && !annotationsJSON.isEmpty
        let hasTranscript = transcript != "No voice transcript available." && !transcript.isEmpty

        let contextDesc: String
        if hasAnnotations && hasTranscript {
            contextDesc = "the user's on-screen annotations and voice transcript below"
        } else if hasAnnotations {
            contextDesc = "the user's on-screen annotations below and the provided screenshot"
        } else if hasTranscript {
            contextDesc = "the voice transcript below and the provided screenshot"
        } else {
            contextDesc = "the provided screenshot"
        }

        let prompt = """
        You are an expert technical writer. Based on \(contextDesc), generate a clear and useful step-by-step tutorial or summary of what was demonstrated.
        Format the output in clean Markdown. Reply exclusively in \(language).

        \(hasAnnotations ? "Annotations Metadata:\n\(annotationsJSON)\n" : "")
        \(hasTranscript ? "Transcript:\n\(transcript)" : "")
        """

        return try await provider.generateText(prompt: prompt, image: screenshot)
    }
}
