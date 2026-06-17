import SwiftUI
import CoreGraphics

struct AISettingsView: View {
    @AppStorage("ai_provider") private var providerStr: String = AIProviderType.xiaomiMimo.rawValue
    @AppStorage("ai_model") private var model: String = "mimo-v2.5"
    @AppStorage("ai_base_url") private var baseURL: String = ""
    @AppStorage("ai_plan") private var plan: String = "token"
    @AppStorage("ai_output_language") private var outputLanguage: String = "en"
    
    @State private var apiKey: String = ""
    @State private var showKeySavedToast = false
    
    let providers = [
        AIProviderType.xiaomiMimo,
        AIProviderType.openAI,
        AIProviderType.openRouter,
        AIProviderType.gemini,
        AIProviderType.claude
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("AI Configuration")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Customize how BerryShot connects to AI models.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 8)
                
                // Authentication Section
                VStack(alignment: .leading, spacing: 16) {
                    Label("Authentication", systemImage: "key.fill")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(spacing: 16) {
                        HStack {
                            Text("Provider")
                                .frame(width: 80, alignment: .leading)
                                .foregroundColor(.secondary)
                            Picker("", selection: $providerStr) {
                                ForEach(providers, id: \.rawValue) { provider in
                                    Text(provider.rawValue).tag(provider.rawValue)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(MenuPickerStyle())
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        HStack {
                            Text("API Key")
                                .frame(width: 80, alignment: .leading)
                                .foregroundColor(.secondary)
                            SecureField("Enter your secret key...", text: $apiKey)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .controlSize(.large)
                        }
                        
                        HStack {
                            Spacer()
                            if showKeySavedToast {
                                Label("Saved Securely", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.subheadline)
                                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                                    .padding(.trailing, 8)
                            }
                            Button(action: saveKey) {
                                Text("Save Key")
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 16)
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
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.1), lineWidth: 1))
                }
                
                // Model Config Section
                VStack(alignment: .leading, spacing: 16) {
                    Label("Model Settings", systemImage: "cpu")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(spacing: 16) {
                        HStack(alignment: .top) {
                            Text("Model")
                                .frame(width: 80, alignment: .leading)
                                .foregroundColor(.secondary)
                                .padding(.top, 6)
                            VStack(alignment: .leading, spacing: 4) {
                                TextField("e.g. gpt-4o", text: $model)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .controlSize(.large)
                                Text("Common models: mimo-v2.5, gpt-4o, claude-3-5-sonnet-20240620")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        HStack(alignment: .top) {
                            Text("Base URL")
                                .frame(width: 80, alignment: .leading)
                                .foregroundColor(.secondary)
                                .padding(.top, 6)
                            VStack(alignment: .leading, spacing: 4) {
                                TextField("Optional override...", text: $baseURL)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .controlSize(.large)
                                Text("Leave empty to use the provider's default endpoint.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        HStack {
                            Text("Language")
                                .frame(width: 80, alignment: .leading)
                                .foregroundColor(.secondary)
                            Picker("", selection: $outputLanguage) {
                                Text("🇺🇸 English").tag("en")
                                Text("🇻🇳 Vietnamese").tag("vi")
                                Text("🇯🇵 Japanese").tag("ja")
                            }
                            .labelsHidden()
                            .pickerStyle(MenuPickerStyle())
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        if providerStr == AIProviderType.xiaomiMimo.rawValue {
                            HStack {
                                Text("Plan")
                                    .frame(width: 80, alignment: .leading)
                                    .foregroundColor(.secondary)
                                Picker("", selection: $plan) {
                                    Text("Token-based").tag("token")
                                    Text("Subscription").tag("sub")
                                }
                                .labelsHidden()
                                .pickerStyle(SegmentedPickerStyle())
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.1), lineWidth: 1))
                }
                
                HStack {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.blue)
                    Text("API keys are saved securely in application preferences.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .center)
                
            }
            .padding(24)
        }
        .frame(minWidth: 450, minHeight: 550)
        .onAppear {
            loadKey()
        }
        .onChange(of: providerStr) {
            loadKey()
        }
    }
    
    private func loadKey() {
        if let data = KeychainHelper.shared.read(key: "berryshot_ai_key_\(providerStr)"),
           let key = String(data: data, encoding: .utf8) {
            apiKey = key
        } else {
            apiKey = ""
        }
    }
    
    private func saveKey() {
        if let data = apiKey.data(using: .utf8) {
            _ = KeychainHelper.shared.save(key: "berryshot_ai_key_\(providerStr)", data: data)
            withAnimation(.spring()) { showKeySavedToast = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeOut) { showKeySavedToast = false }
            }
        }
    }
}
