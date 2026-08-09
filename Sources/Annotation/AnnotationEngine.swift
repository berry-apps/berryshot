import Foundation
import CoreGraphics
import SwiftUI

public enum AnnotationToolType {
    case select
    case pencil
    case rectangle
    case circle
    case arrow
    case curvedArrow
    case line
    case curvedLine
    case text
    case image
}

public struct BindingAnchor: Equatable, Hashable {
    public let elementId: UUID
    public let pointIndex: Int
}

public struct AnnotationElement: Identifiable {
    public let id = UUID()
    public var type: AnnotationToolType
    public var path: Path
    public var color: Color
    public var lineWidth: CGFloat
    public var isFilled: Bool
    public var fillOpacity: CGFloat
    public var fontSize: CGFloat
    
    public var text: String = ""
    public var startPoint: CGPoint
    public var endPoint: CGPoint
    public var nsImage: NSImage?
    
    public var startBinding: BindingAnchor?
    public var endBinding: BindingAnchor?

    /// Non-nil marks this element as a redaction mask rather than a
    /// decorative annotation. It is always paired with `type == .rectangle`
    /// so the existing rectangle draw/resize/select machinery is reused
    /// as-is; only rendering and export treat redaction elements specially.
    /// Per the spec's "do not call annotation rectangles redaction unless
    /// pixels are flattened" guard, this flag alone never redacts anything —
    /// it only carries the user's chosen style through to
    /// `RedactionRenderer`, which performs the actual flattening.
    public var redactionStyle: RedactionStyle?

    public init(type: AnnotationToolType, startPoint: CGPoint, color: Color = .red, lineWidth: CGFloat = 2, text: String = "", nsImage: NSImage? = nil, isFilled: Bool = false, fillOpacity: CGFloat = 0.4, fontSize: CGFloat = 24, redactionStyle: RedactionStyle? = nil) {
        self.type = type
        self.startPoint = startPoint
        self.endPoint = startPoint
        self.color = color
        self.lineWidth = lineWidth
        self.isFilled = isFilled
        self.fillOpacity = fillOpacity
        self.fontSize = fontSize
        self.path = Path()
        self.text = text
        self.nsImage = nsImage
        self.redactionStyle = redactionStyle
    }
    
    public var hasBindingPoints: Bool {
        switch type {
        case .rectangle, .circle, .text, .line, .curvedLine, .arrow, .curvedArrow, .image:
            return true
        case .pencil, .select:
            return false
        }
    }
    
    public var connectorHandles: [CGPoint] {
        switch type {
        case .rectangle, .circle, .image, .text:
            let minX = min(startPoint.x, endPoint.x)
            let maxX = max(startPoint.x, endPoint.x)
            let minY = min(startPoint.y, endPoint.y)
            let maxY = max(startPoint.y, endPoint.y)
            let midX = (minX + maxX) / 2
            let midY = (minY + maxY) / 2
            let offset: CGFloat = 0 // User requested no offset
            return [
                CGPoint(x: midX, y: minY - offset), // Top
                CGPoint(x: minX - offset, y: midY), // Left
                CGPoint(x: maxX + offset, y: midY), // Right
                CGPoint(x: midX, y: maxY + offset)  // Bottom
            ]
        default: return []
        }
    }
    
    public var bindingPoints: [CGPoint] {
        switch type {
        case .rectangle, .circle, .image, .text:
            return Array(magneticPoints.prefix(8))
        default:
            return magneticPoints
        }
    }
    
    public func bindingPoint(at index: Int) -> CGPoint? {
        let points = bindingPoints
        guard index >= 0, index < points.count else { return nil }
        return points[index]
    }
    
    public mutating func update(currentPoint: CGPoint) {
        endPoint = currentPoint
        rebuildPath()
    }
    
    public mutating func updateBindingPoint(at index: Int, with newPoint: CGPoint, anchor: BindingAnchor?) {
        switch type {
        case .line, .curvedLine, .arrow, .curvedArrow:
            if index == 0 {
                startPoint = newPoint
                startBinding = anchor
            } else if index == 1 {
                endPoint = newPoint
                endBinding = anchor
            }
        case .rectangle, .circle, .image, .text:
            let minX = min(startPoint.x, endPoint.x)
            let maxX = max(startPoint.x, endPoint.x)
            let minY = min(startPoint.y, endPoint.y)
            let maxY = max(startPoint.y, endPoint.y)
            
            var newMinX = minX
            var newMaxX = maxX
            var newMinY = minY
            var newMaxY = maxY
            
            // 0: topLeft, 1: topRight, 2: bottomLeft, 3: bottomRight
            // 4: top, 5: bottom, 6: left, 7: right
            if index == 0 || index == 2 || index == 6 { newMinX = newPoint.x }
            if index == 1 || index == 3 || index == 7 { newMaxX = newPoint.x }
            if index == 0 || index == 1 || index == 4 { newMinY = newPoint.y }
            if index == 2 || index == 3 || index == 5 { newMaxY = newPoint.y }
            
            if newMinX > newMaxX { swap(&newMinX, &newMaxX) }
            if newMinY > newMaxY { swap(&newMinY, &newMaxY) }
            
            if type == .image, let img = nsImage, img.size.height > 0 {
                let ratio = img.size.width / img.size.height
                var width = newMaxX - newMinX
                var height = newMaxY - newMinY
                
                let oldWidth = maxX - minX
                let oldHeight = maxY - minY
                let dw = abs(width - oldWidth)
                let dh = abs(height - oldHeight)
                
                if index == 4 || index == 5 || (dh > dw && index != 6 && index != 7) {
                    // Height drives width
                    width = height * ratio
                    if index == 0 || index == 2 || index == 6 {
                        newMinX = newMaxX - width
                    } else {
                        newMaxX = newMinX + width
                    }
                } else {
                    // Width drives height
                    height = width / ratio
                    if index == 0 || index == 1 || index == 4 {
                        newMinY = newMaxY - height
                    } else {
                        newMaxY = newMinY + height
                    }
                }
            }
            
            startPoint = CGPoint(x: newMinX, y: newMinY)
            endPoint = CGPoint(x: newMaxX, y: newMaxY)
            
        default:
            break
        }
        rebuildPath()
    }
    
    public mutating func rebuildPath() {
        switch type {
        case .pencil:
            break
        case .rectangle, .image, .text:
            path = Path(shapeRect())
        case .circle:
            path = Path(ellipseIn: shapeRect())
        case .line:
            path = Path()
            path.move(to: startPoint)
            path.addLine(to: endPoint)
            
        case .arrow:
            let angle = atan2(endPoint.y - startPoint.y, endPoint.x - startPoint.x)
            let arrowLength: CGFloat = max(20, lineWidth * 3)
            let angle1 = angle + .pi * 5 / 6
            let angle2 = angle - .pi * 5 / 6
            
            let p1 = CGPoint(x: endPoint.x + arrowLength * cos(angle1), y: endPoint.y + arrowLength * sin(angle1))
            let p2 = CGPoint(x: endPoint.x + arrowLength * cos(angle2), y: endPoint.y + arrowLength * sin(angle2))
            
            let stemOffset = max(1.0, lineWidth * 1.5)
            let stemEnd = CGPoint(x: endPoint.x - stemOffset * cos(angle), y: endPoint.y - stemOffset * sin(angle))
            
            path = Path()
            path.move(to: startPoint)
            path.addLine(to: stemEnd)
            path.move(to: p1)
            path.addLine(to: endPoint)
            path.addLine(to: p2)
            
        case .curvedLine:
            let (cp1, cp2) = computeConnectorControlPoints(start: startPoint, end: endPoint, startAnchor: startBinding, endAnchor: endBinding)
            path = Path()
            path.move(to: startPoint)
            path.addCurve(to: endPoint, control1: cp1, control2: cp2)
            
        case .curvedArrow:
            let (cp1, cp2) = computeConnectorControlPoints(start: startPoint, end: endPoint, startAnchor: startBinding, endAnchor: endBinding)
            
            let angle = atan2(endPoint.y - cp2.y, endPoint.x - cp2.x)
            let arrowLength: CGFloat = max(20, lineWidth * 3)
            let angle1 = angle + .pi * 5 / 6
            let angle2 = angle - .pi * 5 / 6
            
            let p1 = CGPoint(x: endPoint.x + arrowLength * cos(angle1), y: endPoint.y + arrowLength * sin(angle1))
            let p2 = CGPoint(x: endPoint.x + arrowLength * cos(angle2), y: endPoint.y + arrowLength * sin(angle2))
            
            let stemOffset = max(1.0, lineWidth * 1.5)
            let stemEnd = CGPoint(x: endPoint.x - stemOffset * cos(angle), y: endPoint.y - stemOffset * sin(angle))
            
            path = Path()
            path.move(to: startPoint)
            path.addCurve(to: stemEnd, control1: cp1, control2: cp2)
            
            path.move(to: p1)
            path.addLine(to: endPoint)
            path.addLine(to: p2)
            
        case .select:
            break
        }
    }
    
    private func computeConnectorControlPoints(start: CGPoint, end: CGPoint, startAnchor: BindingAnchor?, endAnchor: BindingAnchor?) -> (CGPoint, CGPoint) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let absDx = abs(dx)
        let absDy = abs(dy)
        let distance = hypot(dx, dy)
        let offset = max(30, distance * 0.4)
        
        var cp1 = start
        var cp2 = end
        
        func offsetForAnchor(_ anchor: BindingAnchor?, point: CGPoint) -> CGPoint? {
            guard let anchor = anchor else { return nil }
            switch anchor.pointIndex {
            case 4: return CGPoint(x: point.x, y: point.y - offset) // Top -> go up
            case 5: return CGPoint(x: point.x, y: point.y + offset) // Bottom -> go down
            case 6: return CGPoint(x: point.x - offset, y: point.y) // Left -> go left
            case 7: return CGPoint(x: point.x + offset, y: point.y) // Right -> go right
            default: return nil
            }
        }
        
        if let p1 = offsetForAnchor(startAnchor, point: start) { cp1 = p1 }
        if let p2 = offsetForAnchor(endAnchor, point: end) { cp2 = p2 }
        
        if startAnchor == nil && endAnchor == nil {
            if absDx > absDy {
                cp1 = CGPoint(x: start.x + dx / 2, y: start.y)
                cp2 = CGPoint(x: end.x - dx / 2, y: end.y)
            } else {
                cp1 = CGPoint(x: start.x, y: start.y + dy / 2)
                cp2 = CGPoint(x: end.x, y: end.y - dy / 2)
            }
        } else if startAnchor == nil {
            if cp2.x == end.x { cp1 = CGPoint(x: start.x, y: start.y + dy / 2) } else { cp1 = CGPoint(x: start.x + dx / 2, y: start.y) }
        } else if endAnchor == nil {
            if cp1.x == start.x { cp2 = CGPoint(x: end.x, y: end.y - dy / 2) } else { cp2 = CGPoint(x: end.x - dx / 2, y: end.y) }
        }
        
        return (cp1, cp2)
    }
    
    public mutating func updatePencil(currentPoint: CGPoint) {
        guard type == .pencil else { return }
        if path.isEmpty {
            path.move(to: startPoint)
        }
        path.addLine(to: currentPoint)
        startPoint = currentPoint
        endPoint = currentPoint
    }
    
    public var boundingRect: CGRect {
        switch type {
        case .text, .pencil, .rectangle, .circle, .line, .curvedLine, .arrow, .curvedArrow, .image:
            return path.boundingRect.insetBy(dx: -lineWidth, dy: -lineWidth)
        case .select:
            return .zero
        }
    }

    /// Box the element occupies for bounds checks against the capture selection.
    /// Unlike `boundingRect` this carries no stroke padding, so an element drawn
    /// flush against the selection edge is still considered to fit there.
    public var geometryBounds: CGRect {
        switch type {
        case .pencil:
            return path.boundingRect
        case .select:
            return .zero
        case .text, .rectangle, .circle, .line, .curvedLine, .arrow, .curvedArrow, .image:
            return shapeRect()
        }
    }
    
    public func shapeRect() -> CGRect {
        CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: max(abs(endPoint.x - startPoint.x), 1),
            height: max(abs(endPoint.y - startPoint.y), 1)
        )
    }
    
    public func contains(point: CGPoint, tolerance: CGFloat = 30) -> Bool {
        switch type {
        case .select:
            return false
        case .text:
            return boundingRect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .rectangle, .circle:
            let rect = shapeRect()
            let expanded = rect.insetBy(dx: -tolerance, dy: -tolerance)
            guard expanded.contains(point) else { return false }
            if isFilled { return true }
            let inner = rect.insetBy(dx: tolerance, dy: tolerance)
            if inner.width <= 0 || inner.height <= 0 { return true }
            return !inner.contains(point)
        case .image:
            return shapeRect().insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .line, .curvedLine, .arrow, .curvedArrow:
            return distanceFromPoint(point, toLineFrom: startPoint, to: endPoint) <= tolerance
        case .pencil:
            if !path.isEmpty {
                return path.boundingRect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
            }
            return hypot(point.x - startPoint.x, point.y - startPoint.y) <= tolerance
        }
    }
    
    public mutating func move(by translation: CGSize) {
        startPoint.x += translation.width
        startPoint.y += translation.height
        endPoint.x += translation.width
        endPoint.y += translation.height
        
        // Break bindings when the whole element is explicitly moved
        startBinding = nil
        endBinding = nil
        
        switch type {
        case .pencil:
            let transform = CGAffineTransform(translationX: translation.width, y: translation.height)
            path = path.applying(transform)
        case .rectangle, .circle, .line, .curvedLine, .arrow, .curvedArrow, .image, .text:
            rebuildPath()
        case .select:
            break
        }
    }
    
    private func distanceFromPoint(_ point: CGPoint, toLineFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }
        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }
    
    public var magneticPoints: [CGPoint] {
        switch type {
        case .rectangle, .circle, .image, .text:
            let minX = min(startPoint.x, endPoint.x)
            let maxX = max(startPoint.x, endPoint.x)
            let minY = min(startPoint.y, endPoint.y)
            let maxY = max(startPoint.y, endPoint.y)
            let midX = (minX + maxX) / 2
            let midY = (minY + maxY) / 2
            return [
                CGPoint(x: minX, y: minY),
                CGPoint(x: maxX, y: minY),
                CGPoint(x: minX, y: maxY),
                CGPoint(x: maxX, y: maxY),
                CGPoint(x: midX, y: minY),
                CGPoint(x: midX, y: maxY),
                CGPoint(x: minX, y: midY),
                CGPoint(x: maxX, y: midY),
                CGPoint(x: midX, y: midY)
            ]
        case .line, .curvedLine, .arrow, .curvedArrow:
            return [startPoint, endPoint]
        case .select, .pencil:
            return []
        }
    }
}

public struct BindingSnapResult: Equatable {
    public let point: CGPoint
    public let anchor: BindingAnchor
}
