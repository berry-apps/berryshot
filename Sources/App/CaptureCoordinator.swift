import Foundation
import CoreGraphics
import Cocoa

@MainActor
public class CaptureCoordinator: ObservableObject {
    public static let shared = CaptureCoordinator()
    
    private let captureManager = ScreenCaptureManager()
    private var aiResultWindowController: AIResultWindowController?
    
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
            // For Phase 1, we capture the main display
            let displayID = CGMainDisplayID()
            let cgImage = try await captureManager.captureDisplay(displayID)
            
            DispatchQueue.main.async {
                if let screen = NSScreen.main {
                    self.overlayWindowController = OverlayWindowController(cgImage: cgImage, display: screen)
                    self.overlayWindowController?.show()
                }
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
    
    public func handleAIAnalysis(cgImage: CGImage) {
        self.cancelCapture() // Hide overlay immediately
        
        // Show loading window
        let windowController = AIResultWindowController()
        self.aiResultWindowController = windowController
        windowController.show()
        
        Task {
            if let ai = Phase3Workflow() {
                do {
                    let lang = UserDefaults.standard.string(forKey: "ai_output_language") ?? "en"
                    let langName = lang == "vi" ? "Vietnamese" : (lang == "ja" ? "Japanese" : "English")
                    let prompt = "Explain what is in this image briefly and concisely. Please reply exclusively in \(langName)."
                    let stream = ai.provider.generateTextStream(prompt: prompt, image: cgImage)
                    await MainActor.run {
                        windowController.viewModel.resultText = ""
                        windowController.viewModel.isLoading = false
                    }
                    for try await chunk in stream {
                        await MainActor.run {
                            windowController.viewModel.resultText += chunk
                        }
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
        
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
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
    }
    
    public func copyToClipboard(cgImage: CGImage, rect: CGRect) {
        self.overlayWindowController?.hide()
        self.overlayWindowController = nil
        
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
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
}
