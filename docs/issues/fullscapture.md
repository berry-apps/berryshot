## Overview

Add the ability to capture the **full scrollable content** of an application window — stitching multiple screenshots into a single tall image. This is commonly known as "scroll capture" or "full page capture".

**Use cases:**
- Capture an entire webpage that extends beyond the viewport
- Capture a long document, chat history, or code file
- Capture any scrollable content in any macOS application

## Feasibility Assessment

| Aspect | Status |
|--------|--------|
| ScreenCaptureKit (current) | Only captures visible area — cannot capture off-screen content |
| Accessibility API | **Implemented** ✅ — `AccessibilityBridge.swift` wraps AXUIElement |
| Window enumeration | **Implemented** ✅ — `WindowSelectorView.swift` uses SCShareableContent |
| Image stitching | **Implemented** ✅ — `ImageStitcher.swift` with overlap detection |
| App sandbox | Hardened Runtime (no sandbox) — Accessibility API works if user grants permission |

**Overall difficulty: Medium-High**

## Implementation Completed ✅

### Files Created

| File | Purpose |
|------|---------|
| `Sources/Capture/AccessibilityManager.swift` | Manages Accessibility permission flow |
| `Sources/Capture/AccessibilityBridge.swift` | AXUIElement scroll control & position detection |
| `Sources/Capture/ScrollCaptureManager.swift` | Scroll capture engine with progress tracking |
| `Sources/Capture/ImageStitcher.swift` | Multi-frame image stitching with overlap detection |
| `Sources/Capture/WindowSelectorView.swift` | Window picker UI with thumbnails |
| `Sources/Capture/ScrollCaptureProgressView.swift` | Progress indicator panel |

### Integration Points

| Location | Change |
|----------|--------|
| `Sources/App/BerryShotApp.swift` | Added "Scroll Capture…" menu item (⌘⇧W) |
| `Sources/App/CaptureCoordinator.swift` | Added `startScrollCapture()` and full pipeline |
| `Sources/Capture/ToolbarView.swift` | Added scroll icon button to annotation toolbar |
| `Sources/Capture/OverlayWindowController.swift` | Added ⌘W keyboard shortcut |

## Implementation Checklist

- [x] **Add Accessibility permission support**
  - [x] Add `AXIsProcessTrusted()` check with prompt dialog
  - [x] Create `AccessibilityManager.swift` to handle permission flow
  - [ ] Add `NSAccessibilityUsageDescription` to Info.plist *(add to .xcconfig or entitlements if needed)*

- [x] **Implement window enumeration & selection**
  - [x] Create `WindowSelectorView.swift` — list running apps and their windows via `SCShareableContent`
  - [x] Add UI for user to pick a target window (grid panel with thumbnails)
  - [x] Store selected `SCWindow` reference for capture

- [x] **Build Accessibility bridge (AXUIElement)**
  - [x] Create `AccessibilityBridge.swift` — wrap `AXUIElement` API
  - [x] Implement `findScrollableArea()` — traverse AX hierarchy to locate scroll area
  - [x] Implement `scrollDown()` / `scrollToTop()` — programmatic scrolling via CGEvent
  - [x] Implement `getScrollInfo()` — detect scroll bounds and position
  - [x] Handle edge cases: stuck detection (consecutiveNoMoveCount), timeout

- [x] **Implement scroll capture engine**
  - [x] Create `ScrollCaptureManager.swift`
  - [x] Implement capture loop: scroll → wait → capture → repeat
  - [x] Add configurable scroll step size and delay between captures
  - [x] Implement end-of-content detection (scroll position unchanged)
  - [x] Add timeout and max-capture limits for safety
  - [x] Show progress indicator during capture (`ScrollCaptureProgressView.swift`)

- [x] **Implement image stitching**
  - [x] Create `ImageStitcher.swift`
  - [x] Detect overlap region between consecutive captures (pixel matching)
  - [x] Crop duplicate content from each frame
  - [x] Concatenate images vertically into final result
  - [x] Handle fixed/sticky elements (stickyHeaderHeight, stickyFooterHeight options)

- [x] **Integration with existing capture flow**
  - [x] Add "Scroll Capture" to menu bar menu (⌘⇧W)
  - [x] Add keyboard shortcut ⌘W from overlay window
  - [x] Add scroll button to annotation toolbar
  - [x] Route captured image through existing annotation/save/upload pipeline
  - [x] Add scroll capture to history (via HistoryService.shared.save)

- [ ] **Testing & polish**
  - [ ] Test with Safari, Chrome, Firefox (webpages)
  - [ ] Test with Terminal, VS Code, Notes, Preview (native scroll views)
  - [ ] Test edge cases: very long content, horizontal scroll, nested scroll views
  - [ ] Performance optimization for large captures

## Technical Notes

### How Scroll Detection Works
1. AX scroll bar value is read as `CFNumber` via `kAXValueAttribute`
2. Normalized to 0.0–1.0 using `(current - min) / (max - min)`
3. "Stuck" detection: if position doesn't change for 3 consecutive frames, capture stops

### How Overlap Stitching Works
1. Sample a horizontal strip from bottom of previous frame and top of current frame
2. Compare pixel values (every 8px) to find matching rows
3. Crop duplicate rows from top of each frame before concatenating

### Keyboard Shortcuts Added
- **⌘W** — Start Scroll Capture from overlay window
- **⌘⇧W** — Start Scroll Capture from menu bar

## Future Enhancements (out of scope for v1)
- App-specific adapters for better compatibility
- Horizontal scroll capture
- Selective region scroll capture (only capture a portion of the scroll area)
- Auto-detect scrollable content without manual window selection

## Related
- Current capture implementation: `Sources/Capture/ScreenCaptureManager.swift`
- Scroll capture manager: `Sources/Capture/ScrollCaptureManager.swift`
- Image stitcher: `Sources/Capture/ImageStitcher.swift`