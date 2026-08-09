import SwiftUI
import AppKit

/// Shared across every Settings tab so the window's height cap tracks the
/// actual display instead of a number picked for one developer's monitor —
/// 700pt is enormous on a small laptop panel and cramped on a large one.
enum SettingsSizing {
    static var maxContentHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 900) * 0.8
    }
}

/// Each tab reports its own unclipped content height by attaching a
/// `GeometryReader` behind its ScrollView's direct content (before the
/// ScrollView's own `.frame(maxHeight:)` clips it) — this is the only value
/// that reflects what that tab actually needs, as opposed to whatever size
/// the window happens to already be.
struct SettingsContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        // TabView still constructs every tab's content (not just the
        // selected one), so more than one tab can contribute a value here.
        // An off-screen/unlaid-out tab reports 0 rather than a real height,
        // so max() reliably keeps whichever tab actually has real geometry
        // — in practice that's always the one currently selected.
        value = max(value, nextValue())
    }
}

/// Same idea as `SettingsContentHeightKey`, but measures the ScrollView's
/// own currently-available viewport (its `.background`, not its child's)
/// instead of the content inside it. The window's content view includes
/// the native tab-switcher bar above the ScrollView, so `window.contentView`
/// height is always taller than this by that bar's height — comparing the
/// two is how `SettingsWindowAccessor` derives that non-ScrollView overhead
/// without hardcoding a toolbar height that could change with OS version,
/// font size, or tab count.
struct SettingsViewportHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// A `TabView`-backed macOS Settings window does not resize itself when the
/// selected tab changes — it keeps whatever size the union of every tab it
/// has ever hosted settled on. SwiftUI's declarative `.frame()` has no way
/// to force the actual NSWindow to shrink back down, so this bridges to
/// AppKit directly: given the currently measured content height (reported
/// by `SettingsContentHeightKey`) and the ScrollView's own currently
/// available viewport height (`SettingsViewportHeightKey`), it resizes the
/// real window to fit that content exactly, capped at
/// `SettingsSizing.maxContentHeight` — correcting for the native
/// tab-switcher bar's own height so a tab whose content already fits
/// doesn't end up with a few points of forced, unnecessary scroll.
private struct SettingsWindowAccessor: NSViewRepresentable {
    let contentHeight: CGFloat
    let viewportHeight: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        scheduleApply(contentHeight: contentHeight, viewportHeight: viewportHeight, view: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        scheduleApply(contentHeight: contentHeight, viewportHeight: viewportHeight, view: nsView)
    }

    // The NSView isn't necessarily attached to its NSWindow yet at the
    // moment SwiftUI calls make/updateNSView (window is still nil right
    // after initial mount). Always re-check one runloop turn later with
    // THIS call's own values — never ones captured by an earlier, possibly
    // stale call — so whichever call ends up running last (after the
    // window is actually attached) applies the correct, current size.
    private func scheduleApply(contentHeight: CGFloat, viewportHeight: CGFloat, view: NSView) {
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window, contentHeight > 0, viewportHeight > 0 else { return }
            let windowContentHeight = window.contentView?.frame.height ?? window.frame.height
            let chrome = max(0, windowContentHeight - viewportHeight)
            let idealTotal = max(contentHeight, 200) + chrome
            let targetHeight = min(idealTotal, SettingsSizing.maxContentHeight)
            guard abs(windowContentHeight - targetHeight) > 1 else { return }
            let currentWidth = window.contentView?.frame.width ?? window.frame.width
            window.setContentSize(NSSize(width: currentWidth, height: targetHeight))
        }
    }
}

private var resourceBundle: Bundle? {
    let candidates = [
        Bundle.main.bundlePath + "/Contents/Resources/BerryShot_BerryShot.bundle",
        Bundle.main.bundlePath + "/Contents/Resources/BerryShot_BerryShot_BerryShot.bundle"
    ]
    for path in candidates {
        if let bundle = Bundle(path: path) { return bundle }
    }
    return nil
}

private enum SettingsTab: Hashable {
    case general, storage, privacy, ai, about
}

struct SettingsView: View {
    // Deliberately no shared .frame() here: a single fixed size forced every
    // tab to the same height regardless of how much content it actually has
    // (previously 700pt, clipping-avoidance for the longest tab left every
    // shorter tab mostly empty). Each tab instead sets its own
    // `.frame(width: 550)` + `.frame(maxHeight: SettingsSizing.maxContentHeight)`
    // on its own ScrollView, so the window naturally resizes per tab to fit
    // that tab's content, capped at 80% of the actual screen height with
    // scroll as the fallback past that cap.
    //
    // That per-tab frame alone isn't enough: a TabView-backed macOS Settings
    // window computes its size once from the union of every tab it has ever
    // hosted and does not shrink again when switching to a smaller tab.
    // `.id(selectedTab)` forces SwiftUI to tear down and rebuild the
    // TabView's hosting view on every tab change (so the freshly-mounted
    // tab reports its own height instead of a stale one), and
    // `SettingsWindowAccessor` below then explicitly resizes the real
    // NSWindow to that measured height, since SwiftUI's own layout
    // negotiation never resizes the window on its own here.
    @State private var selectedTab: SettingsTab = .general
    @State private var measuredContentHeight: CGFloat = 0
    @State private var measuredViewportHeight: CGFloat = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(SettingsTab.general)
            StorageSettingsView()
                .tabItem {
                    Label("Storage", systemImage: "externaldrive.fill")
                }
                .tag(SettingsTab.storage)
            PrivacySettingsView()
                .tabItem {
                    Label("Privacy", systemImage: "hand.raised.fill")
                }
                .tag(SettingsTab.privacy)
            AISettingsView()
                .tabItem {
                    Label("AI", systemImage: "sparkles")
                }
                .tag(SettingsTab.ai)
            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(SettingsTab.about)
        }
        .id(selectedTab)
        .onPreferenceChange(SettingsContentHeightKey.self) { height in
            measuredContentHeight = height
        }
        .onPreferenceChange(SettingsViewportHeightKey.self) { height in
            measuredViewportHeight = height
        }
        .background(SettingsWindowAccessor(contentHeight: measuredContentHeight, viewportHeight: measuredViewportHeight))
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            if let bundle = resourceBundle,
               let url = bundle.url(forResource: "AppIcon", withExtension: "png"),
               let iconImage = NSImage(contentsOf: url) {
                NSApp.applicationIconImage = iconImage
            }
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
