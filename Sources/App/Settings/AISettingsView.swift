import SwiftUI
import CoreGraphics

struct AISettingsView: View {
    // AI provider (for image/doc generation)
    @AppStorage("ai_provider") private var providerStr: String = AIProviderType.xiaomiMimo.rawValue
    @AppStorage("ai_model") private var model: String = "mimo-v2.5"
    @AppStorage("ai_base_url") private var baseURL: String = ""
    @AppStorage("ai_plan") private var plan: String = "token"
    @AppStorage("ai_output_language") private var outputLanguage: String = "en"

    // Live transcription settings
    @AppStorage("transcription_provider") private var transcriptionProvider: String = ""
    @AppStorage("transcription_language") private var transcriptionLanguage: String = "vi"
    @AppStorage("transcription_model") private var transcriptionModel: String = ""
    @AppStorage("transcription_base_url") private var transcriptionBaseURL: String = ""

    @State private var apiKey: String = ""
    @State private var showKeySavedToast = false
    @State private var transcriptionKey: String = ""
    @State private var showTranscriptionKeySaved = false

    let providers = [
        AIProviderType.xiaomiMimo,
        AIProviderType.openAI,
        AIProviderType.openRouter,
        AIProviderType.gemini,
        AIProviderType.claude
    ]

    private var selectedTranscriptionProvider: TranscriptionProviderType? {
        TranscriptionProviderType(rawValue: transcriptionProvider)
    }

    private var transcriptionKeychainKey: String {
        switch selectedTranscriptionProvider {
        case .deepgram: return "berryshot_deepgram_key"
        case .openaiRealtime: return "berryshot_whisper_key"
        case nil: return ""
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("AI Configuration")
                        .font(.title2).fontWeight(.semibold)
                    Text("Customize how BerryShot connects to AI models.")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                .padding(.bottom, 8)

                // ── AI Provider (for image analysis / docs) ──
                settingsSection(label: "Authentication", icon: "key.fill") {
                    VStack(spacing: 16) {
                        row(label: "Provider") {
                            Picker("", selection: $providerStr) {
                                ForEach(providers, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        row(label: "API Key") {
                            SecureField("Enter your secret key...", text: $apiKey)
                                .textFieldStyle(.roundedBorder).controlSize(.large)
                        }
                        HStack {
                            Spacer()
                            if showKeySavedToast {
                                Label("Saved Securely", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green).font(.subheadline)
                                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                                    .padding(.trailing, 8)
                            }
                            saveButton("Save Key", action: saveKey)
                        }
                    }
                }

                // ── Model Settings ──
                settingsSection(label: "Model Settings", icon: "cpu") {
                    VStack(spacing: 16) {
                        row(label: "Model") {
                            VStack(alignment: .leading, spacing: 4) {
                                TextField("e.g. gpt-4o", text: $model)
                                    .textFieldStyle(.roundedBorder).controlSize(.large)
                                Text("Common: mimo-v2.5, gpt-4o, claude-3-5-sonnet-20240620")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                        row(label: "Base URL") {
                            VStack(alignment: .leading, spacing: 4) {
                                TextField("Optional override...", text: $baseURL)
                                    .textFieldStyle(.roundedBorder).controlSize(.large)
                                Text("Leave empty to use the provider's default endpoint.")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                        row(label: "Language") {
                            Picker("", selection: $outputLanguage) {
                                Text("🇺🇸 English").tag("en")
                                Text("🇻🇳 Vietnamese").tag("vi")
                                Text("🇯🇵 Japanese").tag("ja")
                            }
                            .labelsHidden().pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if providerStr == AIProviderType.xiaomiMimo.rawValue {
                            row(label: "Plan") {
                                Picker("", selection: $plan) {
                                    Text("Token-based").tag("token")
                                    Text("Subscription").tag("sub")
                                }
                                .labelsHidden().pickerStyle(.segmented)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }

                // ── Live Transcription ──
                settingsSection(label: "Live Transcription", icon: "waveform.circle") {
                    VStack(spacing: 16) {
                        Text("Real-time speech recognition for Live Meeting Notes. Supports Vietnamese, English, Japanese... Configure provider and API key separately from the AI provider above.")
                            .font(.caption).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        row(label: "Provider") {
                            Picker("", selection: $transcriptionProvider) {
                                Text("Off (SFSpeech, English only)").tag("")
                                ForEach(TranscriptionProviderType.allCases, id: \.rawValue) { p in
                                    Text(p.displayName).tag(p.rawValue)
                                }
                            }
                            .labelsHidden().pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onChange(of: transcriptionProvider) { loadTranscriptionKey() }
                        }

                        row(label: "Language") {
                            Picker("", selection: $transcriptionLanguage) {
                                Text("Auto detect").tag("auto")
                                Text("🇻🇳 Vietnamese").tag("vi")
                                Text("🇺🇸 English").tag("en")
                                Text("🇯🇵 Japanese").tag("ja")
                            }
                            .labelsHidden().pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let selected = selectedTranscriptionProvider {
                            row(label: "API Key") {
                                SecureField(selected == .deepgram ? "Deepgram API key..." : "sk-...", text: $transcriptionKey)
                                    .textFieldStyle(.roundedBorder).controlSize(.large)
                            }

                            row(label: "Model") {
                                VStack(alignment: .leading, spacing: 4) {
                                    TextField(selected == .deepgram ? "nova-2" : "gpt-realtime-whisper", text: $transcriptionModel)
                                        .textFieldStyle(.roundedBorder).controlSize(.large)
                                    Text(selected == .deepgram
                                         ? "nova-2, nova-3, enhanced, base"
                                         : "gpt-realtime-whisper (chỉ model này hỗ trợ transcription)")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }

                            if selected == .openaiRealtime {
                                row(label: "Base URL") {
                                    VStack(alignment: .leading, spacing: 4) {
                                        TextField("https://api.openai.com/v1", text: $transcriptionBaseURL)
                                            .textFieldStyle(.roundedBorder).controlSize(.large)
                                        Text("Để trống dùng OpenAI mặc định. Hỗ trợ custom endpoint.")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }

                            // Provider info
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.blue).font(.caption)
                                Group {
                                    switch selected {
                                    case .deepgram:
                                        Text("Deepgram Nova-2 — ~300ms latency, $0.0043/min, free $200 credit. ")
                                        + Text("deepgram.com").foregroundColor(.blue)
                                    case .openaiRealtime:
                                        Text("OpenAI Realtime — ~200ms latency, $0.006/min. ")
                                        + Text("platform.openai.com").foregroundColor(.blue)
                                    }
                                }
                                .font(.caption).foregroundColor(.secondary)
                            }

                            HStack {
                                Spacer()
                                if showTranscriptionKeySaved {
                                    Label("Saved", systemImage: "checkmark.circle.fill")
                                        .foregroundColor(.green).font(.subheadline)
                                        .transition(.opacity).padding(.trailing, 8)
                                }
                                saveButton("Save Key", action: saveTranscriptionKey)
                            }
                        }
                    }
                }

                // Footer
                HStack {
                    Image(systemName: "lock.fill").foregroundColor(.blue)
                    Text("API keys are saved securely in application preferences.")
                        .font(.footnote).foregroundColor(.secondary)
                }
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(24)
        }
        .frame(minWidth: 480, minHeight: 600)
        .onAppear {
            loadKey()
            loadTranscriptionKey()
        }
        .onChange(of: providerStr) { loadKey() }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func settingsSection<Content: View>(label: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(label, systemImage: icon).font(.headline)
            content()
                .padding()
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.1), lineWidth: 1))
        }
    }

    @ViewBuilder
    private func row<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .frame(width: 80, alignment: .leading)
                .foregroundColor(.secondary)
                .padding(.top, 6)
            content()
        }
    }

    private func saveButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).fontWeight(.medium)
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(Color.blue).foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Key management

    private func loadKey() {
        if let data = KeychainHelper.shared.read(key: "berryshot_ai_key_\(providerStr)"),
           let key = String(data: data, encoding: .utf8) {
            apiKey = key
        } else {
            apiKey = ""
        }
    }

    private func saveKey() {
        guard let data = apiKey.data(using: .utf8) else { return }
        _ = KeychainHelper.shared.save(key: "berryshot_ai_key_\(providerStr)", data: data)
        withAnimation(.spring()) { showKeySavedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeOut) { showKeySavedToast = false }
        }
    }

    private func loadTranscriptionKey() {
        guard !transcriptionKeychainKey.isEmpty,
              let data = KeychainHelper.shared.read(key: transcriptionKeychainKey),
              let key = String(data: data, encoding: .utf8)
        else { transcriptionKey = ""; return }
        transcriptionKey = key
    }

    private func saveTranscriptionKey() {
        guard !transcriptionKeychainKey.isEmpty,
              let data = transcriptionKey.data(using: .utf8) else { return }
        _ = KeychainHelper.shared.save(key: transcriptionKeychainKey, data: data)
        withAnimation { showTranscriptionKeySaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showTranscriptionKeySaved = false }
        }
    }
}
