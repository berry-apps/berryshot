import Foundation

/// Constants shared verbatim by the GUI's `CaptureBroker`/`BrokerIPCServer`
/// and the `BerryShotMCP` helper's `IPCClient`. Both sides must agree on
/// these values without any runtime negotiation; a mismatch on
/// ``currentVersion`` causes the connection to be rejected outright rather
/// than silently interpreted.
///
/// See `02-target-architecture.md` section 6 and `05-mcp-server-contract.md`
/// section 7 for the contract this encodes.
public enum IPCProtocol {
    /// Bumped whenever the `BrokerRequest`/`BrokerResponse`/`BrokerOperation`
    /// wire shape changes in a way an older or newer peer cannot safely
    /// interpret. Both the GUI and the helper compare this value exactly;
    /// there is no negotiation.
    public static let currentVersion: UInt16 = 1

    /// Hard ceiling on one length-prefixed frame's payload (not counting the
    /// 4-byte length prefix itself). Routine IPC never carries image bytes
    /// (`02-target-architecture.md` section 4: "Artifact bytes cross process
    /// boundaries only on explicit preview/resource reads, not in
    /// window-list responses"), so this only needs to hold bounded JSON
    /// metadata for a bounded number of applications/windows, never pixel
    /// data. A peer that advertises a longer frame is rejected before any of
    /// that payload is read into memory.
    public static let maxFramePayloadBytes: Int = 1 * 1024 * 1024

    /// Number of cryptographically random bytes used to generate a
    /// per-launch session token (`05-mcp-server-contract.md` section 7:
    /// "App-generated random session token and bounded token lifetime").
    public static let sessionTokenByteCount: Int = 32

    /// Bounds enforced on a caller-supplied `deadline` so a client cannot
    /// ask the broker to keep a request enqueued indefinitely, matching the
    /// `deadline_ms` bounds documented for capture tools in
    /// `05-mcp-server-contract.md` section 3.
    public static let minDeadlineMilliseconds: Int = 1_000
    public static let maxDeadlineMilliseconds: Int = 60_000

    /// Bound on `CaptureBroker`'s internal FIFO queue. Requests beyond this
    /// depth are rejected with `.rateLimited` instead of growing memory
    /// without limit (`08-implementation-work-packages.md` WP6 task 3:
    /// "GUI `CaptureBroker` actor with bounded queue and cancellation").
    public static let maxQueueDepth: Int = 32

    /// Lifetime of a broker descriptor/session token from the moment the
    /// GUI writes `broker.json`. The GUI rotates both the token and the
    /// socket path after restart/re-enable
    /// (`05-mcp-server-contract.md` section 7).
    public static let descriptorLifetime: TimeInterval = 60 * 60 * 12
}
