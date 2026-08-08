import SwiftUI

struct PrivacySettingsView: View {
    @ObservedObject private var redactionSettings = RedactionSettings.shared
    @State private var newCustomTerm: String = ""

    var body: some View {
        Form {
            VStack(alignment: .leading, spacing: 16) {
                Text("Privacy & Data")
                    .font(.headline)

                Text("BerryShot is a 100% free screen capture tool with no ads, no trackers, and no background data collection.")
                    .font(.body)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Local-First Processing").bold()
                    Text("• All screen captures, recordings, and drawings are processed entirely on your Mac.")
                    Text("• Your capture history and files stay local to your computer and are never shared automatically.")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("On-Demand Integrations").bold()
                    Text("• Data is only sent to external servers when you explicitly initiate an Upload or AI Analysis.")
                    Text("• Only the selected capture region and essential metadata are sent to the APIs you configure.")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Sensitive Content Redaction").bold()
                    Text("Use the Redact tool in the capture toolbar to mark regions by hand, or let BerryShot automatically detect likely sensitive regions below. Either way, BerryShot flattens them (blur, pixelate, or solid cover) before the image is saved, uploaded, or added to history. Automatic detection is best-effort — it never guarantees every secret is found, so review a capture before sharing it.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Picker("Redaction policy", selection: $redactionSettings.policy) {
                        Text("Off — do not track redaction status").tag(RedactionPolicy.none)
                        Text("Suggest — warn when a capture has not been reviewed").tag(RedactionPolicy.suggest)
                        Text("Required — block captures with no reviewed region").tag(RedactionPolicy.required)
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 380)

                    Picker("Default redaction style", selection: $redactionSettings.style) {
                        Text("Blur").tag(RedactionStyle.blur)
                        Text("Pixelate").tag(RedactionStyle.pixelate)
                        Text("Solid Cover").tag(RedactionStyle.solid)
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 380)

                    if redactionSettings.policy == .required {
                        Text("App/Window and Scroll captures have no manual-region editor yet, so Required mode relies entirely on automatic detection for them: a capture is blocked only if detection could not run to completion. Region Capture also supports marking regions by hand.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                Divider()

                automaticDetectionSection
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    /// Category toggles and custom-term editing for WP5's automatic
    /// AX/Vision detection. Matches the locked defaults in
    /// `10-decisions-risks-open-questions.md` section 4: secure fields,
    /// card numbers, and API/token prefixes are on by default; email and
    /// phone are opt-in because they are common in legitimate documentation.
    @ViewBuilder
    private var automaticDetectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Automatic Detection").bold()
            Text("BerryShot can automatically find likely sensitive regions using on-device Accessibility and text recognition. Detected regions are never logged or shown as text — only the category and count.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Toggle("Secure text fields (e.g. password fields)", isOn: $redactionSettings.detectSecureFields)
            Toggle("Credit/debit card numbers (Luhn-validated)", isOn: $redactionSettings.detectCardNumbers)
            Toggle("API keys, tokens, and private key headers", isOn: $redactionSettings.detectAPITokens)
            Toggle("Email addresses", isOn: $redactionSettings.detectEmail)
            Toggle("Phone numbers", isOn: $redactionSettings.detectPhoneNumbers)

            Divider().padding(.vertical, 4)

            Text("Custom Terms").bold()
            Text("Add specific words or phrases (project codenames, internal hostnames, etc.) that should always be redacted when found in a capture.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Toggle("Match custom terms case-sensitively", isOn: $redactionSettings.customTermsCaseSensitive)

            HStack {
                TextField("Add a term…", text: $newCustomTerm)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addCustomTerm)
                Button("Add", action: addCustomTerm)
                    .disabled(newCustomTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .frame(maxWidth: 380)

            if redactionSettings.customTerms.isEmpty {
                Text("No custom terms configured.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(redactionSettings.customTerms, id: \.self) { term in
                        HStack {
                            Text(term)
                            Spacer()
                            Button {
                                removeCustomTerm(term)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(term)")
                        }
                    }
                }
                .frame(maxWidth: 380)
            }
        }
    }

    private func addCustomTerm() {
        redactionSettings.addCustomTerm(newCustomTerm)
        newCustomTerm = ""
    }

    private func removeCustomTerm(_ term: String) {
        if let index = redactionSettings.customTerms.firstIndex(of: term) {
            redactionSettings.removeCustomTerm(at: IndexSet(integer: index))
        }
    }
}
