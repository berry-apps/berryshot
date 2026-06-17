import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @ObservedObject var config = StorageConfiguration.shared
    
    @State private var shortcut: Shortcut = {
        if let data = UserDefaults.standard.data(forKey: "captureShortcut"),
           let decoded = try? JSONDecoder().decode(Shortcut.self, from: data) {
            return decoded
        }
        return Shortcut.defaultShortcut
    }()
    
    @State private var launchAtLogin = false
    
    var body: some View {
        Form {
            Section(header: Text("System").font(.headline)) {
                Toggle("Launch at login", isOn: $launchAtLogin)
            }
            
            Divider().padding(.vertical, 8)
            
            Section(header: Text("Capture").font(.headline)) {
                HStack {
                    Text("Capture Shortcut:")
                    ShortcutRecorderView(shortcut: $shortcut)
                        .frame(width: 150, height: 24)
                }
            }
            
            Divider().padding(.vertical, 8)
            
            Section(header: Text("After Capture").font(.headline)) {
                Picker("Default Action:", selection: $config.selectedProvider) {
                    ForEach(StorageProviderType.allCases) { provider in
                        Label {
                            Text(LocalizedStringKey(provider.rawValue))
                        } icon: {
                            Image(systemName: provider.icon)
                                .foregroundColor(.accentColor)
                        }
                        .tag(provider)
                    }
                }
                .pickerStyle(.radioGroup)
                
                Text("When clicking the Complete button (Checkmark), the application will perform this action.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .frame(width: 450)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .onChange(of: launchAtLogin) { oldValue, newValue in
            updateLaunchAtLogin(enabled: newValue)
        }
    }
    
    private func updateLaunchAtLogin(enabled: Bool) {
        let service = SMAppService.mainApp
        if enabled {
            if service.status != .enabled {
                do {
                    try service.register()
                    print("Launch at login enabled")
                } catch {
                    print("Failed to register launch at login: \(error)")
                }
            }
        } else {
            if service.status == .enabled {
                do {
                    try service.unregister()
                    print("Launch at login disabled")
                } catch {
                    print("Failed to unregister launch at login: \(error)")
                }
            }
        }
    }
}
