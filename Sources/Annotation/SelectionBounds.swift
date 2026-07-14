import Foundation
import CoreGraphics

/// Geometry helpers that keep annotations inside the capture selection.
/// The exported image is cropped to the selection, so anything drawn past its
/// edges is silently chopped off — clamp the pointer instead of letting it escape.
///
/// Every helper is a no-op on an empty rect, so they are safe to call before a
/// region has been selected.
extension CGRect {
    /// Nearest point that still lies inside the rect.
    func clamping(_ point: CGPoint) -> CGPoint {
        guard !isEmpty else { return point }
        return CGPoint(
            x: min(max(point.x, minX), maxX),
            y: min(max(point.y, minY), maxY)
        )
    }

    /// Corner of the largest square anchored at `start` growing toward `point`,
    /// shrunk until it fits. Backs the shift-constrained rectangle/circle tools.
    func clampingSquareCorner(from start: CGPoint, toward point: CGPoint) -> CGPoint {
        let target = clamping(point)
        let dx = target.x - start.x
        let dy = target.y - start.y

        var side = max(abs(dx), abs(dy))
        if !isEmpty {
            let roomX = max(0, dx < 0 ? start.x - minX : maxX - start.x)
            let roomY = max(0, dy < 0 ? start.y - minY : maxY - start.y)
            side = min(side, min(roomX, roomY))
        }

        return CGPoint(
            x: start.x + (dx < 0 ? -side : side),
            y: start.y + (dy < 0 ? -side : side)
        )
    }

    /// Translation shortened so that `box` stays inside. A box too large to fit is
    /// pinned to the top-left edge rather than allowed to drift out.
    func clampingTranslation(_ translation: CGSize, of box: CGRect) -> CGSize {
        guard !isEmpty else { return translation }

        let minDx = minX - box.minX
        let maxDx = maxX - box.maxX
        let minDy = minY - box.minY
        let maxDy = maxY - box.maxY

        return CGSize(
            width: min(max(translation.width, minDx), max(minDx, maxDx)),
            height: min(max(translation.height, minDy), max(minDy, maxDy))
        )
    }
}
