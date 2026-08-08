import XCTest
@testable import BerryShotIPC

final class IPCFramingTests: XCTestCase {
    func testEncodeThenFeedRoundTripsExactPayload() throws {
        let payload = Data("hello broker".utf8)
        let frame = IPCFraming.encode(payload)

        var reader = IPCFrameReader()
        let frames = try reader.feed(frame)

        XCTAssertEqual(frames, [payload])
        XCTAssertEqual(reader.pendingByteCount, 0)
    }

    func testEncodePrependsExactFourByteBigEndianLength() {
        let payload = Data([0xAA, 0xBB, 0xCC])
        let frame = IPCFraming.encode(payload)

        XCTAssertEqual(frame.count, 4 + payload.count)
        let lengthBytes = Array(frame.prefix(4))
        XCTAssertEqual(lengthBytes, [0x00, 0x00, 0x00, 0x03])
        XCTAssertEqual(Array(frame.suffix(3)), Array(payload))
    }

    func testEmptyPayloadRoundTrips() throws {
        let frame = IPCFraming.encode(Data())
        var reader = IPCFrameReader()
        let frames = try reader.feed(frame)
        XCTAssertEqual(frames, [Data()])
    }

    // MARK: - Partial reads/writes

    func testFrameArrivingOneByteAtATimeIsReassembledExactly() throws {
        let payload = Data("reassembled without loss or duplication".utf8)
        let frame = IPCFraming.encode(payload)
        var reader = IPCFrameReader()

        var collected: [Data] = []
        for byte in frame {
            let frames = try reader.feed(Data([byte]))
            collected.append(contentsOf: frames)
        }

        XCTAssertEqual(collected, [payload])
    }

    func testNoFramesYieldedUntilFullPayloadHasArrived() throws {
        let payload = Data("still waiting".utf8)
        let frame = IPCFraming.encode(payload)
        var reader = IPCFrameReader()

        // Feed everything except the last byte.
        let allButLast = frame.prefix(frame.count - 1)
        let frames = try reader.feed(Data(allButLast))
        XCTAssertEqual(frames, [], "must not yield a frame before every byte has arrived")
        XCTAssertGreaterThan(reader.pendingByteCount, 0)

        let final = try reader.feed(Data([frame.last!]))
        XCTAssertEqual(final, [payload])
    }

    func testMultipleFramesDeliveredInOneChunkAreAllExtractedInOrder() throws {
        let first = Data("first".utf8)
        let second = Data("second".utf8)
        var combined = IPCFraming.encode(first)
        combined.append(IPCFraming.encode(second))

        var reader = IPCFrameReader()
        let frames = try reader.feed(combined)

        XCTAssertEqual(frames, [first, second])
    }

    func testFrameSplitAcrossLengthPrefixBoundaryIsReassembled() throws {
        let payload = Data("length prefix split across two chunks".utf8)
        let frame = IPCFraming.encode(payload)
        var reader = IPCFrameReader()

        // Split inside the 4-byte length prefix itself (after 2 of 4 bytes).
        let firstChunk = frame.prefix(2)
        let secondChunk = frame.suffix(from: frame.startIndex + 2)

        let firstResult = try reader.feed(Data(firstChunk))
        XCTAssertEqual(firstResult, [])

        let secondResult = try reader.feed(Data(secondChunk))
        XCTAssertEqual(secondResult, [payload])
    }

    // MARK: - Over-limit frame

    func testOverLimitFrameThrowsBeforeBufferingPayload() {
        var reader = IPCFrameReader(maxPayloadBytes: 16)
        let oversizedPayload = Data(repeating: 0x41, count: 1024)
        let frame = IPCFraming.encode(oversizedPayload)

        XCTAssertThrowsError(try reader.feed(frame)) { error in
            guard case IPCFraming.FrameError.frameTooLarge(let declared, let limit) = error else {
                return XCTFail("Expected frameTooLarge, got \(error)")
            }
            XCTAssertEqual(declared, 1024)
            XCTAssertEqual(limit, 16)
        }
    }

    func testOverLimitDetectedFromLengthPrefixAloneWithoutWaitingForPayload() {
        var reader = IPCFrameReader(maxPayloadBytes: 16)
        // Only the 4-byte length prefix has arrived; none of the (oversized) payload has.
        var lengthOnly = Data()
        var length = UInt32(1_000_000).bigEndian
        lengthOnly.append(Data(bytes: &length, count: 4))

        XCTAssertThrowsError(try reader.feed(lengthOnly)) { error in
            guard case IPCFraming.FrameError.frameTooLarge(let declared, _) = error else {
                return XCTFail("Expected frameTooLarge, got \(error)")
            }
            XCTAssertEqual(declared, 1_000_000)
        }
    }

    func testExactlyAtLimitIsAccepted() throws {
        var reader = IPCFrameReader(maxPayloadBytes: 16)
        let payload = Data(repeating: 0x42, count: 16)
        let frame = IPCFraming.encode(payload)

        let frames = try reader.feed(frame)
        XCTAssertEqual(frames, [payload])
    }
}
