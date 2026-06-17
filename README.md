# 🍓 BerryShot

[![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-blue.svg)](https://developer.apple.com/macos/)
[![Language](https://img.shields.io/badge/language-Swift%206.0-orange.svg)](https://swift.org/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Source Code](https://img.shields.io/badge/github-berryshot-lightgrey.svg?logo=github)](https://github.com/berry-apps/berryshot)

**BerryShot** is a native, open-source macOS utility that brings robust region screen capture, rich annotation tools, 100% offline OCR extraction, and multi-model AI integrations directly into your macOS Menu Bar.

For precompiled releases, user guides, and developer articles, visit the official site at [dautay.dev](https://dautay.dev).

---

## ✨ Key Features

- **🍓 Native Capture Overlay**: Fast, interactive region selector initiated via keyboard shortcut (`⌘ + ⇧ + 1`) or Menu Bar item.
- **🎨 Live Annotation Tools**: Draw rectangles, lines, arrows, custom highlights, and overlay rich text on the canvas before completing the capture.
- **🔍 100% Local OCR**: Perform lightning-fast, offline Optical Character Recognition (OCR) to copy text from screen selections instantly.
- **🤖 Cloud & AI Assistant Integration**:
  - Connect captures to AI models (Gemini, Claude, OpenAI, OpenRouter, and Xiaomi Mimo) to summarize code, translate, or extract data.
  - Choose your output language and customize prompt templates.
- **☁️ Multi-Provider Storage**:
  - Save to a default local folder.
  - Automatically upload captures to **Google Drive** or a custom **HTTP POST Endpoint** (with bearer token / API keys security).
- **🔒 Secure Credentials**: All tokens, API keys, and cloud secrets are stored securely in the native **macOS Keychain**.

---

## 🚀 Installation

You can download precompiled versions of BerryShot:

1. **DMG Installer**: Download the [BerryShot.dmg](https://github.com/berry-apps/berryshot/raw/main/landingpage/assets/BerryShot.dmg) package. Open it and drag BerryShot into your Applications folder.
2. **Zip Package**: Download [BerryShot.zip](https://github.com/berry-apps/berryshot/raw/main/landingpage/assets/BerryShot.zip) and extract it directly into `/Applications`.

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

3. To bundle the app properly (generating the `.app` folder, compiling the app icons, signing, and packaging the DMG/Zip):
   ```bash
   ./build_app.sh
   ```
   The generated application bundle will be created at `BerryShot.app`.

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
---

## 🚀 CI/CD Pipeline (Jenkins)

BerryShot includes an automated declarative [Jenkinsfile](Jenkinsfile) pipeline setup in the root workspace to manage landing page deployments. 

### Pipeline Trigger Actions
- **Trigger**: Activates automatically via the `githubPush()` trigger hook when changes are pushed or a pull request is merged into the `main` branch.
- **Workflow Stages**:
  1. **Build macOS Binaries (Optional)**: Automatically triggers `./build_app.sh` on macOS Jenkins runners to compile and sign the latest `.dmg` and `.zip` distribution bundles.
  2. **Verify Code Integrity**: Confirms formatting and structure of static HTML layouts (`index.html` and `docs.html`).
  3. **Local Deployment**: Runs local `rsync` with the `--delete` flag to synchronize *only* the contents of the `landingpage/` folder directly to the local webroot (e.g. `/var/www/berryshot`), leaving all Swift application source code files safely outside the target deployment webroot.

---

## 📄 License

This project is open-source software licensed under the [MIT License](LICENSE).

---

## 🤝 Contributing

Contributions, bug reports, and feature requests are welcome! Feel free to open issues or submit pull requests to the [GitHub Repository](https://github.com/berry-apps/berryshot).
