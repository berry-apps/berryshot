import XCTest
@testable import BerryShot

final class ApplicationDiscoveryTests: XCTestCase {
    func testEligibleWindowsExcludeOwnAppMissingBundleAndWindowsAtOrBelowMinimumDimension() {
        let records = [
            record(id: 1, bundle: "com.berryshot", name: "BerryShot", width: 800, height: 600),
            record(id: 2, bundle: nil, name: nil, width: 800, height: 600),
            record(id: 3, bundle: "com.example.small", name: "Small", width: 99, height: 600),
            record(id: 4, bundle: "com.example.exact-width", name: "Exact Width", width: 100, height: 600),
            record(id: 5, bundle: "com.example.exact-height", name: "Exact Height", width: 800, height: 100),
            record(id: 6, bundle: "com.example.valid", name: "Valid", width: 800, height: 600)
        ]

        let actual = ApplicationWindowDiscovery.eligibleWindowDescriptors(
            from: records,
            excludingBundleIdentifier: "com.berryshot"
        )

        XCTAssertEqual(actual.map(\.id), [6])
    }

    func testEligibleWindowsExcludeDockOwnedDesktopBackdropLayers() {
        let records = [
            record(id: 1, bundle: "com.apple.dock", name: nil, width: 2560, height: 1440),
            record(id: 2, bundle: "com.apple.dock", name: "Dock", width: 2560, height: 1440),
            record(id: 3, bundle: "com.example.real", name: "Real App", width: 800, height: 600)
        ]

        let actual = ApplicationWindowDiscovery.eligibleWindowDescriptors(
            from: records,
            excludingBundleIdentifier: nil
        )

        XCTAssertEqual(actual.map(\.id), [3], "Display 1 Backstop / Dock Wallpaper- entries must not appear as capturable windows")
    }

    func testApplicationsGroupEligibleWindowsAndSortFrontmostFirst() {
        let windows = [
            descriptor(id: 3, bundle: "com.zeta", name: "Zeta", title: "B"),
            descriptor(id: 2, bundle: "com.alpha", name: "Alpha", title: "B", frontmost: true),
            descriptor(id: 1, bundle: "com.alpha", name: "Alpha", title: "A")
        ]

        let applications = ApplicationWindowDiscovery.applicationDescriptors(from: windows)

        XCTAssertEqual(applications.map(\.id), ["com.alpha", "com.zeta"])
        XCTAssertEqual(applications.first?.windowCount, 2)
        XCTAssertEqual(applications.first?.isFrontmost, true)
    }

    func testWindowsSortFrontmostThenApplicationThenTitleDeterministically() {
        let windows = [
            descriptor(id: 4, bundle: "com.beta", name: "Beta", title: "Z"),
            descriptor(id: 3, bundle: "com.alpha", name: "Alpha", title: "Z"),
            descriptor(id: 2, bundle: "com.alpha", name: "Alpha", title: "A"),
            descriptor(id: 1, bundle: "com.zeta", name: "Zeta", title: "A", frontmost: true)
        ]

        let actual = ApplicationWindowDiscovery.eligibleWindowDescriptors(
            from: windows.map(record(from:)),
            excludingBundleIdentifier: nil
        )

        XCTAssertEqual(actual.map(\.id), [1, 2, 3, 4])
    }

    private func record(id: UInt32, bundle: String?, name: String?, width: Double, height: Double, frontmost: Bool = false) -> WindowDiscoveryRecord {
        WindowDiscoveryRecord(
            windowID: id,
            bundleIdentifier: bundle,
            applicationName: name,
            processID: Int32(id),
            title: "Window \(id)",
            frameInScreenPoints: CGRectDTO(x: 0, y: 0, width: width, height: height),
            isOnScreen: true,
            isFrontmost: frontmost
        )
    }

    private func descriptor(id: UInt32, bundle: String, name: String, title: String, frontmost: Bool = false) -> WindowDescriptor {
        WindowDescriptor(
            id: id,
            bundleIdentifier: bundle,
            applicationName: name,
            processID: Int32(id),
            title: title,
            frameInScreenPoints: CGRectDTO(x: 0, y: 0, width: 800, height: 600),
            isOnScreen: true,
            isFrontmost: frontmost
        )
    }

    private func record(from descriptor: WindowDescriptor) -> WindowDiscoveryRecord {
        WindowDiscoveryRecord(
            windowID: descriptor.id,
            bundleIdentifier: descriptor.bundleIdentifier,
            applicationName: descriptor.applicationName,
            processID: descriptor.processID,
            title: descriptor.title,
            frameInScreenPoints: descriptor.frameInScreenPoints,
            isOnScreen: descriptor.isOnScreen,
            isFrontmost: descriptor.isFrontmost
        )
    }
}
