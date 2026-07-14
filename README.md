# 🍓 BerryShot

[![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-blue.svg)](https://developer.apple.com/macos/)
[![Language](https://img.shields.io/badge/language-Swift%206.0-orange.svg)](https://swift.org/)
[![License](https://img.shields.io/badge/license-PolyForm%20Noncommercial-orange.svg)](LICENSE)
[![Source Code](https://img.shields.io/badge/github-berryshot-lightgrey.svg?logo=github)](https://github.com/berry-apps/berryshot)
[![Support on Ko-fi](https://img.shields.io/badge/Ko--fi-support-FF5E5B.svg?logo=kofi&logoColor=white)](https://ko-fi.com/dautay)

**BerryShot** is a native, source-available macOS utility that brings robust region screen capture, rich annotation tools, 100% offline OCR extraction, and multi-model AI integrations directly into your macOS Menu Bar.

For precompiled releases, user guides, and developer articles, visit the official site at [notex.work](https://notex.work).

---

## ✨ Key Features

- **🍓 Native Capture Overlay**: Fast, interactive region selector initiated via keyboard shortcut (`⌘ + ⇧ + 1`) or Menu Bar item.
- **📜 Scrolling Capture**: Stitch multiple screenshots together for entire webpages or long documents.
- **🎨 Live Annotation Tools**: Draw rectangles, lines, arrows, custom highlights, and overlay rich text on the canvas before completing the capture.
- **🔍 100% Local OCR**: Perform lightning-fast, offline Optical Character Recognition (OCR) to copy text from screen selections instantly.
- **🤖 Cloud & AI Assistant Integration**:
  - Connect captures to AI models (Gemini, Claude, OpenAI, OpenRouter, and Xiaomi Mimo) to summarize code, translate, or extract data.
  - Choose your output language and customize prompt templates.
- **🎙️ Live Meeting Transcription**: Real-time speech-to-text via Deepgram Nova or OpenAI Whisper with dual-source (mic + system audio) capture.
- **🎬 Screen Recording**: HEVC 60fps recording with system audio, microphone, pause/resume, and dynamic region updates.
- **📸 Screenshot History**: Automatic local history with SwiftData for browsing and managing past captures.
- **☁️ Multi-Provider Storage**:
  - Save to a default local folder.
  - Automatically upload captures to **Google Drive** or a custom **HTTP POST Endpoint** (with bearer token / API keys security).
- **🔒 Secure Credentials**: All tokens, API keys, and cloud secrets are stored securely in the native **macOS Keychain**.

---

## 🚀 Installation

You can download precompiled versions of BerryShot:

1. **DMG Installer**: Download [BerryShot.dmg](https://berryshot-download.notex.work/BerryShot.dmg), open it, and drag BerryShot into your Applications folder.
2. **Official site**: Browse all releases and download from the official site — [notex.work](https://notex.work).

---

## 🛠️ Building From Source

### Prerequisites
- **macOS 14.0** or higher.
- **Xcode 15.0+** or Xcode Command Line Tools.
- **Swift 6.0** compiler.

### Build Steps

1. Clone the repository:
   ```bash
   git clone https://github.com/berry-apps/berryshot.git
   cd berryshot
   ```

2. Compile the executable using Swift Package Manager:
   ```bash
   swift build -c release
   ```

3. To assemble a runnable `.app` bundle (compiles, generates the app icon, and writes `Info.plist`):
   ```bash
   ./build_app.sh
   ```
   This produces an **unsigned** bundle at `dist/BerryShot.app`. Launch it with:
   ```bash
   open dist/BerryShot.app
   ```

   > Note: the bundle is unsigned, so macOS Gatekeeper will block it on other machines. Signed & notarized release builds (DMG/ZIP) are produced by maintainers and published to the official site.

---

## 🔧 AI & Cloud API Structure

### Custom Upload Integration
When uploading to your custom service endpoint, the application transmits the binary image as standard `multipart/form-data` with the file key `file`:

```bash
curl -X POST "<Endpoint URL>" \
  -H "Authorization: Bearer <Access Token>" \
  -F "file=@Screenshot.png;type=image/png"
```

The server response should be a JSON payload. By specifying a path in **Callback URL** (e.g. `{json:data.url}` or `data.url`), BerryShot will parse the JSON response to retrieve the direct image URL and copy it straight to your clipboard.

---

## 📄 License

BerryShot is **source-available** under the [PolyForm Noncommercial License 1.0.0](LICENSE).

You may use, modify, and share it freely for **any noncommercial purpose** — personal use, study, research, hobby projects, and use by nonprofits, schools, or government. **Commercial use is not permitted.** For commercial licensing, contact [support@notex.work](mailto:support@notex.work).

---

## 💖 Support

BerryShot is free for noncommercial use. If it saves you time, consider supporting development — it genuinely helps keep the project maintained:

☕ **[Buy me a coffee on Ko-fi →](https://ko-fi.com/dautay)**

---

## 🤝 Contributing

Contributions, bug reports, and feature requests are welcome! Feel free to open issues or submit pull requests to the [GitHub Repository](https://github.com/berry-apps/berryshot).

---

## 👥 Contributors

[<img src="https://github.com/quangtaned.png" width="64" alt="quangtaned"/>](https://github.com/quangtaned)
[<img src="https://github.com/trungdv96.png" width="64" alt="trungdv96"/>](https://github.com/trungdv96)

Built and maintained by [@quangtaned](https://github.com/quangtaned) and [@trungdv96](https://github.com/trungdv96).
