import Foundation
import CoreGraphics
import Cocoa

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
        // Show loading window
        let windowController = AIResultWindowController(rect: rect, screenBounds: screenBounds)
        self.aiResultWindowControllers.append(windowController)
        
        windowController.onClose = { [weak self, weak windowController] in
            self?.aiResultWindowControllers.removeAll { $0 === windowController }
        }
        
        windowController.show()
        
        Task {
            if let ai = Phase3Workflow() {
                do {
                    let lang = UserDefaults.standard.string(forKey: "ai_output_language") ?? "en"
                    let langName = lang == "vi" ? "Vietnamese" : (lang == "ja" ? "Japanese" : "English")
                    let prompt = actionType.prompt(langName: langName)
                    
                    let scale = (self.captureScreen ?? NSScreen.main)?.backingScaleFactor ?? 2.0
                    let cropRect = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
                    let finalImage = cgImage.cropping(to: cropRect) ?? cgImage
                    
                    let stream = ai.provider.generateTextStream(prompt: prompt, image: finalImage)
                    await MainActor.run {
                        windowController.viewModel.resultText = ""
                    }
                    for try await chunk in stream {
                        await MainActor.run {
                            windowController.viewModel.resultText += chunk
                        }
                    }
                    await MainActor.run {
                        windowController.viewModel.isLoading = false
                    }
                } catch {
                    await MainActor.run {
                        if windowController.viewModel.resultText.isEmpty {
                            windowController.viewModel.errorMessage = "Failed to analyze image: \(error.localizedDescription)"
                            windowController.viewModel.isLoading = false
                        } else {
                            windowController.viewModel.resultText += "\n\n[Error: \(error.localizedDescription)]"
                        }
                    }
                }
            } else {
                await MainActor.run {
                    windowController.viewModel.errorMessage = "AI Configuration Missing. Please configure it in Settings."
                    windowController.viewModel.isLoading = false
                }
            }
        }
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
                
                let imagePath = self.saveImageToDisk(cgImage: cropped) // Save temporarily first
                
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
    
    public func cancelCapture() {
        overlayWindowController?.hide()
        overlayWindowController = nil
        closeAIWindow()
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
    
    private func saveImageToDisk(cgImage: CGImage) -> URL {
        let nsImage = NSImage(cgImage: cgImage, size: .zero)
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            fatalError("Failed to convert CGImage to PNG data")
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
                await MainActor.run { wc.viewModel.resultText = "" }
                for try await chunk in stream {
                    await MainActor.run { wc.viewModel.resultText += chunk }
                }
                await MainActor.run { wc.viewModel.isLoading = false }
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
