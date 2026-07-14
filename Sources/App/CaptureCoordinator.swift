import Foundation
import CoreGraphics
import Cocoa
import UniformTypeIdentifiers

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

@MainActor
public class CaptureCoordinator: ObservableObject {
    public static let shared = CaptureCoordinator()

    private let captureManager = ScreenCaptureManager()
    private var aiResultWindowControllers: [AIResultWindowController] = []
    private var liveMeetingWindowController: LiveMeetingWindowController?
    private var captureScreen: NSScreen?

    private init() {
        setupHotkeys()
    }

    private func setupHotkeys() {
        HotkeyManager.shared.onCaptureHotkey = { [weak self] in
            Task {
                await self?.startCapture()
            }
        }
        HotkeyManager.shared.onScrollCaptureHotkey = { [weak self] in
            Task { @MainActor in
                self?.startScrollCapture()
            }
        }
        HotkeyManager.shared.registerHotkeys()
    }

    private var overlayWindowController: OverlayWindowController?

    public func startCapture() async {
        if self.overlayWindowController != nil {
            print("Capture already in progress, ignoring hotkey.")
            return
        }

        do {
            // Capture the screen the cursor is currently on (supports multi-monitor)
            let mouseLocation = NSEvent.mouseLocation
            let activeScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
            guard let screen = activeScreen, let displayID = screen.displayID else {
                print("Capture failed: no active screen found")
                return
            }
            let cgImage = try await captureManager.captureDisplay(displayID)

            DispatchQueue.main.async {
                self.captureScreen = screen
                self.overlayWindowController = OverlayWindowController(cgImage: cgImage, display: screen)
                self.overlayWindowController?.show()
            }
        } catch {
            print("Capture failed: \(error)")
        }
    }

    public enum CaptureAction {
        case saveLocal
        case upload
    }

    public func finishCapture(cgImage: CGImage, rect: CGRect) {
        processCapture(cgImage: cgImage, rect: rect, action: .saveLocal)
    }

    public func uploadCapture(cgImage: CGImage, rect: CGRect) {
        processCapture(cgImage: cgImage, rect: rect, action: .upload)
    }

    public enum AIActionType {
        case explain
        case translate
        case refactor

        func prompt(langName: String) -> String {
            switch self {
            case .explain: return "Explain what is in this image briefly and concisely. Use Markdown formatting: use **bold** for key points, `code` for technical terms, bullet lists for multiple items, and code blocks for code snippets. Reply exclusively in \(langName)."
            case .translate: return "Translate the text in this image into \(langName). Use Markdown formatting with **bold** for emphasis. Only return the translated text."
            case .refactor: return "Refactor or improve the code shown in this image. Use Markdown formatting: wrap code in ```language code blocks```, use **bold** for key changes, and add bullet-point explanations. Reply exclusively in \(langName)."
            }
        }
    }

    public func handleAIAnalysis(cgImage: CGImage, rect: CGRect, screenBounds: CGRect, actionType: AIActionType = .explain) {
        let scale = (self.captureScreen ?? NSScreen.main)?.backingScaleFactor ?? 2.0
        let cropRect = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
        let finalImage = cgImage.cropping(to: cropRect) ?? cgImage

        let windowController = AIResultWindowController(rect: rect, screenBounds: screenBounds)
        windowController.viewModel.cgImage = finalImage
        self.aiResultWindowControllers.append(windowController)

        windowController.onClose = { [weak self, weak windowController] in
            self?.aiResultWindowControllers.removeAll { $0 === windowController }
        }

        windowController.show()
    }

    private func processCapture(cgImage: CGImage, rect: CGRect, action: CaptureAction) {
        self.overlayWindowController?.hide()
        self.overlayWindowController = nil
        self.closeAIWindow()

        let scale = (self.captureScreen ?? NSScreen.main)?.backingScaleFactor ?? 2.0
        let cropRect = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)

        if let cropped = cgImage.cropping(to: cropRect) {
            Task {
                let ocrService = OCRService()
                let ocrText = (try? await ocrService.extractText(from: cropped)) ?? ""

                guard let imagePath = self.saveImageToDisk(cgImage: cropped) else {
                    print("Capture aborted: failed to write image to disk")
                    return
                }

                let finalURL: URL
                if action == .upload || StorageConfiguration.shared.selectedProvider != .local {
                    await MainActor.run {
                        UploadResultWindowManager.shared.showLoading()
                    }
                    do {
                        let uploadService = await UploadServiceFactory.currentService()
                        finalURL = try await uploadService.uploadImage(fileURL: imagePath)
                        print("Upload successful: \(finalURL)")

                        // Copy URL to clipboard
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(finalURL.absoluteString, forType: .string)

                        await MainActor.run {
                            UploadResultWindowManager.shared.show(url: finalURL.absoluteString)
                        }
                    } catch {
                        print("Upload failed: \(error)")
                        finalURL = imagePath

                        let errorMessage = error.localizedDescription
                        await MainActor.run {
                            UploadResultWindowManager.shared.showError(errorMessage)
                        }
                    }
                } else {
                    do {
                        let uploadService = LocalUploadService()
                        finalURL = try await uploadService.uploadImage(fileURL: imagePath)
                    } catch {
                        finalURL = imagePath
                    }
                }

                let screenshot = ScreenshotModel(
                    imagePath: finalURL.path,
                    thumbnailPath: finalURL.path,
                    width: cropped.width,
                    height: cropped.height,
                    ocrText: ocrText
                )
                HistoryService.shared.save(screenshot)
                print("Capture processed and saved/uploaded to \(finalURL)\nOCR Text: \(ocrText)")
            }
        }
    }

    /// Save As: let the user pick a destination via NSSavePanel, then write the PNG there.
    public func saveAsCapture(cgImage: CGImage, rect: CGRect) {
        let scale = (self.captureScreen ?? NSScreen.main)?.backingScaleFactor ?? 2.0
        let cropRect = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
        let cropped = cgImage.cropping(to: cropRect) ?? cgImage

        let bitmapImage = NSBitmapImageRep(cgImage: cropped)
        bitmapImage.size = NSSize(width: cropped.width, height: cropped.height)
        guard let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            print("Save As failed: could not encode PNG")
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Screenshot-\(Self.timestampString()).png"
        let defaultDir = StorageConfiguration.shared.defaultLocalDirectory
        if !defaultDir.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: defaultDir)
        } else if let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            panel.directoryURL = desktop
        }

        // The overlay and toolbar windows sit at .screenSaver level and would obscure
        // and steal interaction from the panel. Hide the overlay entirely while the
        // panel is up, and bring it back if the user cancels.
        self.overlayWindowController?.hide()
        NSApp.activate(ignoringOtherApps: true)

        // runModal centers the panel on the main screen by default. Reposition it to the
        // center of the screen that was captured. The async block runs inside the modal
        // run loop, after the panel is on-screen, so it overrides the auto-centering.
        if let screen = self.captureScreen {
            DispatchQueue.main.async {
                let panelSize = panel.frame.size
                let vf = screen.visibleFrame
                let origin = NSPoint(x: vf.midX - panelSize.width / 2,
                                     y: vf.midY - panelSize.height / 2)
                panel.setFrameOrigin(origin)
            }
        }

        guard panel.runModal() == .OK, let destURL = panel.url else {
            self.overlayWindowController?.show() // Cancelled: restore the overlay.
            return
        }

        do {
            try pngData.write(to: destURL)
        } catch {
            print("Save As failed: \(error)")
            self.overlayWindowController?.show()
            return
        }

        // Confirmed and written: dismiss the overlay and record in history.
        self.overlayWindowController = nil
        self.closeAIWindow()

        Task {
            let ocrService = OCRService()
            let ocrText = (try? await ocrService.extractText(from: cropped)) ?? ""
            let screenshot = ScreenshotModel(
                imagePath: destURL.path,
                thumbnailPath: destURL.path,
                width: cropped.width,
                height: cropped.height,
                ocrText: ocrText
            )
            HistoryService.shared.save(screenshot)
            print("Saved screenshot to \(destURL.path)")
        }
    }

    private static func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }

    public func cancelCapture() {
        overlayWindowController?.hide()
        overlayWindowController = nil
        closeAIWindow()
    }

    // MARK: - Scroll Capture

    /// Convert an overlay-local rect (top-left origin, relative to `screen`) into global
    /// top-left display coordinates that ScreenCaptureKit / CGEvent operate in.
    private static func globalRect(fromLocal local: CGRect, on screen: NSScreen?) -> CGRect {
        guard let screen, let displayID = screen.displayID else { return local }
        let bounds = CGDisplayBounds(displayID)
        return CGRect(x: bounds.origin.x + local.minX,
                      y: bounds.origin.y + local.minY,
                      width: local.width,
                      height: local.height)
    }

    public func startScrollCapture() {
        // Save region selection (overlay-local, top-left origin) and its screen before closing overlay
        let localRegion = overlayWindowController?.viewModel?.selectionRect
        let overlayScreen = overlayWindowController?.window?.screen ?? captureScreen
        let isRegionCapture = (localRegion != nil && localRegion != .zero)

        // Cancel any active region capture to prevent its overlay window from hiding our alerts or UI
        cancelCapture()

        // 1. Check accessibility permission
        guard AccessibilityManager.shared.isAccessibilityGranted else {
            AccessibilityManager.shared.requestAccessibilityPermission()
            return
        }

        if isRegionCapture, let local = localRegion {
            // 2. Convert overlay-local rect to GLOBAL display coordinates so ScreenCaptureKit picks
            //    the monitor the user actually selected on (fixes secondary-monitor scroll capture).
            let globalRect = Self.globalRect(fromLocal: local, on: overlayScreen)
            Task { @MainActor in
                await self.performRegionScrollCapture(rect: globalRect)
            }
        } else {
            // 2. Show window selector for full-window scroll capture
            WindowSelectorPanelController.shared.show { [weak self] windowInfo in
                guard let self else { return }
                Task { @MainActor in
                    await self.performScrollCapture(windowInfo: windowInfo)
                }
            }
        }
    }
    private func performRegionScrollCapture(rect: CGRect) async {
        // Wait for the overlay window to completely disappear and restore target app focus
        try? await Task.sleep(nanoseconds: 300_000_000)
        let progressController = ScrollCaptureProgressController.shared

        progressController.show {
            ScrollCaptureManager.shared.cancel()
        }

        do {
            let stitched = try await ScrollCaptureManager.shared.captureRegion(
                rect: rect,
                onProgress: { progress in
                    Task { @MainActor in
                        ScrollCaptureProgressController.shared.update(progress)
                    }
                }
            )

            progressController.finish()

            let finalRect = CGRect(x: 0, y: 0, width: stitched.width, height: stitched.height)
            processScrollCaptureResult(cgImage: stitched, rect: finalRect)
        } catch {
            progressController.close()
            if let scrollError = error as? ScrollCaptureError, case .cancelled = scrollError {
                // User cancelled, do nothing
            } else {
                let alert = NSAlert()
                alert.messageText = "Scroll Capture Failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .critical
                alert.runModal()
            }
        }
    }

    private func performScrollCapture(windowInfo: WindowInfo) async {
        // Activate target app so that synthetic scrolls and keystrokes work
        if let app = NSRunningApplication(processIdentifier: windowInfo.pid) {
            app.activate(options: [])
        }

        // Wait for the window selector overlay to disappear and space transition to complete
        // Space transitions (e.g. to a full screen app) can take up to 1 second
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        let progressController = ScrollCaptureProgressController.shared

        progressController.show {
            ScrollCaptureManager.shared.cancel()
        }

        do {
            let stitched = try await ScrollCaptureManager.shared.captureScrollable(
                window: windowInfo.scWindow,
                pid: windowInfo.pid,
                onProgress: { progress in
                    Task { @MainActor in
                        ScrollCaptureProgressController.shared.update(progress)
                    }
                }
            )

            progressController.finish()

            // Route through existing save/upload pipeline
            // Use full image rect (scroll capture already produced final image)
            let rect = CGRect(origin: .zero, size: CGSize(width: stitched.width, height: stitched.height))
            processScrollCaptureResult(cgImage: stitched, rect: rect)

        } catch ScrollCaptureError.cancelled {
            progressController.close()
        } catch {
            progressController.showError(error.localizedDescription)
        }
    }

    private func processScrollCaptureResult(cgImage: CGImage, rect: CGRect) {
        let resultWindow = ScrollCaptureResultWindowController(cgImage: cgImage)
        resultWindow.show()

        Task {
            let ocrService = OCRService()
            let ocrText = (try? await ocrService.extractText(from: cgImage)) ?? ""

            guard let imagePath = self.saveImageToDisk(cgImage: cgImage) else {
                print("Scroll capture aborted: failed to write image to disk")
                return
            }

            let finalURL: URL
            if StorageConfiguration.shared.selectedProvider != .local {
                await MainActor.run {
                    UploadResultWindowManager.shared.showLoading()
                }
                do {
                    let uploadService = await UploadServiceFactory.currentService()
                    finalURL = try await uploadService.uploadImage(fileURL: imagePath)
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(finalURL.absoluteString, forType: .string)
                    await MainActor.run {
                        UploadResultWindowManager.shared.show(url: finalURL.absoluteString)
                    }
                } catch {
                    finalURL = imagePath
                    let errorMessage = error.localizedDescription
                    await MainActor.run {
                        UploadResultWindowManager.shared.showError(errorMessage)
                    }
                }
            } else {
                do {
                    let uploadService = LocalUploadService()
                    finalURL = try await uploadService.uploadImage(fileURL: imagePath)
                } catch {
                    finalURL = imagePath
                }
            }

            let screenshot = ScreenshotModel(
                imagePath: finalURL.path,
                thumbnailPath: finalURL.path,
                width: cgImage.width,
                height: cgImage.height,
                ocrText: ocrText
            )
            HistoryService.shared.save(screenshot)
            print("Scroll capture processed and saved to \(finalURL)\nOCR Text: \(ocrText)")
        }
    }

    public func copyToClipboard(cgImage: CGImage, rect: CGRect) {
        self.overlayWindowController?.hide()
        self.overlayWindowController = nil
        self.closeAIWindow()

        let scale = (self.captureScreen ?? NSScreen.main)?.backingScaleFactor ?? 2.0
        let cropRect = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)

        if let cropped = cgImage.cropping(to: cropRect) {
            let nsImage = NSImage(cgImage: cropped, size: .zero)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([nsImage])
            print("Copied to clipboard")
        }
    }

    private func saveImageToDisk(cgImage: CGImage) -> URL? {
        // Encode straight from the CGImage. Avoids building a full TIFF copy first,
        // which can fail or exhaust memory for very tall stitched scroll captures —
        // a failure there used to crash the whole app via fatalError.
        let bitmapImage = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            print("Failed to convert CGImage to PNG data (image \(cgImage.width)x\(cgImage.height))")
            return nil
        }

        let fileManager = FileManager.default
        let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupportDir.appendingPathComponent("BerryShot", isDirectory: true)

        if !fileManager.fileExists(atPath: appDir.path) {
            try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true, attributes: nil)
        }

        let filename = "Screenshot-\(UUID().uuidString).png"
        let fileURL = appDir.appendingPathComponent(filename)

        try? pngData.write(to: fileURL)
        return fileURL
    }

    public func closeAIWindow() {
        self.aiResultWindowControllers.forEach { controller in
            controller.hide()
            controller.close()
        }
        self.aiResultWindowControllers.removeAll()
    }

    public func toggleLiveMeetingNotes() {
        if let wc = liveMeetingWindowController, wc.window?.isVisible == true {
            wc.close()
        } else {
            if liveMeetingWindowController == nil {
                liveMeetingWindowController = LiveMeetingWindowController {
                    Task { @MainActor in
                        CaptureCoordinator.shared.generateMeetingMinutes()
                    }
                }
            }
            liveMeetingWindowController?.show()
        }
    }

    public func generateMeetingMinutes() {
        let transcript = LiveTranscriptionService.shared.liveTranscript
        guard !transcript.isEmpty else { return }

        let screenBounds = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let rect = CGRect(x: screenBounds.midX - 200, y: screenBounds.midY - 100, width: 400, height: 200)
        let wc = AIResultWindowController(rect: rect, screenBounds: screenBounds)
        aiResultWindowControllers.append(wc)
        wc.onClose = { [weak self, weak wc] in
            self?.aiResultWindowControllers.removeAll { $0 === wc }
        }
        wc.show()

        Task {
            guard let ai = Phase3Workflow() else {
                await MainActor.run {
                    wc.viewModel.errorMessage = "AI Configuration Missing. Please configure it in Settings."
                    wc.viewModel.isLoading = false
                }
                return
            }
            do {
                let stream = ai.provider.generateTextStream(prompt: buildMeetingMinutesPrompt(transcript), image: nil)
                await MainActor.run {
                    wc.viewModel.isLoading = true
                    wc.viewModel.currentStreamText = ""
                }
                for try await chunk in stream {
                    await MainActor.run { wc.viewModel.currentStreamText += chunk }
                }
                await MainActor.run {
                    wc.viewModel.chatHistory.append(AIChatMessage(role: .assistant, content: wc.viewModel.currentStreamText))
                    wc.viewModel.currentStreamText = ""
                    wc.viewModel.isLoading = false
                }
            } catch {
                await MainActor.run {
                    wc.viewModel.errorMessage = "Failed to generate minutes: \(error.localizedDescription)"
                    wc.viewModel.isLoading = false
                }
            }
        }
    }

    private func buildMeetingMinutesPrompt(_ transcript: [TranscriptSegment]) -> String {
        let lines = transcript
            .sorted { $0.timestamp < $1.timestamp }
            .map { seg -> String in
                let speaker = seg.source == .mic ? "You" : "Other"
                let m = Int(seg.timestamp) / 60
                let s = Int(seg.timestamp) % 60
                return String(format: "[%02d:%02d] \(speaker): \(seg.text)", m, s)
            }
            .joined(separator: "\n")

        return """
        You are a professional meeting minutes assistant. Based on the following meeting transcript, \
        create minutes in Markdown format with: \
        **Summary**, **Key Discussion Points**, **Decisions Made**, **Action Items**.

        Transcript:
        \(lines)
        """
    }
}
