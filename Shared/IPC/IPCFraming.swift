import Foundation

/// Wire framing shared by the GUI broker server and the helper's IPC
/// client: a 4-byte big-endian length prefix followed by exactly that many
/// bytes of JSON payload. Both sides reject a frame whose declared length
/// exceeds ``IPCProtocol/maxFramePayloadBytes`` before reading the payload,
/// so neither peer can be forced to buffer an unbounded amount of data
/// (`05-mcp-server-contract.md` section 7: "Length-prefixed frames; maximum
/// request/response metadata size defined centrally").
///
/// Byte packing is done manually (no `withUnsafeBytes { $0.load(as:) }`)
/// because `Data`'s storage is not guaranteed to be 4-byte aligned; loading
/// a `UInt32` directly from an arbitrary offset would be undefined
/// behavior.
public enum IPCFraming {
    public enum FrameError: Error, Equatable, Sendable {
        case frameTooLarge(declaredLength: Int, limit: Int)
    }

    /// Prepends the 4-byte big-endian length prefix to `payload`.
    public static func encode(_ payload: Data) -> Data {
        let length = UInt32(payload.count)
        var frame = Data(capacity: 4 + payload.count)
        frame.append(UInt8((length >> 24) & 0xFF))
        frame.append(UInt8((length >> 16) & 0xFF))
        frame.append(UInt8((length >> 8) & 0xFF))
        frame.append(UInt8(length & 0xFF))
        frame.append(payload)
        return frame
    }
}

/// Incremental reader that accepts arbitrarily fragmented byte chunks (as a
/// real socket delivers them — one byte at a time in the worst case) and
/// yields complete frame payloads only once every byte of a frame has
/// arrived. Not thread-safe by itself; a caller must serialize access to
/// one reader per connection (`BrokerIPCServer` and `IPCClient` each keep
/// one reader per connection, touched only from that connection's own
/// serialized context).
public struct IPCFrameReader: Sendable {
    private var buffer = Data()
    public let maxPayloadBytes: Int

    public init(maxPayloadBytes: Int = IPCProtocol.maxFramePayloadBytes) {
        self.maxPayloadBytes = maxPayloadBytes
    }

    /// Appends newly received bytes and returns zero or more complete frame
    /// payloads that are now fully buffered, in arrival order.
    ///
    /// Throws `.frameTooLarge` the instant a length prefix advertises more
    /// than `maxPayloadBytes` — before any of that oversized payload is
    /// buffered. Callers must close the connection on this error; the
    /// reader does not attempt to resynchronize with the stream, because
    /// there is no reliable way to know where the oversized frame ends
    /// without reading (and buffering) the very bytes this check exists to
    /// avoid buffering.
    public mutating func feed(_ chunk: Data) throws -> [Data] {
        buffer.append(chunk)
        var frames: [Data] = []
        while true {
            guard buffer.count >= 4 else { break }
            let start = buffer.startIndex
            let length = readUInt32BE(buffer, at: start)
            if length > maxPayloadBytes {
                throw IPCFraming.FrameError.frameTooLarge(declaredLength: length, limit: maxPayloadBytes)
            }
            guard buffer.count >= 4 + length else { break }
            let payloadStart = start + 4
            let payloadEnd = payloadStart + length
            frames.append(buffer.subdata(in: payloadStart..<payloadEnd))
            buffer.removeSubrange(start..<payloadEnd)
        }
        return frames
    }

    /// Bytes currently buffered while waiting for the rest of a frame.
    /// Exposed only for tests confirming a reader does not silently drop or
    /// duplicate partially-delivered bytes.
    public var pendingByteCount: Int { buffer.count }

    private func readUInt32BE(_ data: Data, at offset: Int) -> Int {
        let b0 = Int(data[offset])
        let b1 = Int(data[offset + 1])
        let b2 = Int(data[offset + 2])
        let b3 = Int(data[offset + 3])
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    }
}
