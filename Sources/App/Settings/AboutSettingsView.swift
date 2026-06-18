import SwiftUI

struct AboutSettingsView: View {
    @StateObject private var storeManager = StoreManager.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // App Icon
                if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
                   let nsImage = NSImage(contentsOf: url) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .frame(width: 96, height: 96)
                } else {
                    Image(systemName: "camera.viewfinder")
                        .resizable()
                        .frame(width: 64, height: 64)
                        .foregroundColor(.accentColor)
                }
                
                VStack(spacing: 6) {
                    Text("BerryShot")
                        .font(.system(size: 28, weight: .bold))
                    
                    Text("Version 1.0.1")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 6) {
                    Text("BerryShot is a fast, minimal macOS screen capture tool.")
                    Text("Capture, save, and share your screen with zero friction.")
                    
                    Text("Built for speed and simplicity.")
                        .padding(.top, 4)
                    
                    HStack(spacing: 4) {
                        Text("Support:")
                            .foregroundColor(.secondary)
                        Link("support@notex.work", destination: URL(string: "mailto:support@notex.work")!)
                    }
                    .padding(.top, 4)
                }
                .multilineTextAlignment(.center)
                .font(.body)
                
                Divider()
                    .frame(width: 280)
                
                VStack(spacing: 8) {
                    Text("Support BerryShot")
                        .font(.headline)
                        .padding(.top, 8)
                    
                    Text("If you find BerryShot useful, consider buying me a coffee ☕️")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        if storeManager.donateProduct != nil {
                            Task { await storeManager.purchase() }
                        } else {
                            if let url = URL(string: "https://notex.work/donate") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            if storeManager.isPurchasing {
                                ProgressView().controlSize(.small)
                            }
                            Text("Donate \(storeManager.donateProduct?.displayPrice ?? "$10.00")")
                                .font(.subheadline)
                        }
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(storeManager.isPurchasing)
                    
                    if storeManager.showThankYou {
                        Text("💖 Thank you so much for your support!")
                            .foregroundColor(.green)
                            .font(.caption)
                            .padding(.top, 4)
                    }
                }
                .padding(.bottom, 20)
            }
            .padding(.top, 40)
            .padding(.horizontal, 30)
            .frame(maxWidth: .infinity)
        }
    }
}
