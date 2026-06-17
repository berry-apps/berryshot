import SwiftUI

struct PrivacySettingsView: View {
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
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
