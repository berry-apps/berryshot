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

let cropSize = 750
let cropRect = CGRect(x: (width - cropSize)/2, y: (height - cropSize)/2, width: cropSize, height: cropSize)
guard let croppedCG = cgImage.cropping(to: cropRect) else { exit(1) }

let outSize = 512
guard let outContext = CGContext(data: nil, width: outSize, height: outSize, bitsPerComponent: 8, bytesPerRow: outSize * 4, space: colorSpace, bitmapInfo: bitmapInfo.rawValue) else { exit(1) }
outContext.interpolationQuality = .high
outContext.draw(croppedCG, in: CGRect(x: 0, y: 0, width: outSize, height: outSize))

if let data = outContext.data {
    let pointer = data.bindMemory(to: UInt8.self, capacity: outSize * outSize * 4)
    for i in 0..<(outSize * outSize) {
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

guard let finalCG = outContext.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: finalCG)
try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "Sources/Resources/DockMenuBarIcon.png"))

print("Created DockMenuBarIcon.png")
