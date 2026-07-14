import Foundation

public struct TranscriptSegment: Identifiable {
    public enum Source { case mic, systemAudio }
    public let id = UUID()
    public let source: Source
    public var text: String
    public let timestamp: TimeInterval
}

public struct Screenshot: Identifiable, Codable {
    public let id: UUID
    public let createdAt: Date
    public let imagePath: String
    public let thumbnailPath: String
    public let width: Int
    public let height: Int
    public var ocrText: String?
    
    public init(id: UUID = UUID(), createdAt: Date = Date(), imagePath: String, thumbnailPath: String, width: Int, height: Int, ocrText: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.imagePath = imagePath
        self.thumbnailPath = thumbnailPath
        self.width = width
        self.height = height
        self.ocrText = ocrText
    }
}
