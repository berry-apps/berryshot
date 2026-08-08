import Foundation

/// Wire-level permission snapshot. Field shape follows the `permissions_status`
/// tool output documented in `05-mcp-server-contract.md` section 3; the exact
/// external JSON key casing for the MCP tool result is a WP7 concern, so this
/// type intentionally uses ordinary Swift `Codable` synthesis rather than
/// pinning `snake_case` keys this early.
public struct PermissionsStatusDTO: Codable, Sendable, Equatable {
    public enum ScreenCaptureStatus: String, Codable, Sendable {
        case granted
        case denied
        case restartRequired = "restart_required"
        case unknown
    }

    public enum AccessibilityStatus: String, Codable, Sendable {
        case granted
        case denied
        case notRequired = "not_required"
    }

    public let screenCapture: ScreenCaptureStatus
    public let accessibility: AccessibilityStatus
    public let berryshotRunning: Bool
    public let brokerProtocolVersion: UInt16

    public init(
        screenCapture: ScreenCaptureStatus,
        accessibility: AccessibilityStatus,
        berryshotRunning: Bool,
        brokerProtocolVersion: UInt16
    ) {
        self.screenCapture = screenCapture
        self.accessibility = accessibility
        self.berryshotRunning = berryshotRunning
        self.brokerProtocolVersion = brokerProtocolVersion
    }
}

/// Bounded, sanitized application summary. Never carries an icon or
/// thumbnail (`05-mcp-server-contract.md` section 3: "Do not return icons or
/// thumbnails by default").
public struct ApplicationSummaryDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let applicationName: String
    public let processID: Int32
    public let isFrontmost: Bool
    public let windowCount: Int

    public init(id: String, applicationName: String, processID: Int32, isFrontmost: Bool, windowCount: Int) {
        self.id = id
        self.applicationName = applicationName
        self.processID = processID
        self.isFrontmost = isFrontmost
        self.windowCount = windowCount
    }
}

/// Bounded, sanitized window summary. Deliberately omits geometry, preview
/// bytes, and any live capture handle; WP6 only needs enough for an agent to
/// choose a window, not to render or capture one yet (that is WP7).
public struct WindowSummaryDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: UInt32
    public let bundleIdentifier: String
    public let applicationName: String
    public let processID: Int32
    public let title: String
    public let isOnScreen: Bool
    public let isFrontmost: Bool

    public init(
        id: UInt32,
        bundleIdentifier: String,
        applicationName: String,
        processID: Int32,
        title: String,
        isOnScreen: Bool,
        isFrontmost: Bool
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.processID = processID
        self.title = title
        self.isOnScreen = isOnScreen
        self.isFrontmost = isFrontmost
    }
}

public struct ListApplicationsRequest: Codable, Sendable, Equatable {
    public let query: String?
    public let limit: Int
    public let cursor: String?

    public init(query: String? = nil, limit: Int = 50, cursor: String? = nil) {
        self.query = query
        self.limit = limit
        self.cursor = cursor
    }
}

public struct ListApplicationsResult: Codable, Sendable, Equatable {
    public let applications: [ApplicationSummaryDTO]
    public let nextCursor: String?

    public init(applications: [ApplicationSummaryDTO], nextCursor: String? = nil) {
        self.applications = applications
        self.nextCursor = nextCursor
    }
}

public struct ListWindowsRequest: Codable, Sendable, Equatable {
    public let bundleIdentifier: String
    public let limit: Int
    public let cursor: String?

    public init(bundleIdentifier: String, limit: Int = 50, cursor: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.limit = limit
        self.cursor = cursor
    }
}

public struct ListWindowsResult: Codable, Sendable, Equatable {
    public let windows: [WindowSummaryDTO]
    public let nextCursor: String?

    public init(windows: [WindowSummaryDTO], nextCursor: String? = nil) {
        self.windows = windows
        self.nextCursor = nextCursor
    }
}
