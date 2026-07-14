import SwiftUI
import AppKit

struct LocalSettingsView: View {
    @ObservedObject var config = StorageConfiguration.shared
    
    var body: some View {
        Form {
            TextField("Storage Directory:", text: $config.defaultLocalDirectory)
                .disabled(true)
            
            HStack {
                Spacer()
                Button("Change Directory...") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    
                    if panel.runModal() == .OK {
                        config.defaultLocalDirectory = panel.url?.path ?? ""
                    }
                }
            }
            
            Text("Screenshots will be saved to this directory on your computer.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 450)
    }
}
