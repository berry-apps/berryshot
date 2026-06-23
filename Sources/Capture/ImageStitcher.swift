import Foundation
import CoreGraphics
import AppKit

/// Stitches multiple screenshot frames into a single tall image.
public class ImageStitcher {

    public struct StitchOptions {
        /// How many rows of pixels at the bottom of each frame to use for overlap detection.
        public var overlapSearchHeight: Int = 100
        /// Minimum overlap (pixels) to strip from duplicate content. Set 0 to disable auto-detection.
        public var minOverlap: Int = 0
        /// If overlap detection fails, fallback to this fixed strip height (in pixels).
        public var fallbackStrip: Int = 0
        /// Strip header/footer bands that appear in every frame (sticky elements).
        /// Positive = strip from top; negative = strip from bottom.
        public var stickyHeaderHeight: Int = 0
        public var stickyFooterHeight: Int = 0

        public init() {}
    }

    // MARK: - Public API

    /// Stitch frames top-to-bottom, removing overlapping duplicate rows.
    public static func stitch(frames: [CGImage], options: StitchOptions = StitchOptions()) -> CGImage? {
        guard !frames.isEmpty else { return nil }
        if frames.count == 1 { return frames[0] }
        
        var opts = options
        if opts.stickyHeaderHeight == 0 && frames.count >= 2 {
            opts.stickyHeaderHeight = detectStickyHeader(frame1: frames[0], frame2: frames[1])
        }
        if opts.stickyFooterHeight == 0 && frames.count >= 2 {
            opts.stickyFooterHeight = detectStickyFooter(frame1: frames[0], frame2: frames[1])
        }

        var croppedFrames: [CGImage] = []

        for (i, frame) in frames.enumerated() {
            var cropped = frame

            // Strip sticky header (except first frame)
            if i > 0, opts.stickyHeaderHeight > 0 {
                cropped = cropTop(of: cropped, pixels: opts.stickyHeaderHeight) ?? cropped
            }
            // Strip sticky footer (except last frame)
            if i < frames.count - 1, opts.stickyFooterHeight > 0 {
                cropped = cropBottom(of: cropped, pixels: opts.stickyFooterHeight) ?? cropped
            }

            // Detect and remove overlap with previous frame
            if i > 0, let prev = croppedFrames.last {
                let overlap = detectOverlap(bottom: prev, top: cropped, searchHeight: opts.overlapSearchHeight)
                if overlap > opts.minOverlap {
                    cropped = cropTop(of: cropped, pixels: overlap) ?? cropped
                } else if opts.fallbackStrip > 0 {
                    cropped = cropTop(of: cropped, pixels: opts.fallbackStrip) ?? cropped
                }
            }

            croppedFrames.append(cropped)
        }

        return concatenateVertically(croppedFrames)
    }

    // MARK: - Overlap Detection

    public static func detectStickyHeader(frame1: CGImage, frame2: CGImage) -> Int {
        let w = min(frame1.width, frame2.width)
        let maxSearch = min(frame1.height, frame2.height) / 2
        guard w > 0, maxSearch > 0 else { return 0 }
        
        let sampleX = w / 4
        let sampleW = w / 2
        let samplesPerRow = max(1, sampleW / 8)
        
        guard let p1 = extractPixelRow(from: frame1, y: 0, height: maxSearch, x: sampleX, width: sampleW, samplesPerRow: samplesPerRow),
              let p2 = extractPixelRow(from: frame2, y: 0, height: maxSearch, x: sampleX, width: sampleW, samplesPerRow: samplesPerRow) else {
            return 0
        }
        
        var stickyHeight = 0
        let bytesPerRow = samplesPerRow * 4
        for y in 0..<maxSearch {
            let start = y * bytesPerRow
            let diff = pixelDifference(p1, aStart: start, p2, bStart: start, byteCount: bytesPerRow)
            if diff < 15 {
                stickyHeight = y + 1
            } else {
                break
            }
        }
        return stickyHeight
    }
    
    public static func detectStickyFooter(frame1: CGImage, frame2: CGImage) -> Int {
        let w = min(frame1.width, frame2.width)
        let h1 = frame1.height
        let h2 = frame2.height
        let maxSearch = min(h1, h2) / 2
        guard w > 0, maxSearch > 0 else { return 0 }
        
        let sampleX = w / 4
        let sampleW = w / 2
        let samplesPerRow = max(1, sampleW / 8)
        
        guard let p1 = extractPixelRow(from: frame1, y: h1 - maxSearch, height: maxSearch, x: sampleX, width: sampleW, samplesPerRow: samplesPerRow),
              let p2 = extractPixelRow(from: frame2, y: h2 - maxSearch, height: maxSearch, x: sampleX, width: sampleW, samplesPerRow: samplesPerRow) else {
            return 0
        }
        
        var stickyHeight = 0
        let bytesPerRow = samplesPerRow * 4
        for y in stride(from: maxSearch - 1, through: 0, by: -1) {
            let start = y * bytesPerRow
            let diff = pixelDifference(p1, aStart: start, p2, bStart: start, byteCount: bytesPerRow)
            if diff < 15 {
                stickyHeight += 1
            } else {
                break
            }
        }
        return stickyHeight
    }

    /// Find how many pixels from the top of `top` image match the bottom of `bottom` image.
    public static func detectOverlap(bottom: CGImage, top: CGImage, searchHeight: Int) -> Int {
        let w = min(bottom.width, top.width)
        guard w > 0, bottom.height > 0, top.height > 0 else { return 0 }

        let height = min(searchHeight, min(bottom.height, top.height))
        guard height > 0 else { return 0 }

        // Sample a central horizontal strip to reduce computation
        let sampleX = w / 4
        let sampleW = w / 2
        let samplesPerRow = max(1, sampleW / 8) // Sample every 8 pixels horizontally

        guard let bottomPixels = extractPixelRow(from: bottom,
                                                 y: bottom.height - height,
                                                 height: height,
                                                 x: sampleX, width: sampleW,
                                                 samplesPerRow: samplesPerRow),
              let topPixels = extractPixelRow(from: top,
                                              y: 0,
                                              height: height,
                                              x: sampleX, width: sampleW,
                                              samplesPerRow: samplesPerRow) else {
            return 0
        }

        // Try each possible overlap from max to min
        for overlap in stride(from: height, through: 4, by: -1) {
            let bottomStart = (height - overlap) * samplesPerRow * 4
            let topStart = 0
            let byteCount = overlap * samplesPerRow * 4

            let diff = pixelDifference(bottomPixels, aStart: bottomStart, topPixels, bStart: topStart, byteCount: byteCount)
            if diff < 15 { // threshold: allow slight color difference due to compression
                return overlap
            }
        }
        return 0
    }

    private static func pixelDifference(_ a: [UInt8], aStart: Int, _ b: [UInt8], bStart: Int, byteCount: Int) -> Double {
        guard byteCount > 0 else { return 255.0 }
        var total: Int = 0
        let end = aStart + byteCount
        var i = aStart
        var j = bStart
        var pixelsCompared = 0
        
        while i < end {
            total += abs(Int(a[i]) - Int(b[j]))      // R
            total += abs(Int(a[i+1]) - Int(b[j+1]))  // G
            total += abs(Int(a[i+2]) - Int(b[j+2]))  // B
            
            i += 4
            j += 4
            pixelsCompared += 1
            
            // Early exit check every 100 pixels
            if pixelsCompared % 100 == 0 {
                let currentAvg = Double(total) / Double(pixelsCompared * 3)
                if currentAvg > 30.0 { 
                    return 255.0 // Definitely not a match, exit early
                }
            }
        }
        return Double(total) / Double(pixelsCompared * 3)
    }

    static func extractPixelRow(from image: CGImage, y: Int, height: Int, x: Int, width: Int, samplesPerRow: Int) -> [UInt8]? {
        let totalPixels = samplesPerRow * height
        let dataSize = totalPixels * 4
        var buffer = [UInt8](repeating: 0, count: dataSize)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: &buffer,
                                      width: samplesPerRow,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: samplesPerRow * 4,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }

        // Draw the strip into context
        let srcRect = CGRect(x: x, y: y, width: width, height: height)
        let dstRect = CGRect(x: 0, y: 0, width: samplesPerRow, height: height)
        context.draw(image.cropping(to: srcRect) ?? image, in: dstRect)

        return buffer
    }

    // MARK: - Crop Helpers

    private static func cropTop(of image: CGImage, pixels: Int) -> CGImage? {
        let newHeight = image.height - pixels
        guard newHeight > 0 else { return nil }
        return image.cropping(to: CGRect(x: 0, y: pixels, width: image.width, height: newHeight))
    }

    private static func cropBottom(of image: CGImage, pixels: Int) -> CGImage? {
        let newHeight = image.height - pixels
        guard newHeight > 0 else { return nil }
        return image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: newHeight))
    }

    // MARK: - Vertical Concatenation

    private static func concatenateVertically(_ images: [CGImage]) -> CGImage? {
        guard !images.isEmpty else { return nil }
        let width = images.map(\.width).max() ?? 0
        let totalHeight = images.map(\.height).reduce(0, +)
        guard width > 0, totalHeight > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: totalHeight,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
            return nil
        }

        // Draw images top-to-bottom (CG origin is bottom-left, so we track y from bottom)
        var currentY = totalHeight
        for image in images {
            currentY -= image.height
            let rect = CGRect(x: 0, y: currentY, width: image.width, height: image.height)
            context.draw(image, in: rect)
        }

        return context.makeImage()
    }
}
