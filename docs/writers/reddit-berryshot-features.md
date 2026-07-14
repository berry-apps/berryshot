# Reddit Posts - BerryShot Feature Promotion

> **Perspective**: User discovered the app, sharing because it fits their needs perfectly. Not the developer.

---

## Post 1: r/macapps - Genuine Recommendation

**Title:** A native macOS screenshot tool with offline OCR and annotations - BerryShot (free & open source)

**Body:**

Hi everyone,

I wanted to share a menu bar screenshot utility for macOS that I've been using/following called **BerryShot**. It's fully open source (MIT license) and native.

**What makes it stand out:**

- **Region capture** (`⌘ + ⇧ + 1`) and scrolling capture.
- **Annotation before saving** - rectangles, arrows, blur, highlights, numbered markers - all in the overlay.
- **100% offline OCR** - select any area, text gets extracted instantly using Apple's Vision framework (no data leaves your machine).
- **Screen recording** - HEVC 60fps with system audio + microphone.
- **Screenshot history** - browse past captures locally via SwiftData.
- **Optional AI features** - if you connect your own API keys (Gemini, Claude, OpenAI, OpenRouter) to analyze code or translate text.

It's really fast since it's native Swift and ScreenCaptureKit. 

Code is here: https://github.com/berry-apps/berryshot

I think it's a great free alternative to paid tools like CleanShot X or Shottr if you want something open source and local-first.

---

## Post 2: r/opensource - Found This Gem

**Title:** BerryShot - Native macOS screenshot utility with local Vision OCR, annotations & screen recording (MIT)

**Body:**

Hi all,

I wanted to share **BerryShot**, a native macOS menu bar app for screenshots, annotations, and offline OCR. It's written in Swift 6 and SwiftUI, and is fully open-source under the MIT license.

**Key features:**

- **Native capture overlay** using ScreenCaptureKit (launches in <500ms)
- **100% local OCR** using Apple's Vision framework (everything is local, no external servers)
- **Live annotation overlay** (shapes, text, blur/pixelate, step markers)
- **Scrolling capture** for long documents and webpages
- **60fps HEVC screen recording** (with mic and system audio)
- **Local history store** via SwiftData

Since it's built with native frameworks, it's very lightweight and respects privacy by keeping credentials in Keychain and processing OCR entirely offline.

Source code and build instructions: https://github.com/berry-apps/berryshot

Any feedback on the code or features is highly appreciated!

---

## Post 3: r/macOS - Tool Discovery

**Title:** Free open-source alternative to paid Mac screenshot & OCR tools

**Body:**

Hey guys,

If you are looking for a native, free screenshot tool that does OCR locally, check out **BerryShot**. It's an open-source utility that sits in your menu bar.

Instead of taking a screenshot, opening Preview to annotate, and then copying it into another app for text extraction, this does it all in one overlay:

1. Press `⌘ + ⇧ + 1` to capture.
2. Annotate (draw, blur private text, add step markers).
3. Click OCR to copy text locally using Apple's Vision framework (no data sent to cloud).
4. Save locally or auto-upload to Google Drive/custom endpoints.

It also does scrolling captures and 60fps screen recording. It's built with native Swift/SwiftUI and ScreenCaptureKit, so it is super fast and low on memory.

Repository: https://github.com/berry-apps/berryshot

Hope this helps anyone looking to simplify their screenshot flow!

---

## Post 4: r/SideProject - Cool Find

**Title:** Show SideProject: BerryShot - a native macOS screenshot & offline OCR tool built in Swift 6

**Body:**

Hey everyone,

I've been working on/contributing to **BerryShot**, a native macOS menu bar app designed to combine screen capture, annotations, offline OCR, and optional integrations into a single utility.

**Why build it?**

Most screenshot tools on macOS are either closed-source/paid (like CleanShot X, Shottr) or don't support offline OCR out-of-the-box. I wanted a fast, native tool that keeps everything local and private.

**Tech stack & features:**

- **Capture:** ScreenCaptureKit for quick region/window captures.
- **OCR:** Native Apple Vision framework (100% offline text extraction).
- **Annotations:** Custom SwiftUI canvas for live shapes, text, blur, and numbered step markers.
- **Storage & History:** SwiftData for offline screenshot history.
- **Recording:** ScreenCaptureKit for 60fps HEVC screen recording with dual-channel audio.
- **Optional AI integration:** Configurable with custom endpoints or your own keys (Claude, Gemini, etc.) if you want AI analysis.

It is completely free and MIT-licensed.

Check it out on GitHub: https://github.com/berry-apps/berryshot

Would love to hear your thoughts on the code or any feature suggestions!

---

## Post 5: r/productivity - Workflow Improvement

**Title:** Simplify your screenshot and OCR workflow on macOS (Free & Open Source)

**Body:**

Hey all,

Just wanted to share a workflow improvement for anyone who takes a lot of screenshots, extracts text, or creates step-by-step guides.

**BerryShot** is a native macOS menu bar app that brings region capture, annotation, and offline OCR into one shortcut.

**What's cool about it:**

- **Instant region capture:** Launches immediately with a global hotkey.
- **Draw & Blur:** You can draw arrows, rectangles, or blur sensitive data directly on the screen before saving.
- **Offline OCR:** Extracts text from any captured area instantly using Apple's Vision framework (no internet needed, completely private).
- **Step markers:** Easily add numbered badges for documentation or tutorials.
- **Screen recording:** 60fps HEVC format with internal audio.

Since it is open-source (MIT licensed) and native Swift, it's fast and doesn't run background electron processes.

Check it out: https://github.com/berry-apps/berryshot

Hope it helps boost your productivity!

---

## Suggested Subreddits for Posting:

1. **r/macapps** - Primary target, macOS app enthusiasts
2. **r/opensource** - Open-source community
3. **r/macOS** - General macOS users
4. **r/SideProject** - Developer/maker community
5. **r/productivity** - Productivity tool users
6. **r/screenshots** - Screenshot enthusiasts
7. **r/mac** - General Mac community
8. **r/software** - Software recommendations

---

## Posting Tips to Avoid Reddit's Spam Filter:

1. **Do not use the `.work` link:** Reddit's site-wide spam filter flags newer or uncommon TLDs like `.work` automatically. **Only link to the GitHub repository** (`github.com/berry-apps/berryshot`). GitHub links are highly trusted by Reddit and will pass the filters.
2. **Post as Markdown:** Use Reddit's Markdown editor mode rather than the Rich Text editor to keep the layout clean and natural.
3. **Keep the tone organic:** Avoid overly hype-filled, PR, or marketing phrases. The posts above have been rewritten to sound like a normal user sharing a useful utility.
4. **Account age & karma:** If your account is very new or has low karma, some subreddits (like r/opensource or r/macapps) will automatically filter out posts with any links. If this happens, post the text **without any links**, and then add the GitHub link in a comment under the post.
5. **Timing**: Post during US business hours (9am-5pm EST) for maximum visibility.
6. **Engagement**: Reply to every comment within the first hour to boost the post's organic ranking.
