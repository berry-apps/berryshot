import XCTest
@testable import BerryShot
import BerryShotIPC

final class DocumentationSessionManagerTests: XCTestCase {
    // MARK: - begin validation

    func testBeginRejectsEmptyBundleIdentifier() async throws {
        let manager = DocumentationSessionManager()
        do {
            _ = try await manager.begin(makeSessionBeginRequest(bundleIdentifier: ""))
            XCTFail("Expected invalid_argument")
        } catch DocumentationSessionManager.SessionError.invalidArgument {
            // expected
        }
    }

    func testBeginRejectsEmptyDisplayName() async throws {
        let manager = DocumentationSessionManager()
        do {
            _ = try await manager.begin(makeSessionBeginRequest(displayName: ""))
            XCTFail("Expected invalid_argument")
        } catch DocumentationSessionManager.SessionError.invalidArgument {
            // expected
        }
    }

    func testBeginRejectsTTLOutOfBounds() async throws {
        let manager = DocumentationSessionManager()
        do {
            _ = try await manager.begin(makeSessionBeginRequest(ttlSeconds: 1))
            XCTFail("Expected invalid_argument")
        } catch DocumentationSessionManager.SessionError.invalidArgument {
            // expected
        }
    }

    func testBeginRejectsMaxArtifactsOutOfBounds() async throws {
        let manager = DocumentationSessionManager()
        do {
            _ = try await manager.begin(makeSessionBeginRequest(maxArtifacts: 0))
            XCTFail("Expected invalid_argument")
        } catch DocumentationSessionManager.SessionError.invalidArgument {
            // expected
        }
    }

    /// `10-decisions-risks-open-questions.md` section 4 item 4 and
    /// `06-agent-documentation-security.md` section 2: MCP redaction is
    /// always "required"; a session cannot be created with a weaker
    /// explicit request.
    func testBeginRejectsExplicitWeakerRedactionPolicy() async throws {
        let manager = DocumentationSessionManager()
        let weakRequest = DocumentationSessionBeginRequest(
            bundleIdentifier: "com.example.App",
            displayName: "Test",
            mode: .readOnly,
            redactionPolicy: IPCRedactionPolicy.none,
            redactionStyle: .solid,
            ttlSeconds: 600,
            maxArtifacts: 10,
            allowLaunch: false
        )
        do {
            _ = try await manager.begin(weakRequest)
            XCTFail("Expected invalid_argument")
        } catch DocumentationSessionManager.SessionError.invalidArgument {
            // expected
        }
    }

    func testBeginLocksRedactionPolicyToRequiredByDefault() async throws {
        let manager = DocumentationSessionManager()
        let dto = try await manager.begin(makeSessionBeginRequest())
        XCTAssertEqual(dto.redactionPolicy, .required)
        XCTAssertEqual(dto.status, .active)
        XCTAssertEqual(dto.artifactCount, 0)
        XCTAssertTrue(dto.steps.isEmpty)
    }

    /// An over-length `display_name` is rejected outright by the bound
    /// check (proven by `testBeginRejectsEmptyDisplayName`'s sibling
    /// bound), not silently truncated — this test only proves the
    /// still-in-bounds control-character-stripping half of sanitization.
    func testBeginSanitizesControlCharactersInDisplayName() async throws {
        let manager = DocumentationSessionManager()
        let dirty = "Evil\u{0007}Session"
        let dto = try await manager.begin(makeSessionBeginRequest(displayName: dirty))
        XCTAssertFalse(dto.displayName.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) })
        XCTAssertEqual(dto.displayName, "EvilSession")
    }

    func testBeginRejectsDisplayNameOverMaxLength() async throws {
        let manager = DocumentationSessionManager()
        let tooLong = String(repeating: "X", count: DocumentationSessionManager.maxDisplayNameLength + 1)
        do {
            _ = try await manager.begin(makeSessionBeginRequest(displayName: tooLong))
            XCTFail("Expected invalid_argument")
        } catch DocumentationSessionManager.SessionError.invalidArgument {
            // expected
        }
    }

    // MARK: - status / notFound / expiry

    func testStatusOfUnknownSessionThrowsNotFound() async throws {
        let manager = DocumentationSessionManager()
        do {
            _ = try await manager.status(sessionID: "nonexistent")
            XCTFail("Expected notFound")
        } catch DocumentationSessionManager.SessionError.notFound {
            // expected
        }
    }

    /// Uses `DocumentationSessionManager`'s injectable clock to
    /// deterministically fast-forward past the session's TTL instead of
    /// sleeping in wall-clock time (which would either flake or force a
    /// real 60s-minimum wait per test run).
    func testExpiredSessionThrowsExpiredAndIsRemoved() async throws {
        let now = LockedBox(Date())
        let manager = DocumentationSessionManager(clock: { now.value })

        let begin = try await manager.begin(makeSessionBeginRequest(ttlSeconds: 60))
        now.value = now.value.addingTimeInterval(61)

        do {
            _ = try await manager.activeSession(begin.sessionID)
            XCTFail("Expected expired")
        } catch DocumentationSessionManager.SessionError.expired {
            // expected
        }

        // Removed, not merely reported expired-in-place: a second lookup
        // must also fail (as `notFound` this time, since it is gone).
        do {
            _ = try await manager.status(sessionID: begin.sessionID)
            XCTFail("Expected notFound after removal")
        } catch DocumentationSessionManager.SessionError.notFound {
            // expected
        }
    }

    func testRecordStepRejectsOnExpiredSession() async throws {
        let now = LockedBox(Date())
        let manager = DocumentationSessionManager(clock: { now.value })
        let begin = try await manager.begin(makeSessionBeginRequest(ttlSeconds: 60, maxArtifacts: 5))
        let statusBeforeExpiry = try await manager.status(sessionID: begin.sessionID).status
        XCTAssertEqual(statusBeforeExpiry, .active)

        now.value = now.value.addingTimeInterval(61)
        do {
            _ = try await manager.recordStep(sessionID: begin.sessionID, captureID: "c1", feature: "F1", navigationSummary: [], redactionStatus: .applied, verification: .verified, notes: [])
            XCTFail("Expected expired")
        } catch DocumentationSessionManager.SessionError.expired {
            // expected
        }
    }

    // MARK: - recordStep / artifact limit

    func testRecordStepAppendsStepAndUpdatesCoverage() async throws {
        let manager = DocumentationSessionManager()
        let begin = try await manager.begin(makeSessionBeginRequest(maxArtifacts: 5))
        let updated = try await manager.recordStep(
            sessionID: begin.sessionID,
            captureID: "capture-1",
            feature: "General settings",
            navigationSummary: ["Settings", "General"],
            redactionStatus: .applied,
            verification: .verified,
            notes: []
        )
        XCTAssertEqual(updated.artifactCount, 1)
        XCTAssertEqual(updated.steps.count, 1)
        XCTAssertEqual(updated.coverage.verified, [updated.steps[0].stepID])
        XCTAssertEqual(updated.lastActionDescription, "Captured step: General settings")
    }

    func testRecordStepRejectsAtArtifactLimit() async throws {
        let manager = DocumentationSessionManager()
        let begin = try await manager.begin(makeSessionBeginRequest(maxArtifacts: 1))
        _ = try await manager.recordStep(sessionID: begin.sessionID, captureID: "c1", feature: "F1", navigationSummary: [], redactionStatus: .applied, verification: .verified, notes: [])
        do {
            _ = try await manager.recordStep(sessionID: begin.sessionID, captureID: "c2", feature: "F2", navigationSummary: [], redactionStatus: .applied, verification: .verified, notes: [])
            XCTFail("Expected artifactLimitReached")
        } catch DocumentationSessionManager.SessionError.artifactLimitReached {
            // expected
        }
    }

    func testRecordStepTruncatesOversizedNavigationSummaryAndNotes() async throws {
        let manager = DocumentationSessionManager()
        let begin = try await manager.begin(makeSessionBeginRequest(maxArtifacts: 5))
        let manyEntries = (0..<50).map { "Step \($0)" }
        let updated = try await manager.recordStep(
            sessionID: begin.sessionID,
            captureID: "c1",
            feature: "F1",
            navigationSummary: manyEntries,
            redactionStatus: .applied,
            verification: .conditional,
            notes: manyEntries
        )
        XCTAssertLessThanOrEqual(updated.steps[0].navigationSummary.count, DocumentationSessionManager.maxNavigationSummaryEntries)
        XCTAssertLessThanOrEqual(updated.steps[0].notes.count, DocumentationSessionManager.maxNotesCount)
    }

    // MARK: - end / Stop

    func testEndMarksSessionStoppedAndRejectsFurtherWork() async throws {
        let manager = DocumentationSessionManager()
        let begin = try await manager.begin(makeSessionBeginRequest())
        let ended = try await manager.end(sessionID: begin.sessionID)
        XCTAssertEqual(ended.status, .stopped)

        do {
            _ = try await manager.activeSession(begin.sessionID)
            XCTFail("Expected stopped")
        } catch DocumentationSessionManager.SessionError.stopped {
            // expected
        }
    }

    func testIsStopRequestedReflectsEndCall() async throws {
        let manager = DocumentationSessionManager()
        let begin = try await manager.begin(makeSessionBeginRequest())
        let before = await manager.isStopRequested(begin.sessionID)
        XCTAssertFalse(before)
        _ = try await manager.end(sessionID: begin.sessionID)
        let after = await manager.isStopRequested(begin.sessionID)
        XCTAssertTrue(after)
    }

    func testStopAllStopsEveryActiveSession() async throws {
        let manager = DocumentationSessionManager()
        let first = try await manager.begin(makeSessionBeginRequest(bundleIdentifier: "com.example.A"))
        let second = try await manager.begin(makeSessionBeginRequest(bundleIdentifier: "com.example.B"))
        await manager.stopAll()
        let firstStopped = await manager.isStopRequested(first.sessionID)
        let secondStopped = await manager.isStopRequested(second.sessionID)
        XCTAssertTrue(firstStopped)
        XCTAssertTrue(secondStopped)
    }

    func testEndOfUnknownSessionThrowsNotFound() async throws {
        let manager = DocumentationSessionManager()
        do {
            _ = try await manager.end(sessionID: "nonexistent")
            XCTFail("Expected notFound")
        } catch DocumentationSessionManager.SessionError.notFound {
            // expected
        }
    }

    // MARK: - indicator onChange

    func testOnChangeFiresOnBeginStepAndEnd() async throws {
        actor Recorder {
            var snapshots: [[DocumentationSessionDTO]] = []
            func record(_ sessions: [DocumentationSessionDTO]) { snapshots.append(sessions) }
        }
        let recorder = Recorder()
        let manager = DocumentationSessionManager(onChange: { sessions in
            Task { await recorder.record(sessions) }
        })
        let begin = try await manager.begin(makeSessionBeginRequest(maxArtifacts: 5))
        _ = try await manager.recordStep(sessionID: begin.sessionID, captureID: "c1", feature: "F1", navigationSummary: [], redactionStatus: .applied, verification: .verified, notes: [])
        _ = try await manager.end(sessionID: begin.sessionID)

        // Give the fire-and-forget recorder tasks a moment to run.
        try await Task.sleep(nanoseconds: 50_000_000)
        let snapshotCount = await recorder.snapshots.count
        XCTAssertGreaterThanOrEqual(snapshotCount, 3, "expected at least one onChange notification per begin/recordStep/end")
    }
}
