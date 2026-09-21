// Turns a square piece of icon artwork into the app icon set.
//
//   swift Scripts/make-icon.swift <artwork.png>
//
// The artwork is a dark tile drawn edge to edge on an opaque black square. A macOS icon is not:
// it is a continuous-corner rounded square 824 points wide, centred on a 1024 canvas, with
// transparency around it and a drop shadow. Used as-is the artwork is oversized next to every
// other icon in the Dock, its black corners show as a square, and macOS 26 puts an icon that
// does not fill its shape inside a grey tile.
//
// So the tile is redrawn in Apple's shape: filled with the artwork's own body colour, then the
// middle of the artwork (the pill and everything around it) laid on top. The artwork's corners
// are rounder than Apple's and black behind, which is why only the middle is taken; the body is
// one flat colour, so the edge of that region cannot be seen.
import AppKit
import SwiftUI

let arguments = CommandLine.arguments
guard arguments.count == 2,
      let artwork = NSImage(contentsOfFile: arguments[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    FileHandle.standardError.write("usage: swift Scripts/make-icon.swift <artwork.png>\n".data(using: .utf8)!)
    exit(1)
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconSet = root.appendingPathComponent("MinNotch/Resources/Assets.xcassets/AppIcon.appiconset")
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func context(_ size: Int) -> CGContext {
    CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
}

// The body colour, read from the artwork well inside its edge and clear of the pill.
func bodyColour() -> CGColor {
    let probe = context(1)
    probe.interpolationQuality = .none
    let side = CGFloat(artwork.width)
    probe.draw(artwork, in: CGRect(x: -side * 0.5, y: -side * 0.2, width: side, height: side))
    let pixel = probe.data!.assumingMemoryBound(to: UInt8.self)
    return CGColor(
        srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
        blue: CGFloat(pixel[2]) / 255, alpha: 1
    )
}

// Apple's grid: an 824 tile on a 1024 canvas, corner radius 185.4, continuous corners.
let canvas: CGFloat = 1024
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = RoundedRectangle(cornerRadius: 185.4, style: .continuous).path(in: tile).cgPath

let master = context(Int(canvas))
master.interpolationQuality = .high

master.saveGState()
master.setShadow(offset: CGSize(width: 0, height: -10), blur: 20, color: CGColor(gray: 0, alpha: 0.3))
master.addPath(shape)
master.setFillColor(bodyColour())
master.fillPath()
master.restoreGState()

master.saveGState()
master.addPath(shape)
master.clip()
// Only the middle of the artwork, inset a tenth from each edge, so none of its black corners
// comes with it. The artwork is scaled so its whole square maps onto the tile, which keeps the
// pill the same proportion of the icon as it was drawn.
let middle = RoundedRectangle(cornerRadius: tile.width * 0.15, style: .continuous)
    .path(in: tile.insetBy(dx: tile.width * 0.1, dy: tile.width * 0.1)).cgPath
master.addPath(middle)
master.clip()
master.draw(artwork, in: tile)
master.restoreGState()

let icon = master.makeImage()!

func write(_ image: CGImage, _ name: String) {
    let url = iconSet.appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

var entries: [String] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        let resized = context(pixels)
        resized.interpolationQuality = .high
        resized.draw(icon, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        write(resized.makeImage()!, name)
        entries.append(
            #"    { "filename" : "\#(name)", "idiom" : "mac", "scale" : "\#(scale)x", "size" : "\#(points)x\#(points)" }"#
        )
    }
}

let contents = """
{
  "images" : [
\(entries.joined(separator: ",\n"))
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}

"""
try! contents.write(to: iconSet.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("wrote \(entries.count) sizes to \(iconSet.path)")
