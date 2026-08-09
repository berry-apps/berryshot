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

    @State private var scrollShortcut: Shortcut = {
        if let data = UserDefaults.standard.data(forKey: "scrollCaptureShortcut"),
           let decoded = try? JSONDecoder().decode(Shortcut.self, from: data) {
            return decoded
        }
        return Shortcut.defaultScrollShortcut
    }()

    @State private var appWindowShortcut: Shortcut = {
        if let data = UserDefaults.standard.data(forKey: "appWindowCaptureShortcut"),
           let decoded = try? JSONDecoder().decode(Shortcut.self, from: data) {
            return decoded
        }
        return Shortcut.defaultAppWindowCaptureShortcut
    }()

    @State private var launchAtLogin = false

    @State private var toolbarPosition: ToolbarPosition = {
        if let raw = UserDefaults.standard.string(forKey: "toolbarPosition"),
           let pos = ToolbarPosition(rawValue: raw) {
            return pos
        }
        return .bottom
    }()

    var body: some View {
        ScrollView {
            Form {
                Section(header: Text("System").font(.headline)) {
                    Toggle("Launch at login", isOn: $launchAtLogin)
                }

                Divider().padding(.vertical, 8)

                Section(header: Text("Capture").font(.headline)) {
                    // Fixed label width (matching the longest label below) so
                    // every value control in this section starts at the same
                    // x-offset instead of trailing whichever label happens to
                    // be shortest — Form's own automatic alignment doesn't
                    // apply here since these are plain HStacks, not
                    // LabeledContent/Form-native rows.
                    HStack {
                        Text("Capture Shortcut:")
                            .frame(width: 220, alignment: .leading)
                        ShortcutRecorderView(shortcut: $shortcut, defaultsKey: "captureShortcut")
                            .frame(width: 150, height: 24)
                    }
                    HStack {
                        Text("Scroll Capture Shortcut:")
                            .frame(width: 220, alignment: .leading)
                        ShortcutRecorderView(shortcut: $scrollShortcut, defaultsKey: "scrollCaptureShortcut")
                            .frame(width: 150, height: 24)
                    }
                    HStack {
                        Text("Capture App or Window Shortcut:")
                            .frame(width: 220, alignment: .leading)
                        ShortcutRecorderView(shortcut: $appWindowShortcut, defaultsKey: "appWindowCaptureShortcut")
                            .frame(width: 150, height: 24)
                    }
                    HStack {
                        Text("Toolbar Position:")
                            .frame(width: 220, alignment: .leading)
                        Picker("", selection: $toolbarPosition) {
                            ForEach(ToolbarPosition.allCases, id: \.self) { position in
                                Text(position.displayName).tag(position)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 220)
                    }
                    .onChange(of: toolbarPosition) { _, newValue in
                        UserDefaults.standard.set(newValue.rawValue, forKey: "toolbarPosition")
                    }
                    Text("Where the floating annotation toolbar appears relative to your capture selection. Dragging it manually during a capture overrides this until you start a new one.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider().padding(.vertical, 8)

                Section(header: Text("After Capture").font(.headline)) {
                    // "Default Action:" is a manual label above the picker
                    // rather than the Picker's own title — Form's automatic
                    // label-column alignment doesn't handle a .radioGroup
                    // picker's stacked, icon-bearing options well, and threw
                    // the whole page's label column out of alignment.
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Default Action:")
                        Picker("", selection: $config.selectedProvider) {
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
                        .labelsHidden()

                        Text("When clicking the Complete button (Checkmark), the application will perform this action.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(20)
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
