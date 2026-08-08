import XCTest
@testable import BerryShot
import BerryShotIPC

/// Direct tests of the opaque-ref bookkeeping
/// (`06-agent-documentation-security.md` section 4: "short-lived opaque
/// element references bound to session, PID, and AX snapshot generation").
/// `CaptureBrokerUIAutomationTests` proves the same guarantees end-to-end
/// through `CaptureBroker`; these tests isolate the registry itself.
final class UIElementRegistryTests: XCTestCase {
    func testRegisterAndResolveRoundTrips() async throws {
        let registry = UIElementRegistry()
        let generation = await registry.beginGeneration(sessionID: "s1")
        let ref = await registry.register(handle: "node-1", sessionID: "s1", pid: 100, generation: generation, role: "AXButton", subrole: nil, title: "Save", descriptionText: nil, advertisedActions: [.press])

        let result = await registry.resolve(ref: ref, sessionID: "s1", pid: 100)
        switch result {
        case .success(let entry):
            XCTAssertEqual(entry.role, "AXButton")
            XCTAssertEqual(entry.advertisedActions, [.press])
        case .failure(let failure):
            XCTFail("Expected success, got \(failure)")
        }
    }

    func testResolveRejectsUnknownRef() async throws {
        let registry = UIElementRegistry()
        let result = await registry.resolve(ref: "does-not-exist", sessionID: "s1", pid: 100)
        guard case .failure(.notFound) = result else { return XCTFail("Expected notFound") }
    }

    func testResolveRejectsSessionMismatch() async throws {
        let registry = UIElementRegistry()
        let generation = await registry.beginGeneration(sessionID: "s1")
        let ref = await registry.register(handle: "node-1", sessionID: "s1", pid: 100, generation: generation, role: "AXButton", subrole: nil, title: nil, descriptionText: nil, advertisedActions: [.press])

        let result = await registry.resolve(ref: ref, sessionID: "different-session", pid: 100)
        guard case .failure(.sessionMismatch) = result else { return XCTFail("Expected sessionMismatch") }
    }

    func testResolveRejectsPIDMismatch() async throws {
        let registry = UIElementRegistry()
        let generation = await registry.beginGeneration(sessionID: "s1")
        let ref = await registry.register(handle: "node-1", sessionID: "s1", pid: 100, generation: generation, role: "AXButton", subrole: nil, title: nil, descriptionText: nil, advertisedActions: [.press])

        let result = await registry.resolve(ref: ref, sessionID: "s1", pid: 999)
        guard case .failure(.pidMismatch) = result else { return XCTFail("Expected pidMismatch") }
    }

    /// The mechanism behind "Reuse stale element reference after PID/window
    /// change: rejected": a second `beginGeneration` (what every
    /// `inspect_ui` call does) invalidates every ref issued under the prior
    /// generation, even though the ref string itself has not expired and
    /// still names a real, still-registered node identity elsewhere.
    func testBeginGenerationInvalidatesPreviousRefs() async throws {
        let registry = UIElementRegistry()
        let firstGeneration = await registry.beginGeneration(sessionID: "s1")
        let staleRef = await registry.register(handle: "node-1", sessionID: "s1", pid: 100, generation: firstGeneration, role: "AXButton", subrole: nil, title: nil, descriptionText: nil, advertisedActions: [.press])

        _ = await registry.beginGeneration(sessionID: "s1") // simulates a second inspect_ui call

        let result = await registry.resolve(ref: staleRef, sessionID: "s1", pid: 100)
        guard case .failure(.notFound) = result else { return XCTFail("Expected the stale ref to be purged (notFound), got \(result)") }
    }

    func testClearSessionRemovesAllItsRefsButNotOthers() async throws {
        let registry = UIElementRegistry()
        let genA = await registry.beginGeneration(sessionID: "sessionA")
        let refA = await registry.register(handle: "a", sessionID: "sessionA", pid: 1, generation: genA, role: "AXButton", subrole: nil, title: nil, descriptionText: nil, advertisedActions: [.press])
        let genB = await registry.beginGeneration(sessionID: "sessionB")
        let refB = await registry.register(handle: "b", sessionID: "sessionB", pid: 2, generation: genB, role: "AXButton", subrole: nil, title: nil, descriptionText: nil, advertisedActions: [.press])

        await registry.clearSession("sessionA")

        let resultA = await registry.resolve(ref: refA, sessionID: "sessionA", pid: 1)
        guard case .failure(.notFound) = resultA else { return XCTFail("Expected sessionA's ref to be gone") }

        let resultB = await registry.resolve(ref: refB, sessionID: "sessionB", pid: 2)
        guard case .success = resultB else { return XCTFail("Expected sessionB's ref to remain valid") }
    }

    func testRegisterTreeAssignsRefsToEveryNodeAndPreservesShape() async throws {
        let registry = UIElementRegistry()
        let generation = await registry.beginGeneration(sessionID: "s1")
        let tree = AXObservedNode(
            handle: "root",
            role: "AXWindow",
            subrole: nil,
            title: "Window",
            descriptionText: nil,
            enabledState: true,
            focused: false,
            frame: nil,
            supportedActions: [],
            childCount: 1,
            children: [
                AXObservedNode(handle: "child", role: "AXButton", subrole: nil, title: "Save", descriptionText: nil, enabledState: true, focused: false, frame: nil, supportedActions: [.press], childCount: 0, children: [])
            ]
        )

        let dto = await registry.registerTree(tree, sessionID: "s1", pid: 100, generation: generation)
        XCTAssertNotNil(dto.ref)
        XCTAssertEqual(dto.children.count, 1)
        XCTAssertNotNil(dto.children[0].ref)
        XCTAssertEqual(dto.children[0].role, "AXButton")
        XCTAssertNotEqual(dto.ref, dto.children[0].ref)

        // Both refs resolve under the same generation.
        let childResolution = await registry.resolve(ref: dto.children[0].ref!, sessionID: "s1", pid: 100)
        guard case .success(let entry) = childResolution else { return XCTFail("Expected child ref to resolve") }
        XCTAssertEqual(entry.advertisedActions, [.press])
    }
}
