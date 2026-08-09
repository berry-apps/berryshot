import SwiftUI

/// Shared across every Settings tab so the window's height cap tracks the
/// actual display instead of a number picked for one developer's monitor —
/// 700pt is enormous on a small laptop panel and cramped on a large one.
enum SettingsSizing {
    static var maxContentHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 900) * 0.8
    }
}

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
    // Deliberately no shared .frame() here: a single fixed size forced every
    // tab to the same height regardless of how much content it actually has
    // (previously 700pt, clipping-avoidance for the longest tab left every
    // shorter tab mostly empty). Each tab instead sets its own
    // `.frame(width: 550)` + `.frame(maxHeight: SettingsSizing.maxContentHeight)`
    // on its own ScrollView, so the window naturally resizes per tab to fit
    // that tab's content, capped at 80% of the actual screen height with
    // scroll as the fallback past that cap.
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
