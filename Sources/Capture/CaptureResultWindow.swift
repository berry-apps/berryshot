import AppKit
import SwiftUI

/// Shared "here's what you just captured" preview window: Scroll Capture and
/// single-window/App capture both show this after the capture is already
/// redacted and saved, offering Copy/Save.../Upload as convenience actions
/// on top of the already-final image — never on a pre-redaction one, which
/// this type's callers are responsible for guaranteeing.
public class CaptureResultWindowController: NSWindowController {
    public static var activeControllers: [CaptureResultWindowController] = []

    /// Nothing ever closes an old result window on its own — the user has to
    /// click Close/Esc on every single one. Each holds a full-resolution
    /// decoded image (tens of MB for a Retina capture), and repeated
    /// captures without dismissing the previous preview accumulate windows
    /// without limit: this is reachable, intentional state (every window is
    /// still in `activeControllers`), so it never shows up as a "leak" to
    /// ARC/`leaks`, but it is exactly why memory climbs with capture count
    /// and never comes back down on its own, even after leaving the app
    /// idle. Generous enough to comfortably fit a real "capture all windows
    /// of one app" batch; still a hard, finite ceiling instead of no ceiling
    /// at all.
    private static let maxConcurrentWindows = 12

    /// Batch "capture whole app" can show several of these at once (one per
    /// window); cascading instead of centering every one on top of the last
    /// keeps them all reachable instead of only the topmost being visible.
    private static var lastCascadePoint: NSPoint = .zero

    private var closeObserver: NSObjectProtocol?

    public convenience init(
        cgImage: CGImage,
        title: String = "Scroll Capture Result",
        filenamePrefix: String = "ScrollCapture"
    ) {
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

        // Size the image area to the capture's own aspect ratio, clamped to
        // a sane range, instead of independently capping width and height —
        // that let a non-square image (nearly every real capture) get
        // forced into a near-square window, leaving `scaledToFit()` to
        // letterbox it with empty space above/below or beside the image.
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let imagePointWidth = CGFloat(cgImage.width) / scale
        let imagePointHeight = CGFloat(cgImage.height) / scale
        let maxDimension: CGFloat = 900
        let minDimension: CGFloat = 320
        var displayWidth = imagePointWidth
        var displayHeight = imagePointHeight
        if displayWidth > maxDimension || displayHeight > maxDimension {
            let shrink = min(maxDimension / displayWidth, maxDimension / displayHeight)
            displayWidth *= shrink
            displayHeight *= shrink
        }
        if displayWidth < minDimension || displayHeight < minDimension {
            let grow = max(minDimension / displayWidth, minDimension / displayHeight)
            displayWidth *= grow
            displayHeight *= grow
        }

        // The action toolbar below the image has its own fixed height,
        // separate from the image area being sized here.
        let toolbarHeight: CGFloat = 64

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: displayWidth, height: displayHeight + toolbarHeight),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        if Self.lastCascadePoint == .zero {
            // First preview since launch (or since the cascade sequence
            // last reset): center it, matching the original single-capture
            // behavior, and seed the cascade origin from where that landed.
            window.center()
            let frame = window.frame
            Self.lastCascadePoint = NSPoint(x: frame.minX, y: frame.maxY)
        } else {
            Self.lastCascadePoint = window.cascadeTopLeft(from: Self.lastCascadePoint)
        }
        window.isReleasedWhenClosed = false
        window.level = .floating // ensure it appears above other windows
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        // `window.contentView` (transitively) holds `view`, so a *strong*
        // capture of `window` here would retain window -> contentView ->
        // view -> this closure -> window: a cycle keeping the window (and
        // its full-resolution `nsImage`) alive forever, for every single
        // capture shown, even after the window is closed and its controller
        // removed from `activeControllers`.
        let view = CaptureResultView(image: nsImage, filenamePrefix: filenamePrefix) { [weak window] in
            window?.close()
        }

        window.contentView = NSHostingView(rootView: view)

        self.init(window: window)

        CaptureResultWindowController.activeControllers.append(self)
        // Enforce the ceiling by closing the oldest surviving windows first
        // — closing (rather than just dropping the array entry) runs the
        // exact same teardown path as the user clicking Close, so the
        // window/image actually deallocate instead of merely losing this
        // one reference.
        while CaptureResultWindowController.activeControllers.count > Self.maxConcurrentWindows {
            let oldest = CaptureResultWindowController.activeControllers.removeFirst()
            // `oldest` is already out of `activeControllers` here, so it is
            // the *only* strong reference keeping it alive — once this loop
            // iteration ends, ARC can deallocate it immediately, before the
            // `willCloseNotification` handler's `Task { @MainActor in ... }`
            // below ever gets a run-loop turn to execute its weakly-captured
            // `self`. That would skip `removeObserver` entirely, leaking the
            // registration. Remove it here, synchronously, instead of
            // relying on that handler for this path.
            if let token = oldest.closeObserver {
                NotificationCenter.default.removeObserver(token)
                oldest.closeObserver = nil
            }
            oldest.window?.close()
        }
        // Every capture (single, batch-per-window, and scroll) creates one of
        // these, and the app stays running in the menu bar all day — an
        // observer registered without ever being removed accumulates one
        // permanent NotificationCenter entry per screenshot for the life of
        // the process. Self-remove it as soon as it fires.
        let observer = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: nil) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                CaptureResultWindowController.activeControllers.removeAll { $0 === self }
                if let token = self.closeObserver {
                    NotificationCenter.default.removeObserver(token)
                }
            }
        }
        self.closeObserver = observer
    }

    public func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct CaptureResultView: View {
    let image: NSImage
    let filenamePrefix: String
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
        savePanel.nameFieldStringValue = "\(filenamePrefix)-\(Int(Date().timeIntervalSince1970)).png"

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
            let fileName = "\(filenamePrefix)-\(Int(Date().timeIntervalSince1970)).png"
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
