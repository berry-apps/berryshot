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
    /// `RedactionStatus.rawValue`, or `nil` for rows written before WP4. Kept
    /// as a plain optional `String` (not the enum) so history persistence
    /// does not depend on the `Redaction` module's type identity across
    /// SwiftData's lightweight-migration schema comparison.
    public var redactionStatus: String?

    public init(id: UUID = UUID(), createdAt: Date = Date(), imagePath: String, thumbnailPath: String, width: Int, height: Int, ocrText: String? = nil, redactionStatus: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.imagePath = imagePath
        self.thumbnailPath = thumbnailPath
        self.width = width
        self.height = height
        self.ocrText = ocrText
        self.redactionStatus = redactionStatus
    }
}
