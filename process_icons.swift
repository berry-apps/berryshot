import Cocoa

let inputPath = "/Users/tan/.gemini/antigravity-cli/brain/d920b82d-a43b-474f-9180-b0bf63d42f29/new_strawberry_1781517096677.jpg"
guard let image = NSImage(contentsOfFile: inputPath),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("Failed to load image")
    exit(1)
}

let width = cgImage.width
let height = cgImage.height

let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

// 1. App Icon
guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo.rawValue) else { exit(1) }

let rect = CGRect(x: 0, y: 0, width: width, height: height)
let insetRect = rect.insetBy(dx: 120, dy: 120) 
let path = CGPath(roundedRect: insetRect, cornerWidth: 150, cornerHeight: 150, transform: nil)
context.addPath(path)
context.clip()
context.draw(cgImage, in: rect)

guard let appIconCG = context.makeImage() else { exit(1) }
let appIconRep = NSBitmapImageRep(cgImage: appIconCG)
try? appIconRep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "Sources/Resources/AppIcon.png"))

// 2. Menu Bar Icon
let cropSize = 750
let cropRect = CGRect(x: (width - cropSize)/2, y: (height - cropSize)/2, width: cropSize, height: cropSize)
guard let croppedCG = cgImage.cropping(to: cropRect) else { exit(1) }

let menuIconSize = 44
guard let menuContext = CGContext(data: nil, width: menuIconSize, height: menuIconSize, bitsPerComponent: 8, bytesPerRow: menuIconSize * 4, space: colorSpace, bitmapInfo: bitmapInfo.rawValue) else { exit(1) }
menuContext.interpolationQuality = .high
menuContext.draw(croppedCG, in: CGRect(x: 0, y: 0, width: menuIconSize, height: menuIconSize))

if let data = menuContext.data {
    let pointer = data.bindMemory(to: UInt8.self, capacity: menuIconSize * menuIconSize * 4)
    for i in 0..<(menuIconSize * menuIconSize) {
        let r = pointer[i*4]
        let g = pointer[i*4+1]
        let b = pointer[i*4+2]
        
        let lum = 0.299 * Float(r) + 0.587 * Float(g) + 0.114 * Float(b)
        let alpha = min(255.0, max(0.0, (250.0 - lum) * 3.0))
        
        pointer[i*4] = 0
        pointer[i*4+1] = 0
        pointer[i*4+2] = 0
        pointer[i*4+3] = UInt8(alpha)
    }
}

guard let menuIconCG = menuContext.makeImage() else { exit(1) }
let menuIconRep = NSBitmapImageRep(cgImage: menuIconCG)
try? menuIconRep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "Sources/Resources/MenuBarIcon.png"))

print("Done")
