import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            LocalSettingsView()
                .tabItem {
                    Label("Local", systemImage: "macwindow")
                }
            CloudSettingsView()
                .tabItem {
                    Label("Cloud", systemImage: "icloud")
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
            if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
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
