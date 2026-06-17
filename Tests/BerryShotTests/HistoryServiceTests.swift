import XCTest
@testable import BerryShot
import SwiftData

@MainActor
final class HistoryServiceTests: XCTestCase {
    
    func testSaveAndFetch() throws {
        let service = HistoryService.shared
        
        let initialCount = service.fetchAll().count
        
        let model = ScreenshotModel(
            imagePath: "/tmp/test.png",
            thumbnailPath: "/tmp/test.png",
            width: 100,
            height: 100,
            ocrText: "Test OCR"
        )
        
        service.save(model)
        
        let fetched = service.fetchAll()
        XCTAssertEqual(fetched.count, initialCount + 1)
        XCTAssertEqual(fetched.first?.ocrText, "Test OCR")
        
        // Cleanup
        service.delete(model)
    }
}
