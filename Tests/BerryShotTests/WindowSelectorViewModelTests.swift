import XCTest
@testable import BerryShot

@MainActor
final class WindowSelectorViewModelTests: XCTestCase {
    func testLoadsDescriptorOnlyListingsFromDiscoveryBoundary() async {
        let first = descriptor(id: 1, name: "Alpha", title: "First")
        let second = descriptor(id: 2, name: "Beta", title: "Second")
        let discovery = RecordingWindowDiscovery(result: .success([first, second]))
        let viewModel = WindowSelectorViewModel(windowDiscovery: discovery)

        await viewModel.loadWindows()

        XCTAssertEqual(discovery.callCount, 1)
        XCTAssertEqual(viewModel.windows.map(\.id), [1, 2])
        XCTAssertEqual(viewModel.windows.map(\.descriptor), [first, second])
        XCTAssertNil(viewModel.errorMessage)
    }

    func testDiscoveryFailureShowsErrorWithoutListingWindows() async {
        let discovery = RecordingWindowDiscovery(result: .failure(TestError.failed))
        let viewModel = WindowSelectorViewModel(windowDiscovery: discovery)

        await viewModel.loadWindows()

        XCTAssertEqual(discovery.callCount, 1)
        XCTAssertTrue(viewModel.windows.isEmpty)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    private func descriptor(id: UInt32, name: String, title: String) -> WindowDescriptor {
        WindowDescriptor(
            id: id,
            bundleIdentifier: "com.example.\(name.lowercased())",
            applicationName: name,
            processID: Int32(id),
            title: title,
            frameInScreenPoints: CGRectDTO(x: 0, y: 0, width: 800, height: 600),
            isOnScreen: true
        )
    }

    private enum TestError: LocalizedError {
        case failed
    }
}

@MainActor
private final class RecordingWindowDiscovery: WindowDiscovering {
    private let result: Result<[WindowDescriptor], Error>
    private(set) var callCount = 0

    init(result: Result<[WindowDescriptor], Error>) {
        self.result = result
    }

    func discoverWindows() async throws -> [WindowDescriptor] {
        callCount += 1
        return try result.get()
    }
}
