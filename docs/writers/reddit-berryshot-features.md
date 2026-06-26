# Reddit Posts - BerryShot Feature Promotion

> **Perspective**: User discovered the app, sharing because it fits their needs perfectly. Not the developer.

---

## Post 1: r/macapps - Genuine Recommendation

**Title:** Finally found a macOS screenshot tool that does everything I need - and it's free

**Body:**

Been searching for a good screenshot tool on macOS for months. Tried CleanShot X, Shottr, Monosnap... they all lacked something. Then I stumbled upon **BerryShot** and honestly it checks every box.

**What makes it stand out:**

- **`⌘ + ⇧ + 1` region capture** - super fast, launches instantly
- **Annotation before saving** - rectangles, arrows, blur, highlights, numbered markers - all in the overlay, no need to open another editor
- **100% offline OCR** - select any area, text gets extracted instantly. No internet, no cloud, no privacy concerns
- **AI integration** - this is the killer feature for me. Connects to Gemini, Claude, OpenAI, OpenRouter. I use it to summarize code screenshots and translate text from images
- **Scrolling capture** - finally works for long webpages and chat logs
- **Auto-upload to Google Drive** or custom HTTP endpoint with bearer token support
- **Screenshot history** - browse all past captures locally

**Why it fits my workflow:**

I'm a developer and I constantly need to:
- Capture code snippets → AI summarizes or extracts clean code
- Screenshot UI bugs → annotate with arrows and blur sensitive info
- Extract text from PDFs/images → OCR copies to clipboard instantly
- Share screenshots → auto-uploads and copies link

Before this I was juggling 3-4 different tools. Now it's just one menu bar app.

**Downsides:**
- Requires macOS 14.0+
- AI features need API keys (but OCR is fully offline)
- UI is functional but not the most polished

**Download:** https://notex.work

It's open-source and MIT licensed. Worth a try if you're still looking for that "one screenshot tool to rule them all."

---

## Post 2: r/opensource - Found This Gem

**Title:** Found an open-source macOS screenshot tool with OCR and multi-model AI support - BerryShot

**Body:**

Came across **BerryShot** recently while looking for a privacy-focused screenshot tool. It's MIT-licensed and surprisingly feature-rich for something I'd never heard of before.

**What caught my attention:**

- Native macOS app, lives in the menu bar
- Region/window/full screen capture with global hotkey
- Rich annotation tools (blur, pixelate, numbered markers, highlights)
- **100% local OCR** using Apple's Vision framework - no data leaves your machine
- Multi-model AI: Gemini, Claude, OpenAI, OpenRouter, Xiaomi Mimo
- Scrolling screenshot capture
- Screen recording (HEVC 60fps with audio)
- Cloud upload to Google Drive or custom HTTP endpoints
- Screenshot history with local SwiftData storage
- All credentials stored in macOS Keychain

**Why I like it:**

The offline OCR alone makes it worth it. But the AI integration is what sets it apart - I can capture a code screenshot and have Claude summarize it, or capture text in another language and get an instant translation.

It uses ScreenCaptureKit and Vision framework, so it's properly native and fast. Launches in under 500ms.

**Download:** https://notex.work

Anyone else using this? Curious how it compares to Shottr or CleanShot X for your workflows.

---

## Post 3: r/macOS - Tool Discovery

**Title:** Tired of switching between screenshot, OCR, and AI tools? This menu bar app combines all three

**Body:**

I used to have this workflow:
1. Screenshot with macOS built-in
2. Open in Preview to annotate
3. Copy to another app for OCR
4. Switch to browser for AI analysis
5. Upload to cloud separately

Found **BerryShot** and now it's:
1. `⌘ + ⇧ + 1` → annotate in overlay → OCR extracts text → AI analyzes → auto-uploads

**The features that sold me:**

**Capture side:**
- Region, window, full screen capture
- Multi-monitor support
- Scrolling capture for long pages
- Screen recording with system audio + mic

**Annotation side:**
- Rectangle, circle, arrow, line, pencil
- Blur and pixelate (great for hiding sensitive info)
- Numbered markers for step-by-step guides
- Text overlay with customizable fonts

**OCR side:**
- 100% offline, uses Apple's Vision framework
- Extracts text from any screen selection
- Works with any language
- Copies to clipboard instantly

**AI side:**
- Multiple providers: Gemini, Claude, OpenAI, OpenRouter
- Summarize code screenshots
- Translate text from images
- Extract structured data
- Customizable prompt templates

**Productivity side:**
- Screenshot history with search
- Auto-upload to Google Drive or custom HTTP
- Pin screenshots on top of other windows
- Color picker tool

**Performance:**
- Launches in under 500ms
- Capture latency under 100ms
- Works completely offline (except AI features)

**Download:** https://notex.work

Free, open-source, MIT licensed. The offline OCR alone is worth it IMO.

---

## Post 4: r/SideProject - Cool Find

**Title:** Stumbled upon an open-source macOS screenshot tool with AI integration - sharing because it's actually good

**Body:**

Not my project, just something I found while browsing GitHub. **BerryShot** is a macOS menu bar app that combines screenshots, annotations, OCR, and AI analysis.

**What it does:**

- `⌘ + ⇧ + 1` for instant region capture
- Live annotation tools (rectangles, arrows, blur, highlights)
- 100% offline OCR using Apple's Vision framework
- Multi-model AI: Gemini, Claude, OpenAI, OpenRouter
- Scrolling capture for entire webpages
- Screen recording (HEVC 60fps with audio)
- Auto-upload to Google Drive or custom HTTP endpoint
- Screenshot history with local storage

**Why I'm sharing:**

I've been looking for a tool that combines OCR and AI for screenshots. Most tools do one or the other. This one does both, and the OCR is completely offline which is a big deal for privacy.

The AI integration is flexible - you can use multiple providers and customize prompt templates. I use it to:
- Summarize code screenshots
- Translate text from images
- Extract data from UI screenshots

**Tech stack:**
- Swift 6.0 + SwiftUI
- ScreenCaptureKit for capture
- Vision framework for OCR
- SwiftData for storage
- macOS 14.0+

**Download:** https://notex.work

Worth checking out if you need a comprehensive screenshot tool. It's free and open-source.

---

## Post 5: r/productivity - Workflow Improvement

**Title:** This free macOS app eliminated 3 tools from my screenshot workflow

**Body:**

I used to use:
- **Shottr** for screenshots
- **TextSniper** for OCR
- **CleanShot X** for annotations
- Browser for AI analysis

Then I found **BerryShot** and it replaced all of them.

**What it does:**

1. **Capture**: `⌘ + ⇧ + 1` for region capture. Also supports window, full screen, and scrolling capture.

2. **Annotate**: Draw on the screenshot before saving - rectangles, arrows, blur, highlights, numbered markers. No need to open a separate editor.

3. **OCR**: 100% offline text extraction using Apple's Vision framework. Select any area, text gets copied to clipboard instantly.

4. **AI Analysis**: Connect to Gemini, Claude, OpenAI, or OpenRouter. Summarize code, translate text, extract data from screenshots.

5. **Upload**: Auto-upload to Google Drive or custom HTTP endpoint. Link gets copied to clipboard.

6. **History**: Browse all past screenshots with search.

**My workflow now:**

1. `⌘ + ⇧ + 1` to capture
2. Annotate with arrows and blur sensitive info
3. OCR extracts text I need
4. AI summarizes or translates if needed
5. Auto-uploads and copies link
6. Done - never left the overlay

**Use cases:**
- Capturing code snippets for documentation
- Extracting text from PDFs or images
- Creating step-by-step guides with numbered markers
- Sharing annotated screenshots with teammates
- Recording screen for tutorials

**Download:** https://notex.work

Free, open-source, works offline. The OCR alone saved me $10/year on TextSniper.

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

## Posting Tips:

1. **Timing**: Post during US business hours (9am-5pm EST) for maximum visibility
2. **Engagement**: Reply to every comment within the first hour
3. **Screenshots**: Include 2-3 screenshots showing the app in action
4. **Demo GIF**: Short GIF showing the capture → annotate → OCR flow
5. **Authenticity**: Don't oversell, mention both pros and cons
6. **Cross-post**: Share across related subreddits with slight variations
7. **Follow-up**: Post updates when new features are added
8. **Comments**: Be helpful, answer questions, don't be defensive
