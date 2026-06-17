import Foundation

public class UploadServiceFactory {
    public static func currentService() async -> any UploadServiceProtocol {
        let provider = await StorageConfiguration.shared.selectedProvider
        switch provider {
        case .local:
            return LocalUploadService()
        case .googleDrive:
            return GoogleDriveUploadService()
        case .custom:
            return CustomUploadService()
        }
    }
}
