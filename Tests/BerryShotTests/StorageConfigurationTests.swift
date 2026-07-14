import Foundation
import XCTest
@testable import BerryShot

final class StorageConfigurationTests: XCTestCase {
    func testProviderEnum() {
        XCTAssertEqual(StorageProviderType.local.rawValue, "Local Directory")
        XCTAssertEqual(StorageProviderType.googleDrive.rawValue, "Google Drive")
        XCTAssertEqual(StorageProviderType.custom.rawValue, "Custom Service")
    }
}
