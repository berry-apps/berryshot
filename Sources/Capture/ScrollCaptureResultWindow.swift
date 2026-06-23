import AppKit
import SwiftUI

public class ScrollCaptureResultWindowController: NSWindowController {
    public static var activeControllers: [ScrollCaptureResultWindowController] = []

    public convenience init(cgImage: CGImage) {
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        
        // Size window to fit image up to 800x800
        let winWidth = min(800.0, CGFloat(cgImage.width) / (NSScreen.main?.backingScaleFactor ?? 2.0))
        let winHeight = min(800.0, CGFloat(cgImage.height) / (NSScreen.main?.backingScaleFactor ?? 2.0))
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: max(400, winWidth), height: max(400, winHeight)),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Scroll Capture Result"
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating // ensure it appears above other windows
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        
        let view = ScrollCaptureResultView(image: nsImage) {
            window.close()
        }
        
        window.contentView = NSHostingView(rootView: view)
        
        self.init(window: window)
        
        ScrollCaptureResultWindowController.activeControllers.append(self)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: nil) { [weak self] _ in
            Task { @MainActor in
                ScrollCaptureResultWindowController.activeControllers.removeAll { $0 === self }
            }
        }
    }
    
    public func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct ScrollCaptureResultView: View {
    let image: NSImage
    let onClose: () -> Void
    
    @State private var showCopiedIndicator = false
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding()
            }
            .background(Color(NSColor.windowBackgroundColor))
            
            HStack {
                Button(action: {
                    copyToClipboard()
                }) {
                    Label(showCopiedIndicator ? "Copied!" : "Copy (⌘C)", systemImage: showCopiedIndicator ? "checkmark" : "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: .command)
                .buttonStyle(.borderedProminent)
                
                Button(action: {
                    saveToDisk()
                }) {
                    Label("Save... (⌘S)", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: .command)
                
                Button(action: {
                    uploadToCloud()
                }) {
                    Label("Upload (⌘U)", systemImage: "icloud.and.arrow.up")
                }
                .keyboardShortcut("u", modifiers: .command)
                
                Spacer()
                
                Button("Close (Esc)") {
                    onClose()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
            .background(VisualEffectBackground().ignoresSafeArea())
        }
    }
    
    private func copyToClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        
        withAnimation {
            showCopiedIndicator = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopiedIndicator = false
            }
            onClose() // Auto-close after copy is a good UX for screenshot tools
        }
    }
    
    private func saveToDisk() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "ScrollCapture-\(Int(Date().timeIntervalSince1970)).png"
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
            if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: url)
                    onClose()
                }
            }
        }
    }
    
    private func uploadToCloud() {
        Task {
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "ScrollCapture-\(Int(Date().timeIntervalSince1970)).png"
            let tempURL = tempDir.appendingPathComponent(fileName)
            
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return }
            
            try? png.write(to: tempURL)
            
            await MainActor.run {
                UploadResultWindowManager.shared.showLoading()
                onClose()
            }
            
            do {
                let uploadService = await UploadServiceFactory.currentService()
                let finalURL = try await uploadService.uploadImage(fileURL: tempURL)
                
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(finalURL.absoluteString, forType: .string)
                
                await MainActor.run {
                    UploadResultWindowManager.shared.show(url: finalURL.absoluteString)
                }
            } catch {
                let errorMessage = error.localizedDescription
                await MainActor.run {
                    UploadResultWindowManager.shared.showError(errorMessage)
                }
            }
        }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .headerView
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
