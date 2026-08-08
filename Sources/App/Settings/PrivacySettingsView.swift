import SwiftUI

struct PrivacySettingsView: View {
    @ObservedObject private var redactionSettings = RedactionSettings.shared

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
                    Text("Automatic detection has not shipped yet. Use the Redact tool in the capture toolbar to mark regions by hand; BerryShot flattens them (blur, pixelate, or solid cover) before the image is saved, uploaded, or added to history.")
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
                        Text("Required mode currently blocks App/Window and Scroll captures, which have no manual-region editor yet. Only Region Capture supports marking regions in this release.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
