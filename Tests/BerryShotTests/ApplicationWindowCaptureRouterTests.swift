import XCTest
@testable import BerryShot

final class ApplicationWindowCaptureRouterTests: XCTestCase {
    func testSelectedWindowRoutesOnlyTheSelectedDescriptor() {
        let descriptor = makeDescriptor(id: 1, title: "Selected")

        let route = ApplicationWindowCaptureRouter.route(for: .window(WindowInfo(descriptor: descriptor)))

        XCTAssertEqual(route, .selectedWindow(descriptor))
    }

    func testFrontmostApplicationRoutesOnlyTheDescriptorMarkedFrontmost() {
        let frontmost = makeDescriptor(id: 1, title: "Frontmost", frontmost: true)
        let second = makeDescriptor(id: 2, title: "Second")
        let application = makeApplication(windows: [frontmost, second])

        let route = ApplicationWindowCaptureRouter.route(
            for: .application(application, policy: .frontmostWindow)
        )

        XCTAssertEqual(route, .applicationWindow(frontmost))
    }

    func testAllApplicationWindowsRetainsEveryDescriptorWithoutSubstitution() {
        let first = makeDescriptor(id: 1, title: "First")
        let second = makeDescriptor(id: 2, title: "Second")
        let application = makeApplication(windows: [first, second])

        let route = ApplicationWindowCaptureRouter.route(
            for: .application(application, policy: .allOnScreenWindows)
        )

        XCTAssertEqual(route, .applicationWindows([first, second]))
    }

    func testFrontmostRouteIsUnavailableWhenDiscoveryDidNotMarkOne() {
        let application = makeApplication(windows: [makeDescriptor(id: 1, title: "Only")])

        let route = ApplicationWindowCaptureRouter.route(
            for: .application(application, policy: .frontmostWindow)
        )

        XCTAssertNil(route)
    }

    private func makeApplication(windows: [WindowDescriptor]) -> ApplicationInfo {
        ApplicationInfo(
            descriptor: ApplicationDescriptor(
                id: "com.example.alpha",
                applicationName: "Alpha",
                processID: 1,
                windowCount: windows.count,
                isFrontmost: windows.contains(where: \.isFrontmost)
            ),
            windows: windows.map(WindowInfo.init(descriptor:))
        )
    }

    private func makeDescriptor(id: UInt32, title: String, frontmost: Bool = false) -> WindowDescriptor {
        WindowDescriptor(
            id: id,
            bundleIdentifier: "com.example.alpha",
            applicationName: "Alpha",
            processID: 1,
            title: title,
            frameInScreenPoints: CGRectDTO(x: 0, y: 0, width: 800, height: 600),
            isOnScreen: true,
            isFrontmost: frontmost
        )
    }
}
