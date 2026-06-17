import Foundation
import Cocoa

public final class LocalUploadService: UploadServiceProtocol, Sendable {
    public init() {}
    
    public func uploadImage(fileURL: URL) async throws -> URL {
        let config = await StorageConfiguration.shared
        let defaultDirString = await config.defaultLocalDirectory
        
        let targetDir: URL
        if !defaultDirString.isEmpty {
            targetDir = URL(fileURLWithPath: defaultDirString)
        } else {
            let fileManager = FileManager.default
            let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            targetDir = appSupportDir.appendingPathComponent("BerryShot", isDirectory: true)
        }
        
        if !FileManager.default.fileExists(atPath: targetDir.path) {
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true, attributes: nil)
        }
        
        let destinationURL = targetDir.appendingPathComponent(fileURL.lastPathComponent)
        
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: fileURL, to: destinationURL)
        
        return destinationURL
    }
}
