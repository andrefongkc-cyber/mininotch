// Lays the top of several notch captures out in one labelled image, for reviewing styles side by
// side.
//
//   contact-sheet out.png <crop height> <crop width> "Label=capture.png" ...
//
// Each capture is cropped to the given size around its top centre (in the capture's pixels),
// drawn over a mid grey with a lighter band down the right half, so a black pill, a white one and
// a transparent edge all show, and labelled on the left. Rows are stacked top to bottom.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count >= 5, let cropHeight = Int(arguments[2]), let cropWidth = Int(arguments[3]) else {
    print("usage: contact-sheet out.png <crop height> <crop width> \"Label=capture.png\" ...")
    exit(2)
}

let entries: [(String, CGImage)] = arguments.dropFirst(4).compactMap { entry in
    let parts = entry.split(separator: "=", maxSplits: 1).map(String.init)
    guard parts.count == 2,
          let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: parts[1]) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        print("skipped \(entry)")
        return nil
    }
    let x = max((image.width - cropWidth) / 2, 0)
    guard let cropped = image.cropping(to: CGRect(x: x, y: 0, width: min(cropWidth, image.width), height: min(cropHeight, image.height))) else { return nil }
    return (parts[0], cropped)
}

let labelWidth = 260
let gap = 16
let width = labelWidth + cropWidth + gap * 2
let height = entries.count * (cropHeight + gap) + gap

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
let cg = context.cgContext
cg.setFillColor(NSColor(white: 0.16, alpha: 1).cgColor)
cg.fill(CGRect(x: 0, y: 0, width: width, height: height))

for (index, (label, image)) in entries.enumerated() {
    // Rows from the top: AppKit's origin is bottom left.
    let top = height - gap - index * (cropHeight + gap)
    let frame = CGRect(x: CGFloat(labelWidth + gap), y: CGFloat(top - cropHeight), width: CGFloat(cropWidth), height: CGFloat(cropHeight))
    cg.setFillColor(NSColor(white: 0.45, alpha: 1).cgColor)
    cg.fill(frame)
    cg.setFillColor(NSColor(white: 0.86, alpha: 1).cgColor)
    cg.fill(CGRect(x: frame.midX, y: frame.minY, width: frame.width / 2, height: frame.height))
    cg.draw(image, in: CGRect(x: frame.minX, y: frame.maxY - CGFloat(image.height), width: CGFloat(image.width), height: CGFloat(image.height)))

    let text = NSAttributedString(string: label, attributes: [
        .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
        .foregroundColor: NSColor.white
    ])
    text.draw(at: CGPoint(x: CGFloat(gap), y: frame.maxY - 34))
}
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try? png.write(to: URL(fileURLWithPath: arguments[1]))
print("wrote \(arguments[1]) (\(width)x\(height))")
