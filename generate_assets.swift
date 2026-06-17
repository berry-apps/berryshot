import Cocoa

// 1. Process App Icon
let inputPath = "/Users/tan/.gemini/antigravity-cli/brain/d920b82d-a43b-474f-9180-b0bf63d42f29/macos_strawberry_1781517278751.jpg"
if let image = NSImage(contentsOfFile: inputPath),
   let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
    
    let width = cgImage.width
    let height = cgImage.height
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

    if let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo.rawValue) {
        
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        let insetRect = rect.insetBy(dx: 120, dy: 120) 
        let path = CGPath(roundedRect: insetRect, cornerWidth: 160, cornerHeight: 160, transform: nil)
        context.addPath(path)
        context.clip()
        context.draw(cgImage, in: rect)

        if let appIconCG = context.makeImage() {
            let appIconRep = NSBitmapImageRep(cgImage: appIconCG)
            try? appIconRep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "Sources/Resources/AppIcon.png"))
            print("AppIcon created")
        }
    }
} else {
    print("Failed to load app icon source image")
}

// 2. Generate Menu Bar Icon
let size = CGSize(width: 36, height: 36)
let menuImage = NSImage(size: size)
menuImage.lockFocus()

if let context = NSGraphicsContext.current?.cgContext {
    context.setStrokeColor(NSColor.black.cgColor)
    context.setLineWidth(2.5)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    
    // Draw a strawberry outline
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 18, y: 3)) // bottom tip
    path.addCurve(to: CGPoint(x: 32, y: 22), control1: CGPoint(x: 28, y: 8), control2: CGPoint(x: 34, y: 16))
    path.addCurve(to: CGPoint(x: 18, y: 28), control1: CGPoint(x: 30, y: 28), control2: CGPoint(x: 24, y: 29))
    path.addCurve(to: CGPoint(x: 4, y: 22), control1: CGPoint(x: 12, y: 29), control2: CGPoint(x: 6, y: 28))
    path.addCurve(to: CGPoint(x: 18, y: 3), control1: CGPoint(x: 2, y: 16), control2: CGPoint(x: 8, y: 8))
    context.addPath(path)
    context.strokePath()
    
    // Leaves
    let leafPath = CGMutablePath()
    leafPath.move(to: CGPoint(x: 18, y: 27))
    leafPath.addLine(to: CGPoint(x: 18, y: 33)) // center stem
    
    leafPath.move(to: CGPoint(x: 18, y: 27))
    leafPath.addQuadCurve(to: CGPoint(x: 10, y: 31), control: CGPoint(x: 14, y: 30))
    
    leafPath.move(to: CGPoint(x: 18, y: 27))
    leafPath.addQuadCurve(to: CGPoint(x: 26, y: 31), control: CGPoint(x: 22, y: 30))
    
    context.addPath(leafPath)
    context.strokePath()
    
    // Camera lens in the middle
    let lensPath = CGPath(ellipseIn: CGRect(x: 13, y: 12, width: 10, height: 10), transform: nil)
    context.addPath(lensPath)
    context.strokePath()
}

menuImage.unlockFocus()

if let tiff = menuImage.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
    let png = rep.representation(using: .png, properties: [:])
    try? png?.write(to: URL(fileURLWithPath: "Sources/Resources/MenuBarIcon.png"))
    print("MenuBarIcon created")
}
