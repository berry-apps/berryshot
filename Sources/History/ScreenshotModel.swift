import Foundation
import SwiftData

@Model
public final class ScreenshotModel {
    @Attribute(.unique) public var id: UUID
    public var createdAt: Date
    public var imagePath: String
    public var thumbnailPath: String
    public var width: Int
    public var height: Int
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
