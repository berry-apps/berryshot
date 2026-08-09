import CoreGraphics
import Foundation

/// A Codable, Sendable representation of a Core Graphics rectangle.
///
/// ScreenCaptureKit's window objects deliberately never cross the discovery
/// boundary. This value type is the geometry that can safely be retained by
/// UI, history, and (in a later work package) IPC clients.
public struct CGRectDTO: Codable, Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
    }

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

public struct ApplicationDescriptor: Identifiable, Codable, Hashable, Sendable {
    /// The bundle identifier is the application identity exposed to callers.
    public let id: String
    public let applicationName: String
    /// Observation metadata only. It must not be used as a durable identity.
    public let processID: Int32
    public let windowCount: Int
    public let isFrontmost: Bool

    public init(id: String, applicationName: String, processID: Int32, windowCount: Int, isFrontmost: Bool) {
        self.id = id
        self.applicationName = applicationName
        self.processID = processID
        self.windowCount = windowCount
        self.isFrontmost = isFrontmost
    }
}

public struct WindowDescriptor: Identifiable, Codable, Hashable, Sendable {
    /// A CGWindowID is valid only for the discovery snapshot that produced it.
    public let id: UInt32
    public let bundleIdentifier: String
    public let applicationName: String
    /// Observation metadata only. It is checked for staleness, not persisted as identity.
    public let processID: Int32
    public let title: String
    public let frameInScreenPoints: CGRectDTO
    public let isOnScreen: Bool
    public let isFrontmost: Bool

    public init(
        id: UInt32,
        bundleIdentifier: String,
        applicationName: String,
        processID: Int32,
        title: String,
        frameInScreenPoints: CGRectDTO,
        isOnScreen: Bool,
        isFrontmost: Bool = false
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.processID = processID
        self.title = title
        self.frameInScreenPoints = frameInScreenPoints
        self.isOnScreen = isOnScreen
        self.isFrontmost = isFrontmost
    }
}

public enum ApplicationCapturePolicy: String, Codable, Sendable {
    case frontmostWindow
    case allOnScreenWindows
}

public enum CaptureTarget: Codable, Sendable, Equatable {
    case display(displayID: UInt32)
    case region(displayID: UInt32, rect: CGRectDTO)
    case window(windowID: UInt32)
    case application(bundleIdentifier: String, policy: ApplicationCapturePolicy)
}

/// A plain record used to keep filtering and ordering deterministic and unit-testable.
public struct WindowDiscoveryRecord: Hashable, Sendable {
    public let windowID: UInt32
    public let bundleIdentifier: String?
    public let applicationName: String?
    public let processID: Int32
    public let title: String?
    public let frameInScreenPoints: CGRectDTO
    public let isOnScreen: Bool
    public let isFrontmost: Bool

    public init(
        windowID: UInt32,
        bundleIdentifier: String?,
        applicationName: String?,
        processID: Int32,
        title: String?,
        frameInScreenPoints: CGRectDTO,
        isOnScreen: Bool,
        isFrontmost: Bool
    ) {
        self.windowID = windowID
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.processID = processID
        self.title = title
        self.frameInScreenPoints = frameInScreenPoints
        self.isOnScreen = isOnScreen
        self.isFrontmost = isFrontmost
    }
}

public enum ApplicationWindowDiscovery {
    /// Windows below this size are control surfaces or transient layers, not useful captures.
    public static let minimumUsefulDimension: Double = 100

    /// `SCShareableContent` reports these as ordinary on-screen windows —
    /// full-display-sized, so they pass `minimumUsefulDimension` easily —
    /// but they are desktop backdrop layers, not anything a user can
    /// meaningfully select as a capture target. Confirmed via manual QA
    /// (`docs/tests/01.md` item 2): the app/window selector listed
    /// "Display 1 Backstop" and two `Dock`-owned entries ("Dock" /
    /// "Wallpaper-") alongside real application windows.
    private static let systemBackdropBundleIdentifiers: Set<String> = ["com.apple.dock"]

    public static func eligibleWindowDescriptors(
        from records: [WindowDiscoveryRecord],
        excludingBundleIdentifier ownBundleIdentifier: String?
    ) -> [WindowDescriptor] {
        records.compactMap { record in
            guard record.isOnScreen,
                  let bundleIdentifier = record.bundleIdentifier,
                  bundleIdentifier != ownBundleIdentifier,
                  !systemBackdropBundleIdentifiers.contains(bundleIdentifier),
                  record.frameInScreenPoints.width > minimumUsefulDimension,
                  record.frameInScreenPoints.height > minimumUsefulDimension else {
                return nil
            }

            return WindowDescriptor(
                id: record.windowID,
                bundleIdentifier: bundleIdentifier,
                applicationName: record.applicationName ?? bundleIdentifier,
                processID: record.processID,
                title: record.title ?? "",
                frameInScreenPoints: record.frameInScreenPoints,
                isOnScreen: record.isOnScreen,
                isFrontmost: record.isFrontmost
            )
        }
        .sorted(by: windowSort)
    }

    public static func applicationDescriptors(from windows: [WindowDescriptor]) -> [ApplicationDescriptor] {
        let groups = Dictionary(grouping: windows, by: \.bundleIdentifier)
        return groups.compactMap { bundleIdentifier, group in
            guard let first = group.first else { return nil }
            return ApplicationDescriptor(
                id: bundleIdentifier,
                applicationName: first.applicationName,
                processID: first.processID,
                windowCount: group.count,
                isFrontmost: group.contains(where: \.isFrontmost)
            )
        }
        .sorted(by: applicationSort)
    }

    public static func windows(for bundleIdentifier: String, in windows: [WindowDescriptor]) -> [WindowDescriptor] {
        windows.filter { $0.bundleIdentifier == bundleIdentifier }.sorted(by: windowSort)
    }

    private static func applicationSort(_ lhs: ApplicationDescriptor, _ rhs: ApplicationDescriptor) -> Bool {
        if lhs.isFrontmost != rhs.isFrontmost { return lhs.isFrontmost }
        let result = lhs.applicationName.localizedStandardCompare(rhs.applicationName)
        if result != .orderedSame { return result == .orderedAscending }
        return lhs.id < rhs.id
    }

    private static func windowSort(_ lhs: WindowDescriptor, _ rhs: WindowDescriptor) -> Bool {
        if lhs.isFrontmost != rhs.isFrontmost { return lhs.isFrontmost }
        let applicationResult = lhs.applicationName.localizedStandardCompare(rhs.applicationName)
        if applicationResult != .orderedSame { return applicationResult == .orderedAscending }
        let titleResult = lhs.title.localizedStandardCompare(rhs.title)
        if titleResult != .orderedSame { return titleResult == .orderedAscending }
        return lhs.id < rhs.id
    }
}
