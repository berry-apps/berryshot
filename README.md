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

- **🍓 Native Capture Overlay**: Fast, interactive region selector initiated via keyboard shortcut (`⌘ + ⇧ + 2`) or Menu Bar item.
- **🖼️ App & Window Capture**: Capture a single window or all eligible windows of any application via dedicated selector (`⌘ + ⇧ + 7`), featuring multi-window batch capture and an aspect-ratio-matched preview window with Copy (`⌘C`), Save As, and Cloud Upload.
- **📜 Scrolling Capture**: Stitch multiple screenshots together for entire webpages or long documents (`⌘ + ⇧ + 8`).
- **🎨 Live Annotation Tools**: Draw rectangles, lines, arrows, custom highlights, overlay rich text, or wipe canvas shapes with "Clear All" (undoable via `⌘Z`).
- **🔒 Sensitive Content Redaction**: Apply manual blur, pixelate, or solid cover masks, or rely on automatic on-device redaction (Accessibility + Vision OCR) for passwords, credit cards (Luhn-validated), API keys/tokens, emails, phone numbers, and custom terms under configurable policies (Off / Suggest / Required).
- **🔍 100% Local OCR**: Perform lightning-fast, offline Optical Character Recognition (OCR) to copy text from screen selections instantly.
- **🤖 Cloud & AI Assistant Integration**:
  - Connect captures to AI models (Gemini, Claude, OpenAI, OpenRouter, and Xiaomi Mimo) to summarize code, translate, or extract data.
  - Choose your output language and customize prompt templates.
- **🤝 Local MCP Server**: Connect local AI coding agents (Claude Code, Codex) over private local IPC to list apps/windows, capture with redaction, or run guarded documentation sessions with strict action allowlists and persistent menu-bar session status.
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

1. **DMG Installer**: Download [BerryShot.dmg](https://download-shot.berryhub.app/BerryShot.dmg), open it, and drag BerryShot into your Applications folder.
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

## 🤝 Agent Integration (MCP)

BerryShot ships a small, separate stdio [MCP](https://modelcontextprotocol.io/) helper executable inside the app bundle, at a fixed location:

```text
/Applications/BerryShot.app/Contents/Helpers/BerryShotMCP
```

(or `<wherever you installed BerryShot>/Contents/Helpers/BerryShotMCP` if not installed in `/Applications`). The helper only speaks MCP stdio and a private, same-user, authenticated local IPC connection to the BerryShot GUI — it never opens a network port, never calls ScreenCaptureKit/Accessibility directly, and never becomes a background daemon (it starts when an MCP client spawns it and exits when that client disconnects). BerryShot itself remains the sole holder of the Screen Recording/Accessibility permissions and must be running with **Settings → Privacy → Agent Integration (MCP)** turned on before a client can connect.

### Codex

```toml
[mcp_servers.berryshot]
command = "/Applications/BerryShot.app/Contents/Helpers/BerryShotMCP"
startup_timeout_sec = 10
tool_timeout_sec = 60
required = false
```

### Claude Code

```bash
claude mcp add berryshot -- /Applications/BerryShot.app/Contents/Helpers/BerryShotMCP
```

or add it directly to `.mcp.json` / `~/.claude.json`:

```json
{
  "mcpServers": {
    "berryshot": {
      "type": "stdio",
      "command": "/Applications/BerryShot.app/Contents/Helpers/BerryShotMCP",
      "args": []
    }
  }
}
```

### Tool Tiers & Security Policy

BerryShot MCP provides two distinct tool tiers for agent clients:

1. **Read-only Discovery & Capture Tools**: List running applications and windows, capture a window or full application with automatic/manual redaction applied, and fetch capture manifests. Results return a bounded inline preview (long edge ≤960px) plus an artifact ID; full-resolution images and OCR text are fetched lazily as MCP resources only when requested. Artifacts expire automatically after 24 hours (or under 500 MiB / 200-artifact quota limits).
2. **Guarded Documentation Sessions**: Enables agent-driven UI exploration and documentation generation. A session is strictly locked to a single allowlisted application (never a different app). Allowed UI interactions are restricted to a safe subset (press, show menu, increment, decrement, set plain text field value); secure input fields and destructive or external side-effect controls are rejected by policy. A persistent menu-bar indicator displays active session details (target app, mode, elapsed time) with a one-click Stop control.

Every capture performed via MCP is subject to the same manual and automatic redaction policy as GUI captures.

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

You may use, modify, and share it freely for **any noncommercial purpose** — personal use, study, research, hobby projects, and use by nonprofits, schools, or government. **Commercial use is not permitted.** For commercial licensing, contact [info@notex.work](mailto:info@notex.work).

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
