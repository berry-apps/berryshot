import Foundation
import CoreGraphics

public enum AnnotationEventType: String, Codable {
    case addElement
    case updateElement
    case removeElement
    case clearAll
}

public struct AnnotationEvent: Codable {
    public let timestamp: TimeInterval
    public let eventType: AnnotationEventType
    public let elementData: Data? // JSON encoded AnnotationElement
    
    public init(timestamp: TimeInterval, eventType: AnnotationEventType, elementData: Data? = nil) {
        self.timestamp = timestamp
        self.eventType = eventType
        self.elementData = elementData
    }
}

public class AnnotationRecordingService {
    private var events: [AnnotationEvent] = []
    private var startTime: TimeInterval = 0
    private var isRecording = false
    
    public init() {}
    
    public func startRecording() {
        events.removeAll()
        startTime = Date().timeIntervalSince1970
        isRecording = true
    }
    
    public func stopRecording() -> [AnnotationEvent] {
        isRecording = false
        return events
    }
    
    public func recordEvent(type: AnnotationEventType, elementData: Data? = nil) {
        guard isRecording else { return }
        let now = Date().timeIntervalSince1970
        let relativeTime = now - startTime
        let event = AnnotationEvent(timestamp: relativeTime, eventType: type, elementData: elementData)
        events.append(event)
    }
    
    public func exportJSON(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(events)
        try data.write(to: url)
    }
}
