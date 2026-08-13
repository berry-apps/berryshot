import SwiftUI

private var resourceBundle: Bundle? {
    let candidates = [
        Bundle.main.bundlePath + "/Contents/Resources/BerryShot_BerryShot.bundle",
        Bundle.main.bundlePath + "/Contents/Resources/BerryShot_BerryShot_BerryShot.bundle"
    ]
    for path in candidates {
        if let bundle = Bundle(path: path) { return bundle }
    }
    return nil
}

struct AboutSettingsView: View {
    @StateObject private var storeManager = StoreManager.shared
    
    @State private var isCheckingForUpdates = false
    @State private var updateMessage: String?
    @State private var updateUrl: String?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // App Icon
                if let bundle = resourceBundle,
                   let url = bundle.url(forResource: "AppIcon", withExtension: "png"),
                   let nsImage = NSImage(contentsOf: url) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .frame(width: 96, height: 96)
                } else {
                    Image(systemName: "camera.viewfinder")
                        .resizable()
                        .frame(width: 64, height: 64)
                        .foregroundColor(.accentColor)
                }
                
                VStack(spacing: 6) {
                    Text("BerryShot")
                        .font(.system(size: 28, weight: .bold))
                    
                    Text("Version 2.1.0")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if let msg = updateMessage {
                        if let urlString = updateUrl, let url = URL(string: urlString) {
                            Link(msg, destination: url)
                                .font(.caption)
                                .foregroundColor(.green)
                                .buttonStyle(.plain)
                        } else {
                            Text(msg)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Button(action: checkForUpdates) {
                            if isCheckingForUpdates {
                                ProgressView().controlSize(.mini)
                            } else {
                                Text("Check for Updates...")
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                        .font(.caption)
                        .disabled(isCheckingForUpdates)
                    }
                }
                
                VStack(spacing: 6) {
                    Text("BerryShot is a fast, minimal macOS screen capture tool.")
                    Text("Capture, save, and share your screen with zero friction.")
                    
                    Text("Built for speed and simplicity.")
                        .padding(.top, 4)
                    
                    HStack(spacing: 4) {
                        Text("Website:")
                            .foregroundColor(.secondary)
                        Link("https://shot.berryhub.app", destination: URL(string: "https://shot.berryhub.app")!)
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                    }
                    .padding(.top, 4)
                    
                    HStack(spacing: 4) {
                        Text("Support:")
                            .foregroundColor(.secondary)
                        Link("info@notex.work", destination: URL(string: "mailto:info@notex.work")!)
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                    }
                    .padding(.top, 4)
                }
                .multilineTextAlignment(.center)
                .font(.body)
                
                Divider()
                    .frame(width: 280)
                
                VStack(spacing: 8) {
                    Text("Support BerryShot")
                        .font(.headline)
                        .padding(.top, 8)
                    
                    Text("If you find BerryShot useful, consider buying me a coffee ☕️")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        if storeManager.donateProduct != nil {
                            Task { await storeManager.purchase() }
                        } else {
                            if let url = URL(string: "https://ko-fi.com/dautay") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            if storeManager.isPurchasing {
                                ProgressView().controlSize(.small)
                            }
                            Text("Donate \(storeManager.donateProduct?.displayPrice ?? "$10.00")")
                                .font(.subheadline)
                        }
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(storeManager.isPurchasing)
                    
                    if storeManager.showThankYou {
                        Text("💖 Thank you so much for your support!")
                            .foregroundColor(.green)
                            .font(.caption)
                            .padding(.top, 4)
                    }
                }
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 40)
            .padding(.top, 40)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: SettingsContentHeightKey.self, value: geo.size.height)
                }
            )
        }
        .frame(width: 550)
        .frame(maxHeight: SettingsSizing.maxContentHeight)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: SettingsViewportHeightKey.self, value: geo.size.height)
            }
        )
    }

    private func checkForUpdates() {
        isCheckingForUpdates = true
        updateMessage = nil
        updateUrl = nil
        
        Task {
            do {
                let url = URL(string: "https://download-shot.berryhub.app/version.json")!
                let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                
                struct UpdateInfo: Decodable {
                    let version: String
                    let url: String
                }
                
                let info = try JSONDecoder().decode(UpdateInfo.self, from: data)
                let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.3"
                
                await MainActor.run {
                    isCheckingForUpdates = false
                    if info.version != currentVersion {
                        updateMessage = "Update available (v\(info.version)). Click to download."
                        updateUrl = info.url
                    } else {
                        updateMessage = "You are up to date!"
                    }
                }
            } catch {
                await MainActor.run {
                    isCheckingForUpdates = false
                    updateMessage = "Failed to check for updates."
                }
            }
        }
    }
}
