import SwiftUI
import AppKit

struct StorageSettingsView: View {
    @ObservedObject var config = StorageConfiguration.shared
    @State private var isGoogleSaved = false
    @State private var isCustomSaved = false
    @State private var isGuideExpanded = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Provider Selection
                VStack(alignment: .leading, spacing: 12) {
                    Label("Storage Provider", systemImage: "folder.fill")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(spacing: 12) {
                        HStack {
                            Text("Save to:")
                                .frame(width: 105, alignment: .leading)
                                .foregroundColor(.secondary)
                            Picker("", selection: $config.selectedProvider) {
                                ForEach(StorageProviderType.allCases) { provider in
                                    Text(LocalizedStringKey(provider.rawValue)).tag(provider)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(MenuPickerStyle())
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.1), lineWidth: 1))
                }
                
                // Local Directory Section
                VStack(alignment: .leading, spacing: 12) {
                    Label("Local Storage", systemImage: "macwindow")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(spacing: 12) {
                        TextField("Storage Directory:", text: $config.defaultLocalDirectory)
                            .disabled(true)
                        
                        HStack {
                            Text("Screenshots will be saved to this directory on your computer.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
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
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.1), lineWidth: 1))
                }
                
                // Google Drive Section
                VStack(alignment: .leading, spacing: 12) {
                    Label("Google Drive", systemImage: "icloud.fill")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(spacing: 12) {
                        HStack {
                            Text("Access Token:")
                                .frame(width: 105, alignment: .leading)
                                .foregroundColor(.secondary)
                            SecureField("Enter access token...", text: $config.googleDriveAccessToken)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .controlSize(.large)
                        }
                        
                        HStack {
                            Text("Refresh Token:")
                                .frame(width: 105, alignment: .leading)
                                .foregroundColor(.secondary)
                            SecureField("Enter refresh token...", text: $config.googleDriveRefreshToken)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .controlSize(.large)
                        }
                        
                        HStack {
                            Text("Auto-upload captures to Google Drive.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            if isGoogleSaved {
                                Label("Saved Securely", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.subheadline)
                            }
                            
                            Button(action: {
                                config.saveToKeychain()
                                withAnimation { isGoogleSaved = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                    withAnimation { isGoogleSaved = false }
                                }
                            }) {
                                Text("Save Credentials")
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .onContinuousHover { phase in
                                switch phase {
                                case .active: NSCursor.pointingHand.set()
                                case .ended: NSCursor.arrow.set()
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.1), lineWidth: 1))
                }
                
                // Custom Service API Section
                VStack(alignment: .leading, spacing: 12) {
                    Label("Custom Service API", systemImage: "network")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(spacing: 12) {
                        HStack {
                            Text("Endpoint URL:")
                                .frame(width: 105, alignment: .leading)
                                .foregroundColor(.secondary)
                            TextField("https://example.com/api/upload", text: $config.customEndpointURL)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .controlSize(.large)
                        }
                        
                        HStack(alignment: .top) {
                            Text("Callback URL:")
                                .frame(width: 105, alignment: .leading)
                                .foregroundColor(.secondary)
                                .padding(.top, 6)
                            VStack(alignment: .leading, spacing: 4) {
                                TextField("e.g. {json:url}", text: $config.customCallbackURL)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .controlSize(.large)
                                Text("Variable path inside JSON response to extract the final URL.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        HStack {
                            Text("Auth Type:")
                                .frame(width: 105, alignment: .leading)
                                .foregroundColor(.secondary)
                            Picker("", selection: $config.customAuthType) {
                                ForEach(CustomAuthType.allCases) { type in
                                    Text(LocalizedStringKey(type.rawValue)).tag(type)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(MenuPickerStyle())
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        if config.customAuthType == .accessToken {
                            HStack {
                                Text("Access Token:")
                                    .frame(width: 105, alignment: .leading)
                                    .foregroundColor(.secondary)
                                SecureField("Enter custom access token...", text: $config.customAccessToken)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .controlSize(.large)
                            }
                        } else {
                            HStack {
                                Text("API Key:")
                                    .frame(width: 105, alignment: .leading)
                                    .foregroundColor(.secondary)
                                SecureField("Enter custom API key...", text: $config.customAPIKey)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .controlSize(.large)
                            }
                            HStack {
                                Text("Access Key:")
                                    .frame(width: 105, alignment: .leading)
                                    .foregroundColor(.secondary)
                                SecureField("Enter custom access key...", text: $config.customAPISecret)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .controlSize(.large)
                            }
                        }
                        
                        HStack {
                            Spacer()
                            if isCustomSaved {
                                Label("Saved Securely", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.subheadline)
                            }
                            Button(action: {
                                config.saveToKeychain()
                                withAnimation { isCustomSaved = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                    withAnimation { isCustomSaved = false }
                                }
                            }) {
                                Text("Save Credentials")
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .onContinuousHover { phase in
                                switch phase {
                                case .active: NSCursor.pointingHand.set()
                                case .ended: NSCursor.arrow.set()
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.1), lineWidth: 1))
                }
                
                // Custom Service Guide
                VStack(alignment: .leading, spacing: 10) {
                    DisclosureGroup(isExpanded: $isGuideExpanded) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("When uploading captures, the application sends the binary file as multipart/form-data in this exact structure:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Text("""
                            curl -X POST "<Endpoint URL>" \\
                              -H "Authorization: Bearer <Token>" \\
                              -F "file=@Screenshot.png;type=image/png"
                            """)
                            .font(.system(.body, design: .monospaced))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                            
                            Text("Your server must accept this multipart/form-data upload, process it, and return a JSON payload. The 'Callback URL' field traverses the JSON payload to retrieve the image URL (e.g. value of data.url).")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 8)
                    } label: {
                        Label("API Integration Guide", systemImage: "info.circle.fill")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.1), lineWidth: 1))
            }
            .padding(16)
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
}
