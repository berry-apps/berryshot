import Foundation
import AppKit

public final class UpdateManager: Sendable {
    public static let shared = UpdateManager()
    private init() {}
    
    struct UpdateInfo: Decodable {
        let version: String
        let url: String
    }
    
    public func checkForUpdates(showUI: Bool = true) async {
        do {
            let url = URL(string: "https://notex.work/assets/version.json")!
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            
            let info = try JSONDecoder().decode(UpdateInfo.self, from: data)
            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.3"
            
            await MainActor.run {
                if info.version != currentVersion {
                    let alert = NSAlert()
                    alert.icon = NSApplication.shared.applicationIconImage ?? NSImage(named: "AppIcon")
                    alert.messageText = "Update Available"
                    alert.informativeText = "Version \(info.version) is available. Would you like to download it now?"
                    alert.addButton(withTitle: "Download")
                    alert.addButton(withTitle: "Cancel")
                    
                    if alert.runModal() == .alertFirstButtonReturn {
                        if let downloadUrl = URL(string: info.url) {
                            NSWorkspace.shared.open(downloadUrl)
                        }
                    }
                } else if showUI {
                    let alert = NSAlert()
                    alert.icon = NSApplication.shared.applicationIconImage ?? NSImage(named: "AppIcon")
                    alert.messageText = "Up to Date"
                    alert.informativeText = "BerryShot is currently up to date (Version \(currentVersion))."
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        } catch {
            if showUI {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.icon = NSApplication.shared.applicationIconImage ?? NSImage(named: "AppIcon")
                    alert.messageText = "Update Check Failed"
                    alert.informativeText = "Failed to check for updates: \(error.localizedDescription)"
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }
}
