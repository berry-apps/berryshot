# System Architecture

Layers:

Presentation
- SwiftUI Views
- ViewModels

Application
- CaptureCoordinator
- AnnotationCoordinator
- UploadCoordinator
- OCRCoordinator
- HistoryCoordinator

Domain
- CaptureService
- AnnotationService
- OCRService
- StorageService
- ShareService

Infrastructure
- ScreenCaptureKit
- Vision
- SwiftData
- Keychain
- URLSession

Modules:

App/
Capture/
Annotation/
OCR/
History/
Sharing/
Recording/
AI/
Infrastructure/
