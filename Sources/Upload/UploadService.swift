import Foundation

public protocol UploadServiceProtocol: Sendable {
    func uploadImage(fileURL: URL) async throws -> URL
}

public class MockUploadService: UploadServiceProtocol, @unchecked Sendable {
    public init() {}
    
    public func uploadImage(fileURL: URL) async throws -> URL {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Mock successful upload URL
        return URL(string: "https://mock.upload.com/\(fileURL.lastPathComponent)")!
    }
}
