import XCTest
@testable import BerryShot
import CoreGraphics

final class OCRServiceTests: XCTestCase {
    
    func testExtractText() async throws {
        let service = OCRService()
        
        // Create a 100x100 white image
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 400, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        let cgImage = context.makeImage()!
        
        let text = try await service.extractText(from: cgImage)
        // A blank white image should result in no extracted text
        XCTAssertEqual(text, "")
    }
}
