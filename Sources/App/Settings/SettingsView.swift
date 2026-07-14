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

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            StorageSettingsView()
                .tabItem {
                    Label("Storage", systemImage: "externaldrive.fill")
                }
            PrivacySettingsView()
                .tabItem {
                    Label("Privacy", systemImage: "hand.raised.fill")
                }
            AISettingsView()
                .tabItem {
                    Label("AI", systemImage: "sparkles")
                }
            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 550, height: 450)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            if let bundle = resourceBundle,
               let url = bundle.url(forResource: "AppIcon", withExtension: "png"),
               let iconImage = NSImage(contentsOf: url) {
                NSApp.applicationIconImage = iconImage
            }
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
