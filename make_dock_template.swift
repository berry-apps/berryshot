import Cocoa
import CoreImage

let inputPath = "/Users/tan/idea/screenshot/Sources/Resources/AppIcon.png"
let outputPath = "/Users/tan/idea/screenshot/Sources/Resources/DockIconTemplate.png"

guard let inputImage = NSImage(contentsOfFile: inputPath),
      let cgImage = inputImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("Could not load AppIcon.png")
}

let ciImage = CIImage(cgImage: cgImage)

let filter = CIFilter(name: "CIColorMatrix")!
filter.setValue(ciImage, forKey: kCIInputImageKey)
// Make it a black silhouette
filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector")
filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")

guard let outputCI = filter.outputImage else { fatalError() }

let context = CIContext()
guard let outputCG = context.createCGImage(outputCI, from: outputCI.extent) else { fatalError() }

let outputImage = NSImage(cgImage: outputCG, size: NSSize(width: 512, height: 512))
outputImage.isTemplate = true

guard let tiff = outputImage.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError()
}

try! png.write(to: URL(fileURLWithPath: outputPath))
print("Created DockIconTemplate.png")
