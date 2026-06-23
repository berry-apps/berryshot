# BerryShot — Monetization & Revenue Feature Plan

## Context

BerryShot is a macOS native menu bar app for screen capture, annotation, OCR, and AI-powered image analysis. Currently free & open-source with a single $10 StoreKit donation. Goal: add monetization through unique, high-value features that users are willing to pay for.

**Target file to modify:** `Sources/App/Store/StoreManager.swift` (existing StoreKit), new files under `Sources/` as noted below.

---

## Revenue Model: Freemium + Pro Subscription

| Tier | Price | Description |
|------|-------|-------------|
| **Free** | $0 | Basic capture, annotation, OCR, 5 AI queries/day |
| **Pro (Monthly)** | $4.99/mo | Unlimited AI, all premium features |
| **Pro (Yearly)** | $29.99/yr | Same as monthly (~50% savings) |
| **Lifetime** | $79.99 | One-time purchase, all Pro features forever |

---

## Phase 1: Foundation — Subscription Infrastructure

### 1.1 StoreKit 2 Subscription System
- **File:** `Sources/App/Store/StoreManager.swift` (refactor existing)
- **New:** `Sources/App/Store/SubscriptionManager.swift`
- **New:** `Sources/App/Store/EntitlementManager.swift`
- Products: monthly, yearly, lifetime IAP
- Receipt validation, restore purchases
- Feature gating with `EntitlementManager` (checks Pro status)
- Free tier: 5 AI queries/day, basic features only

### 1.2 Paywall UI
- **New:** `Sources/App/Paywall/PaywallView.swift`
- **New:** `Sources/App/Paywall/FeatureHighlightView.swift`
- Shown when user hits free limit or tries Pro feature
- Feature comparison table, trial offer (7-day free trial for Pro)
- Native SwiftUI, matches app design language

### 1.3 Usage Tracking & Limits
- **New:** `Sources/App/Store/UsageTracker.swift`
- Track daily AI queries, feature usage (local SwiftData)
- Show usage counter in menu bar dropdown
- Soft paywall: "You've used 5/5 free AI queries today. Upgrade to Pro for unlimited."

---

## Phase 2: AI-Powered Premium Features

### 2.1 Smart Screenshot Summary (AI)
- **File:** `Sources/AI/AIService.swift` (extend)
- **New:** `Sources/App/Features/ScreenshotSummaryService.swift`
- One-click: capture region → AI generates a concise summary of what's on screen
- Use cases: summarize articles, code, emails, chat conversations
- **Gating:** Free = 5/day, Pro = unlimited

### 2.2 AI Translation Overlay
- **New:** `Sources/App/Features/TranslationOverlayService.swift`
- Capture any text on screen → AI translates to target language
- Overlay translation directly on the captured image
- Supports 30+ languages, uses AI provider (not just Google Translate)
- **Gating:** Pro only

### 2.3 AI Code Screenshot → Code Snippet
- **New:** `Sources/App/Features/CodeExtractorService.swift`
- Capture code on screen → AI extracts clean, formatted code
- Auto-detect language, copy to clipboard as runnable code
- Works with dark/light themes, messy screenshots
- **Gating:** Pro only

### 2.4 AI Meeting Minutes Generator (enhanced)
- **File:** `Sources/AI/LiveTranscriptionService.swift` (enhance existing)
- Auto-generate structured meeting minutes: action items, decisions, key points
- Export to Markdown, PDF, or Notion
- Speaker identification (when possible)
- **Gating:** Pro only

### 2.5 AI Image Description / Alt-Text Generator
- **New:** `Sources/App/Features/AltTextGenerator.swift`
- Capture any image/region → AI generates accessibility alt-text
- Useful for web developers, content creators
- Multiple output styles: short, detailed, SEO-optimized
- **Gating:** Free = 3/day, Pro = unlimited

---

## Phase 3: Unique Productivity Features

### 3.1 Scrolling Screenshot (Long Capture)
- **New:** `Sources/App/Features/ScrollCaptureService.swift`
- Capture entire scrollable area (web pages, documents, chat logs)
- Auto-scroll, stitch multiple frames into one long image
- Works with any app that supports accessibility scrolling
- **Gating:** Pro only

### 3.2 Screenshot Comparison (Diff View)
- **New:** `Sources/App/Features/ComparisonView.swift`
- Side-by-side or overlay comparison of two screenshots
- Pixel diff highlighting, opacity slider
- Use cases: UI testing, design review, before/after
- **Gating:** Pro only

### 3.3 Smart Redaction / Privacy Blur
- **New:** `Sources/App/Features/SmartRedactionService.swift`
- AI auto-detects sensitive info: emails, phone numbers, credit cards, names
- One-click blur/redact all sensitive data before sharing
- Manual redaction tool (rectangle blur) also available
- **Gating:** Free = manual blur only, Pro = AI auto-detect

### 3.4 Auto Watermark
- **New:** `Sources/App/Features/WatermarkService.swift`
- Add customizable text/image watermark to screenshots
- Configurable position, opacity, font, size
- Useful for content creators, agencies, IP protection
- **Gating:** Pro only

### 3.5 GIF / Short Video Creator
- **New:** `Sources/App/Features/GIFCreatorService.swift`
- Convert screen recording → optimized GIF
- Adjustable FPS, quality, loop, dimensions
- Auto-trim silence, add captions from transcription
- **Gating:** Pro only

### 3.6 Scheduled / Timed Capture
- **New:** `Sources/App/Features/ScheduledCaptureService.swift`
- Set timer: capture screen every N seconds/minutes
- Useful for monitoring, time-lapse, documentation
- Auto-save to folder with timestamp naming
- **Gating:** Pro only

---

## Phase 4: Developer & Team Features

### 4.1 Bug Report Generator
- **New:** `Sources/App/Features/BugReportService.swift`
- Capture screenshot → auto-generate bug report template
- Includes: screenshot, system info, app version, timestamp, steps to reproduce template
- Export to Jira, Linear, GitHub Issues (via API)
- **Gating:** Pro only

### 4.2 API for Developers
- **New:** `Sources/App/API/LocalAPIService.swift`
- Local HTTP API / CLI tool for automation
- `berryshot capture --region 100,100,500,500 --ocr --output ./out.png`
- Integrates with scripts, CI/CD, Alfred/Raycast workflows
- **Gating:** Pro only

### 4.3 Cloud Sync & Team Sharing
- **New:** `Sources/App/Features/CloudSyncService.swift`
- Sync screenshot history, annotations, settings across Macs via iCloud
- Share annotated screenshots with team members via link
- Team workspace with shared folders
- **Gating:** Pro (individual), Team plan ($9.99/user/mo) for collaboration

### 4.4 Custom Brand Kit
- **New:** `Sources/App/Features/BrandKitService.swift`
- Save brand colors, fonts, logos for consistent annotations
- One-click apply brand style to any annotation
- Useful for social media managers, marketing teams
- **Gating:** Pro only

---

## Phase 5: Marketplace & Extensions

### 5.1 Annotation Templates Store
- **New:** `Sources/App/Marketplace/TemplateStore.swift`
- Pre-built annotation templates: UI review, bug report, tutorial, presentation
- Free templates + premium template packs ($2.99-$4.99 each)
- Community-submitted templates (revenue share)
- **Gating:** Free = 3 templates, Pro = all built-in, marketplace items separate

### 5.2 Custom AI Prompt Marketplace
- **New:** `Sources/App/Marketplace/PromptMarketplace.swift`
- Users create & share custom AI prompt templates
- Popular prompts can be sold ($0.99-$1.99)
- Example: "Extract all TODOs from code screenshot", "Generate test cases from UI"
- **Gating:** Pro only to access marketplace

---

## Implementation Priority

| Priority | Features | Impact | Effort |
|----------|----------|--------|--------|
| **P0** | 1.1-1.3 (Subscription infra + paywall) | 🔴 Critical | High |
| **P1** | 2.1, 2.3, 3.3 (Smart summary, Code extract, Redaction) | 🔴 High | Medium |
| **P1** | 3.1 (Scrolling screenshot) | 🔴 High | High |
| **P2** | 2.2, 2.5, 3.5 (Translation, Alt-text, GIF) | 🟡 Medium | Medium |
| **P2** | 3.2, 3.4, 3.6 (Comparison, Watermark, Scheduled) | 🟡 Medium | Low |
| **P3** | 4.1-4.4 (Dev tools, Cloud sync, Brand kit) | 🟢 Nice-have | High |
| **P3** | 5.1-5.2 (Marketplace) | 🟢 Nice-have | High |

---

## Recommended Starting Point

1. **Implement P0 first**: Subscription system + paywall — this is the revenue backbone
2. **Then P1**: 3-4 killer features that justify Pro subscription
3. **Ship fast**, get user feedback, iterate on P2/P3 based on demand

---

## Verification Plan

- Unit tests for `SubscriptionManager`, `EntitlementManager`, `UsageTracker`
- Test with StoreKit sandbox environment (Xcode StoreKit configuration file)
- Test free tier limits: verify paywall appears after 5 AI queries
- Test subscription flow: purchase → verify entitlement → unlock features → restore purchase
- Test each Pro feature behind the gate: verify free users see paywall, Pro users access feature
- Test edge cases: expired subscription, network offline, restore on new device

---

## Critical Files

| File | Action |
|------|--------|
| `Sources/App/Store/StoreManager.swift` | Refactor: add subscription products |
| `Sources/App/Store/SubscriptionManager.swift` | New: subscription lifecycle |
| `Sources/App/Store/EntitlementManager.swift` | New: feature gating |
| `Sources/App/Store/UsageTracker.swift` | New: usage limits |
| `Sources/App/Paywall/PaywallView.swift` | New: paywall UI |
| `Sources/AI/AIService.swift` | Extend: usage tracking integration |
| `Sources/App/Capture/CaptureCoordinator.swift` | Extend: route through entitlement check |
