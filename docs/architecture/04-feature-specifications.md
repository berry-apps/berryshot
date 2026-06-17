# Feature Specifications

## Capture Engine
Use ScreenCaptureKit.

Modes:
- Region
- Window
- Display

## Annotation Engine

Tools:
- Rectangle
- Circle
- Arrow
- Line
- Pencil
- Text
- Blur
- Pixelate
- Highlight
- Numbered markers

## OCR

Framework:
- Vision

Outputs:
- Plain text
- Structured blocks

## History

Store:
- Metadata
- Thumbnail
- OCR result
- Tags

## Cloud & Storage

Providers:
- Local Directory
- Google Drive
- Custom Service API

Security:
- All sensitive information (API Keys, Tokens) is stored securely in macOS Keychain.
- Provider metadata is stored in AppStorage.
