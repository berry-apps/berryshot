import XCTest
@testable import BerryShot

/// `MCPIntegrationSettings.shared` is a real singleton (matching this
/// codebase's existing `RedactionSettings.shared` convention) backed by
/// `UserDefaults.standard` and, when actually enabled, the real
/// `~/Library/Application Support/BerryShot/MCP` path. These tests always
/// construct their own instance with an isolated temp `baseDirectory`
/// instead, so `enable()` never touches a path a real running BerryShot
/// instance on the test machine might also be using.
///
/// Matches this codebase's existing convention for `@MainActor` test
/// classes (see `HistoryServiceTests`/`RedactionOrderingTests`) of not
/// overriding `setUp()`/`tearDown()` — those are `nonisolated` on
/// `XCTestCase` and cannot touch `@MainActor` state without extra
/// ceremony. Each test builds and tears down its own fixture inline.
@MainActor
final class MCPIntegrationSettingsTests: XCTestCase {
    private func freshBaseDirectory() -> URL {
        URL(fileURLWithPath: "/tmp/bsmcp-settings-\(UUID().uuidString.prefix(8))", isDirectory: true)
    }

    /// Every test starts and ends with a clean persisted-preference slate:
    /// all instances share the same `UserDefaults`-backed key
    /// (`mcp_integration_enabled`) within this test process.
    private func resetPersistedPreference() {
        UserDefaults.standard.removeObject(forKey: "mcp_integration_enabled")
    }

    func testFreshInstanceIsDisabledByDefault() {
        resetPersistedPreference()
        let baseDirectory = freshBaseDirectory()
        defer { try? FileManager.default.removeItem(at: baseDirectory); resetPersistedPreference() }

        let settings = MCPIntegrationSettings(baseDirectory: baseDirectory)
        XCTAssertFalse(settings.isEnabled)
        XCTAssertFalse(settings.isRunning)
    }

    func testEnableStartsARealListeningBrokerAndWritesDescriptor() {
        resetPersistedPreference()
        let baseDirectory = freshBaseDirectory()
        let settings = MCPIntegrationSettings(baseDirectory: baseDirectory)
        defer { settings.disable(); try? FileManager.default.removeItem(at: baseDirectory); resetPersistedPreference() }

        settings.isEnabled = true

        XCTAssertTrue(settings.isEnabled)
        XCTAssertTrue(settings.isRunning)
        XCTAssertNil(settings.lastErrorMessage)
        XCTAssertTrue(FileManager.default.fileExists(atPath: baseDirectory.appendingPathComponent("broker.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: baseDirectory.appendingPathComponent("broker.sock").path))
    }

    func testDisableStopsTheBrokerAndRemovesSocketAndDescriptor() {
        resetPersistedPreference()
        let baseDirectory = freshBaseDirectory()
        defer { try? FileManager.default.removeItem(at: baseDirectory); resetPersistedPreference() }

        let settings = MCPIntegrationSettings(baseDirectory: baseDirectory)
        settings.isEnabled = true
        XCTAssertTrue(settings.isRunning)

        settings.isEnabled = false

        XCTAssertFalse(settings.isEnabled)
        XCTAssertFalse(settings.isRunning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: baseDirectory.appendingPathComponent("broker.sock").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: baseDirectory.appendingPathComponent("broker.json").path))
    }

    func testEnableIsIdempotentWhileAlreadyRunning() {
        resetPersistedPreference()
        let baseDirectory = freshBaseDirectory()
        let settings = MCPIntegrationSettings(baseDirectory: baseDirectory)
        defer { settings.disable(); try? FileManager.default.removeItem(at: baseDirectory); resetPersistedPreference() }

        settings.enable()
        let descriptorPath = baseDirectory.appendingPathComponent("broker.json").path
        let firstDescriptorContents = try? Data(contentsOf: URL(fileURLWithPath: descriptorPath))

        settings.enable() // second call while already running

        XCTAssertTrue(settings.isRunning)
        let secondDescriptorContents = try? Data(contentsOf: URL(fileURLWithPath: descriptorPath))
        XCTAssertEqual(firstDescriptorContents, secondDescriptorContents, "a redundant enable() must not rotate/restart an already-running broker")
    }

    func testDisableIsSafeWhenNotRunning() {
        resetPersistedPreference()
        let baseDirectory = freshBaseDirectory()
        defer { try? FileManager.default.removeItem(at: baseDirectory); resetPersistedPreference() }

        let settings = MCPIntegrationSettings(baseDirectory: baseDirectory)
        settings.disable() // must not crash
        XCTAssertFalse(settings.isRunning)
    }

    /// The core "resume on relaunch" design decision documented on
    /// `MCPIntegrationSettings`: constructing a *new* instance while the
    /// persisted preference is already `true` (as if the GUI relaunched
    /// after the user previously enabled it) resumes the broker
    /// automatically, without any code path calling `enable()` itself.
    func testConstructingANewInstanceResumesWhenThePersistedPreferenceIsAlreadyTrue() {
        resetPersistedPreference()
        let baseDirectory = freshBaseDirectory()
        defer { try? FileManager.default.removeItem(at: baseDirectory); resetPersistedPreference() }

        let first = MCPIntegrationSettings(baseDirectory: baseDirectory)
        first.isEnabled = true
        first.disable() // stop the broker but leave the *persisted* preference...

        // ...except disable() also clears the persisted preference (it is
        // an explicit user "off" action). Simulate a relaunch after the
        // user left it *on* by restoring the persisted flag directly, the
        // same way UserDefaults would already contain `true` from a
        // previous session's enable() the user never turned back off.
        UserDefaults.standard.set(true, forKey: "mcp_integration_enabled")

        let second = MCPIntegrationSettings(baseDirectory: baseDirectory)
        defer { second.disable() }
        XCTAssertTrue(second.isRunning, "a fresh instance must resume when the persisted preference was already on")
    }

    func testFreshInstanceNeverStartsWhenPreferenceWasNeverEnabled() {
        resetPersistedPreference()
        let baseDirectory = freshBaseDirectory()
        defer { try? FileManager.default.removeItem(at: baseDirectory); resetPersistedPreference() }

        // Belt-and-suspenders on the "disabled by default" requirement:
        // with no prior UserDefaults value at all, a brand new instance
        // must never be running.
        let settings = MCPIntegrationSettings(baseDirectory: baseDirectory)
        XCTAssertFalse(settings.isRunning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: baseDirectory.appendingPathComponent("broker.sock").path))
    }
}
