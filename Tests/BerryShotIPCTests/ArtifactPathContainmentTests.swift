import XCTest
@testable import BerryShotIPC

final class ArtifactPathContainmentTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = URL(fileURLWithPath: "/tmp/bscontainment-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        root = nil
        super.tearDown()
    }

    // MARK: - canonicalContainedPath

    func testPathDirectlyInsideRootIsContained() {
        let path = root.appendingPathComponent("abc/image.png").path
        XCTAssertNotNil(ArtifactPathContainment.canonicalContainedPath(path, withinRoot: root.path))
    }

    func testDotDotEscapeOutsideRootIsRejected() {
        let escaping = root.appendingPathComponent("abc/../../etc/passwd").path
        XCTAssertNil(ArtifactPathContainment.canonicalContainedPath(escaping, withinRoot: root.path))
    }

    func testUnrelatedAbsolutePathIsRejected() {
        XCTAssertNil(ArtifactPathContainment.canonicalContainedPath("/etc/passwd", withinRoot: root.path))
    }

    func testSiblingDirectoryWithSharedPrefixIsNotConsideredContained() {
        // Regression guard for a naive `hasPrefix` check without a trailing
        // separator: "/tmp/bscontainment-abc-evil" must not be considered
        // contained within "/tmp/bscontainment-abc".
        let siblingRoot = URL(fileURLWithPath: root.path + "-evil", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: siblingRoot) }
        try? FileManager.default.createDirectory(at: siblingRoot, withIntermediateDirectories: true)
        let siblingFile = siblingRoot.appendingPathComponent("image.png").path
        XCTAssertNil(ArtifactPathContainment.canonicalContainedPath(siblingFile, withinRoot: root.path))
    }

    func testSymlinkEscapingRootIsRejected() throws {
        let outside = URL(fileURLWithPath: "/tmp/bscontainment-outside-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        let secretFile = outside.appendingPathComponent("secret.png")
        FileManager.default.createFile(atPath: secretFile.path, contents: Data("secret".utf8))

        let symlinkPath = root.appendingPathComponent("escape.png")
        try FileManager.default.createSymbolicLink(at: symlinkPath, withDestinationURL: secretFile)

        XCTAssertNil(ArtifactPathContainment.canonicalContainedPath(symlinkPath.path, withinRoot: root.path))
    }

    func testRootItselfIsContained() {
        XCTAssertNotNil(ArtifactPathContainment.canonicalContainedPath(root.path, withinRoot: root.path))
    }

    // MARK: - validatedArtifactID

    func testWellFormedUUIDIsValid() {
        let id = UUID().uuidString
        XCTAssertEqual(ArtifactPathContainment.validatedArtifactID(id), id)
    }

    func testLowercaseUUIDNormalizesToCanonicalUppercaseForm() {
        let id = UUID()
        let lowercase = id.uuidString.lowercased()
        XCTAssertEqual(ArtifactPathContainment.validatedArtifactID(lowercase), id.uuidString)
    }

    func testPathTraversalStringsAreNeverValidArtifactIDs() {
        let attempts = [
            "../../../etc/passwd",
            "/etc/passwd",
            "abc/../def",
            "",
            "not-a-uuid-at-all",
            String(repeating: "a", count: 4000),
            "00000000-0000-0000-0000-00000000000g" // invalid hex digit
        ]
        for attempt in attempts {
            XCTAssertNil(ArtifactPathContainment.validatedArtifactID(attempt), "expected \(attempt) to be rejected")
        }
    }
}
