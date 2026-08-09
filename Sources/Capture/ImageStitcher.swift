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

    /// Stitch frames top-to-bottom.
    ///
    /// Approach (robust for full-screen browser captures with fixed chrome/sidebar): keep the
    /// FIRST frame in full, then for each subsequent frame measure how far the content scrolled
    /// and append ONLY that frame's newly-revealed bottom strip. Because the fixed chrome/header
    /// lives at the TOP of every frame, it is never appended — so it appears exactly once and the
    /// content flows continuously. No fragile top/sticky-header detection required.
    public static func stitch(frames: [CGImage], options: StitchOptions = StitchOptions()) -> CGImage? {
        guard !frames.isEmpty else { return nil }
        if frames.count == 1 { return frames[0] }

        // Buffers (top-left origin) for detection, built once.
        let bufs = frames.map { makeBuf($0) }
        let W = frames[0].width, H = frames[0].height

        // Fixed side columns (compare first vs last frame → biggest scroll delta → clearest signal).
        var L = 0, R = 0
        if let a = bufs.first ?? nil, let b = bufs.last ?? nil {
            (L, R) = detectFixedColumns(a, b, W: W, H: H)
        }

        // Measure the real sticky header height once (compare frame 0 vs 1 — the
        // biggest guaranteed-different pair) instead of assuming it's always
        // shorter than a fixed 20% of frame height. An app whose header/toolbar
        // is taller than that guess would otherwise leak header rows into
        // detectContentShift's sampling band, corrupting the detected shift and
        // letting the header get appended again in later "newly revealed" strips
        // instead of appearing exactly once, per the original design intent.
        let measuredHeaderHeight = frames.count > 1 ? detectStickyHeader(frame1: frames[0], frame2: frames[1]) : 0

        var pieces: [CGImage] = [frames[0]]
        for i in 1..<frames.count {
            guard let a = bufs[i-1], let b = bufs[i] else { continue }
            var shift = detectContentShift(prev: a, next: b, L: L, R: R, W: W, H: H, headerHeight: measuredHeaderHeight)
            if shift <= 2 {
                // Detection failed (e.g. visually near-identical repeating rows). Rather than drop
                // the frame and lose the bottom of the page, fall back to the commanded scroll amount.
                shift = min(options.fallbackStrip, H - 1)
            }
            guard shift > 2 else { continue }
            let s = min(shift, H - 1)
            // Keep only the bottom `s` px of this frame (the newly-revealed content).
            if let bottom = cropTop(of: frames[i], pixels: H - s) {
                pieces.append(bottom)
            }
        }

        return concatenateVertically(pieces)
    }

    // MARK: - Content-shift detection

    private struct PixBuf { let w: Int; let h: Int; let px: [UInt8] }

    /// Build a top-left-origin RGBA buffer for pixel comparison.
    private static func makeBuf(_ img: CGImage) -> PixBuf? {
        let w = img.width, h = img.height
        guard w > 0, h > 0 else { return nil }
        var raw = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &raw, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        // CGContext is bottom-left origin; flip so row 0 = top of image.
        var flipped = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            let s = (h - 1 - y) * w * 4, d = y * w * 4
            for i in 0..<(w * 4) { flipped[d + i] = raw[s + i] }
        }
        return PixBuf(w: w, h: h, px: flipped)
    }

    private static func rowDiff(_ a: PixBuf, _ ay: Int, _ b: PixBuf, _ by: Int, _ x0: Int, _ x1: Int) -> Double {
        var t = 0, n = 0, x = x0
        while x < x1 {
            let i = (ay * a.w + x) * 4, j = (by * b.w + x) * 4
            t += abs(Int(a.px[i]) - Int(b.px[j]))
            t += abs(Int(a.px[i+1]) - Int(b.px[j+1]))
            t += abs(Int(a.px[i+2]) - Int(b.px[j+2]))
            n += 3; x += 4
        }
        return n > 0 ? Double(t) / Double(n) : 0
    }

    private static func colDiff(_ a: PixBuf, _ b: PixBuf, _ x: Int, _ y0: Int, _ y1: Int) -> Double {
        var t = 0, n = 0, y = y0
        while y < y1 {
            let i = (y * a.w + x) * 4, j = (y * b.w + x) * 4
            t += abs(Int(a.px[i]) - Int(b.px[j]))
            t += abs(Int(a.px[i+1]) - Int(b.px[j+1]))
            t += abs(Int(a.px[i+2]) - Int(b.px[j+2]))
            n += 3; y += 8
        }
        return n > 0 ? Double(t) / Double(n) : 0
    }

    /// Detect fixed (non-scrolling) left/right column widths, noise-tolerant.
    private static func detectFixedColumns(_ a: PixBuf, _ b: PixBuf, W: Int, H: Int) -> (Int, Int) {
        let thr = 12.0, maxBad = 10
        var L = 0, bad = 0
        for x in 0..<(W/2) {
            if colDiff(a, b, x, H/4, 3*H/4) < thr { L = x + 1; bad = 0 }
            else { bad += 1; if bad >= maxBad { break } }
        }
        var R = 0; bad = 0; var xr = W - 1
        while xr > W/2 {
            if colDiff(a, b, xr, H/4, 3*H/4) < thr { R = W - 1 - xr + 1; bad = 0 }
            else { bad += 1; if bad >= maxBad { break } }
            xr -= 1
        }
        return (L, R)
    }

    /// Measure how many pixels the content scrolled between `prev` and `next`, sampling only the
    /// central scrolling content band/columns. Returns 0 if no confident alignment is found.
    /// `headerHeight` is the real measured sticky-header height (0 if none/undetected); the
    /// sampling band always starts below it rather than assuming a fixed fraction of the frame.
    private static func detectContentShift(prev a: PixBuf, next b: PixBuf, L: Int, R: Int, W: Int, H: Int, headerHeight: Int = 0) -> Int {
        let cw = W - L - R
        guard cw > 16 else { return 0 }
        let x0 = L + cw / 8, x1 = (W - R) - cw / 8
        let bandTop = max(H / 5, headerHeight), bandBot = H * 9 / 10
        var bestShift = 0, bestCost = Double.greatestFiniteMagnitude
        var s = 4
        let maxShift = H * 4 / 5
        while s < maxShift {
            var t = 0.0, n = 0, y = bandTop
            while y < bandBot {
                if y + s < H { t += rowDiff(a, y + s, b, y, x0, x1); n += 1 }
                y += 4
            }
            if n > 20 {
                let avg = t / Double(n)
                if avg < bestCost { bestCost = avg; bestShift = s }
            }
            s += 2
        }
        return bestCost < 12 ? bestShift : 0
    }

    // MARK: - Sticky Side Columns

    /// Detect the width (in pixels) of a fixed, non-scrolling column on one side of the frame
    /// (e.g. a sticky left sidebar). Returns 0 when no real sidebar is present.
    public static func detectStickyColumnWidth(frame1: CGImage, frame2: CGImage, fromLeft: Bool) -> Int {
        let w = min(frame1.width, frame2.width)
        let h = min(frame1.height, frame2.height)
        guard w > 8, h > 8 else { return 0 }

        let maxColScan = w / 2
        let rowCount = 40
        let yStart = h / 10
        let span = max(1, h - 2 * (h / 10))

        func sample(_ img: CGImage) -> [UInt8]? {
            let dataSize = w * rowCount * 4
            var buffer = [UInt8](repeating: 0, count: dataSize)
            let cs = CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(data: &buffer, width: w, height: rowCount,
                                      bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: cs,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            let srcRect = CGRect(x: 0, y: yStart, width: w, height: span)
            ctx.draw(img.cropping(to: srcRect) ?? img, in: CGRect(x: 0, y: 0, width: w, height: rowCount))
            return buffer
        }

        guard let b1 = sample(frame1), let b2 = sample(frame2) else { return 0 }

        func columnDiff(_ col: Int) -> Double {
            var total = 0
            for row in 0..<rowCount {
                let idx = (row * w + col) * 4
                total += abs(Int(b1[idx]) - Int(b2[idx]))
                total += abs(Int(b1[idx + 1]) - Int(b2[idx + 1]))
                total += abs(Int(b1[idx + 2]) - Int(b2[idx + 2]))
            }
            return Double(total) / Double(rowCount * 3)
        }

        var width = 0
        if fromLeft {
            for col in 0..<maxColScan {
                if columnDiff(col) < 12 { width = col + 1 } else { break }
            }
        } else {
            var c = w - 1
            while c >= w - maxColScan && c >= 0 {
                if columnDiff(c) < 12 { width += 1; c -= 1 } else { break }
            }
        }

        // Ignore thin margins / antialiasing noise.
        guard width >= 24 else { return 0 }

        // Variance guard: a real sidebar has visual structure. A uniform background
        // margin would also read as "sticky" (same color every frame) but must not be
        // treated as one, otherwise we'd blank a legitimate colored margin.
        let colStart = fromLeft ? 0 : (w - width)
        let colEnd = fromLeft ? width : w
        var sum = 0, sumSq = 0, n = 0
        for row in stride(from: 0, to: rowCount, by: 2) {
            for col in stride(from: colStart, to: colEnd, by: 4) {
                let g = Int(b1[(row * w + col) * 4 + 1]) // green as luminance proxy
                sum += g; sumSq += g * g; n += 1
            }
        }
        guard n > 0 else { return 0 }
        let mean = Double(sum) / Double(n)
        let variance = Double(sumSq) / Double(n) - mean * mean
        guard variance > 50 else { return 0 }

        return width
    }

    /// Paint the sticky side band(s) below the first frame with the sidebar's own
    /// background colour, removing the duplicated copies produced by vertical stitching.
    private static func compositeStickyColumns(stitched: CGImage,
                                               firstFrame: CGImage,
                                               leftWidth: Int,
                                               rightWidth: Int,
                                               keepTopHeight: Int) -> CGImage? {
        let width = stitched.width
        let height = stitched.height
        guard width > 0, height > 0 else { return nil }

        let blankHeight = max(0, height - keepTopHeight)
        guard blankHeight > 0 else { return stitched }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
            return nil
        }

        ctx.draw(stitched, in: CGRect(x: 0, y: 0, width: width, height: height))

        // CG origin is bottom-left: the first frame sits at the top (highest y),
        // so the region to blank is y in [0, height - keepTopHeight].
        if leftWidth > 0 {
            let (r, g, b) = averageColor(of: firstFrame,
                                         rect: CGRect(x: 0, y: 0,
                                                      width: min(leftWidth, firstFrame.width),
                                                      height: min(firstFrame.height, 40)))
            ctx.setFillColor(red: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0, blue: CGFloat(b) / 255.0, alpha: 1.0)
            ctx.fill(CGRect(x: 0, y: 0, width: leftWidth, height: blankHeight))
        }
        if rightWidth > 0 {
            let (r, g, b) = averageColor(of: firstFrame,
                                         rect: CGRect(x: max(0, firstFrame.width - rightWidth), y: 0,
                                                      width: min(rightWidth, firstFrame.width),
                                                      height: min(firstFrame.height, 40)))
            ctx.setFillColor(red: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0, blue: CGFloat(b) / 255.0, alpha: 1.0)
            ctx.fill(CGRect(x: width - rightWidth, y: 0, width: rightWidth, height: blankHeight))
        }

        return ctx.makeImage() ?? stitched
    }

    private static func averageColor(of image: CGImage, rect: CGRect) -> (UInt8, UInt8, UInt8) {
        var buf = [UInt8](repeating: 255, count: 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard rect.width >= 1, rect.height >= 1,
              let ctx = CGContext(data: &buf, width: 1, height: 1,
                                  bitsPerComponent: 8, bytesPerRow: 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let crop = image.cropping(to: rect) else {
            return (255, 255, 255)
        }
        ctx.interpolationQuality = .medium
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (buf[0], buf[1], buf[2])
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
    /// `contentXStart`/`contentXEnd` restrict sampling to the scrolling content columns
    /// (pass -1 to use the default central strip).
    public static func detectOverlap(bottom: CGImage, top: CGImage, searchHeight: Int,
                                     contentXStart: Int = -1, contentXEnd: Int = -1) -> Int {
        let w = min(bottom.width, top.width)
        guard w > 0, bottom.height > 0, top.height > 0 else { return 0 }

        let height = min(searchHeight, min(bottom.height, top.height))
        guard height > 0 else { return 0 }

        // Sample the scrolling content columns. When a valid content range is provided, use it
        // (excluding fixed side panels); otherwise fall back to a central horizontal strip.
        let hasRange = contentXStart >= 0 && contentXEnd > contentXStart && contentXEnd <= w
        let sampleX = hasRange ? contentXStart : w / 4
        let sampleW = hasRange ? max(8, contentXEnd - contentXStart) : w / 2
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
