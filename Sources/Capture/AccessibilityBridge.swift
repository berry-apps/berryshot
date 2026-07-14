import Foundation
import AppKit
@preconcurrency import ApplicationServices

/// Wraps AXUIElement interactions for scroll capture.
public class AccessibilityBridge {

    // MARK: - Public Types

    public struct ScrollInfo {
        public let currentVertical: CGFloat   // 0.0 ... 1.0
        public let currentHorizontal: CGFloat // 0.0 ... 1.0
        public let canScrollDown: Bool
        public let canScrollUp: Bool
    }

    // MARK: - Private

    private let appElement: AXUIElement
    private var scrollAreaElement: AXUIElement?

    // MARK: - Init

    public init(pid: pid_t) {
        self.appElement = AXUIElementCreateApplication(pid)
    }

    // MARK: - Find Scroll Area

    /// Traverse the AX hierarchy of the frontmost window to locate the primary scroll area.
    @discardableResult
    public func findScrollableArea() -> AXUIElement? {
        guard let focusedWindow = getFocusedWindow() else { return nil }
        if let found = findScrollArea(in: focusedWindow, maxDepth: 8) {
            self.scrollAreaElement = found
            return found
        }
        return nil
    }

    private func getFocusedWindow() -> AXUIElement? {
        var windowRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef)
        guard result == .success else { return nil }
        // swiftlint:disable:next force_cast
        return (windowRef as! AXUIElement)
    }

    private func findScrollArea(in element: AXUIElement, maxDepth: Int) -> AXUIElement? {
        guard maxDepth > 0 else { return nil }

        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        if let role = roleRef as? String, role == kAXScrollAreaRole {
            return element
        }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }

        // Prefer larger children (more likely to be main content)
        let sorted = children.sorted { sizeOf($0) > sizeOf($1) }

        for child in sorted {
            if let found = findScrollArea(in: child, maxDepth: maxDepth - 1) {
                return found
            }
        }
        return nil
    }

    private func sizeOf(_ element: AXUIElement) -> CGFloat {
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let sizeValue = sizeRef,
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return 0 }
        var size = CGSize.zero
        // swiftlint:disable:next force_cast
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return size.width * size.height
    }

    // MARK: - Scroll Control

    /// Scroll down by `lines` lines using CGEvent scroll wheel.
    public func scrollDown(lines: Int = 5) {
        postScrollEvent(deltaY: -Int32(lines))
    }

    /// Scroll to top using CGEvent (many up scrolls).
    public func scrollToTop() {
        // Try AX first
        if let el = scrollAreaElement {
            setScrollBarValue(0.0, in: el)
        }
        // Also post keyboard Home to force scroll to top
        postKeyEvent(keyCode: 0x73) // Home key
    }

    /// Set the vertical scroll bar to a normalized value (0.0 = top, 1.0 = bottom).
    private func setScrollBarValue(_ normalizedValue: CGFloat, in scrollArea: AXUIElement) {
        var vertBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(scrollArea, kAXVerticalScrollBarAttribute as CFString, &vertBarRef) == .success,
              let vertBar = vertBarRef else { return }
        // swiftlint:disable:next force_cast
        let barEl = vertBar as! AXUIElement

        // Get min/max to compute absolute value
        let minVal = getScrollBarNumericAttribute(kAXMinValueAttribute, from: barEl) ?? 0
        let maxVal = getScrollBarNumericAttribute(kAXMaxValueAttribute, from: barEl) ?? 1
        let target = minVal + normalizedValue * (maxVal - minVal)
        let targetNum = target as CFNumber
        AXUIElementSetAttributeValue(barEl, kAXValueAttribute as CFString, targetNum)
    }

    private func getScrollBarNumericAttribute(_ attr: String, from element: AXUIElement) -> CGFloat? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success,
              let val = ref else { return nil }
        // AX scroll bar values come back as CFNumber
        if CFGetTypeID(val) == CFNumberGetTypeID() {
            var result: CGFloat = 0
            CFNumberGetValue((val as! CFNumber), .cgFloatType, &result)
            return result
        }
        return nil
    }

    private func postScrollEvent(deltaY: Int32) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil,
                                  units: .line,
                                  wheelCount: 1,
                                  wheel1: deltaY,
                                  wheel2: 0,
                                  wheel3: 0) else { return }
        event.post(tap: .cghidEventTap)
    }

    private func postKeyEvent(keyCode: CGKeyCode) {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - Scroll Position

    /// Get the current vertical scroll position (0.0 = top, 1.0 = bottom).
    public func getScrollInfo() -> ScrollInfo {
        guard let el = scrollAreaElement else {
            // If we can't find the scroll area, assume we can scroll and fallback to visual diffing
            return ScrollInfo(currentVertical: 0, currentHorizontal: 0, canScrollDown: true, canScrollUp: true)
        }

        var vertBarRef: CFTypeRef?
        var normalized: CGFloat = 0

        if AXUIElementCopyAttributeValue(el, kAXVerticalScrollBarAttribute as CFString, &vertBarRef) == .success,
           let vertBar = vertBarRef {
            // swiftlint:disable:next force_cast
            let barEl = vertBar as! AXUIElement
            let currentVal = getScrollBarNumericAttribute(kAXValueAttribute, from: barEl) ?? 0
            let minVal = getScrollBarNumericAttribute(kAXMinValueAttribute, from: barEl) ?? 0
            let maxVal = getScrollBarNumericAttribute(kAXMaxValueAttribute, from: barEl) ?? 1
            let range = maxVal - minVal
            normalized = range > 0 ? (currentVal - minVal) / range : 0
        }

        return ScrollInfo(
            currentVertical: normalized,
            currentHorizontal: 0,
            canScrollDown: normalized < 0.999,
            canScrollUp: normalized > 0.001
        )
    }

    // MARK: - Frame

    /// Returns the frame of the scroll area element in screen coordinates.
    public func getScrollAreaFrame() -> CGRect? {
        guard let el = scrollAreaElement else { return nil }
        return frameOf(el)
    }

    public func frameOf(_ element: AXUIElement) -> CGRect? {
        var originRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &originRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success else {
            return nil
        }
        guard let ov = originRef, CFGetTypeID(ov) == AXValueGetTypeID(),
              let sv = sizeRef, CFGetTypeID(sv) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        // swiftlint:disable:next force_cast
        AXValueGetValue(ov as! AXValue, .cgPoint, &origin)
        // swiftlint:disable:next force_cast
        AXValueGetValue(sv as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }
}
