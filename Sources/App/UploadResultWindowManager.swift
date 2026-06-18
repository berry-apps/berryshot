import SwiftUI
import AppKit

@MainActor
public class UploadResultWindowManager {
    public static let shared = UploadResultWindowManager()
    private var window: NSWindow?
    
    private init() {}
    
    public func showLoading() {
        let view = UploadLoadingView()
        presentPanel(title: "Uploading to Cloud...", view: AnyView(view), height: 120)
    }
    
    public func show(url: String) {
        let view = UploadResultView(url: url)
        presentPanel(title: "Cloud Upload Successful", view: AnyView(view), height: 120)
    }
    
    public func showError(_ message: String) {
        let view = UploadErrorView(message: message)
        presentPanel(title: "Upload Failed", view: AnyView(view), height: 250)
    }
    
    private func presentPanel(title: String, view: AnyView, height: CGFloat) {
        if window == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 450, height: height),
                                styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                                backing: .buffered,
                                defer: false)
            panel.level = .floating
            panel.center()
            panel.isReleasedWhenClosed = false
            self.window = panel
        }
        
        window?.setContentSize(NSSize(width: 450, height: height))
        window?.title = title
        window?.contentView = NSHostingView(rootView: view)
        
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct UploadErrorView: View {
    let message: String
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.title2)
                Text("Failed to Upload Image")
                    .font(.headline)
            }
            
            ScrollView {
                Text(message)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .padding()
            }
            .background(Color.black.opacity(0.05))
            .cornerRadius(8)
            .padding(.horizontal)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct UploadLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .progressViewStyle(CircularProgressViewStyle())
            
            Text("Uploading Image...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 450, height: 120)
    }
}

struct UploadResultView: View {
    let url: String
    @State private var copied = false
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Image Uploaded Successfully!")
                .font(.headline)
            
            HStack {
                TextField("", text: .constant(url))
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1)
                
                Button(action: {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(url, forType: .string)
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { copied = false }
                    }
                }) {
                    Image(systemName: copied ? "checkmark" : "doc.on.clipboard")
                        .foregroundColor(copied ? .green : .primary)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(width: 450, height: 120)
    }
}
