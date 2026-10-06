// Compares two PNGs pixel for pixel, for `Scripts/style-diff.sh`.
//
//   png-diff a.png b.png [diff.png]
//
// Prints how many pixels differ, the largest difference in any channel, and the rectangle they
// fall in, and exits 0 only when the two are identical. With a third path it writes the
// differing pixels in red over a faded copy of the first image, so a change can be seen.
import AppKit

func pixels(_ path: String) -> (width: Int, height: Int, bytes: [UInt8])? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    let width = image.width, height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(
            data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    return drawn ? (width, height, bytes) : nil
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    print("usage: png-diff a.png b.png [diff.png]")
    exit(2)
}
guard let a = pixels(arguments[1]), let b = pixels(arguments[2]) else {
    print("could not read one of the images")
    exit(2)
}
guard a.width == b.width, a.height == b.height else {
    print("sizes differ: \(a.width)x\(a.height) against \(b.width)x\(b.height)")
    exit(1)
}

var differing = 0
var largest = 0
var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
var marked = a.bytes.enumerated().map { index, value in index % 4 == 3 ? value : value / 3 }
for y in 0..<a.height {
    for x in 0..<a.width {
        let i = (y * a.width + x) * 4
        var worst = 0
        for c in 0..<4 { worst = max(worst, abs(Int(a.bytes[i + c]) - Int(b.bytes[i + c]))) }
        guard worst > 0 else { continue }
        differing += 1
        largest = max(largest, worst)
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        marked[i] = 255; marked[i + 1] = 0; marked[i + 2] = 0; marked[i + 3] = 255
    }
}

if differing == 0 {
    print("identical")
    exit(0)
}
print("\(differing) pixels differ, by up to \(largest), within x \(minX)...\(maxX), y \(minY)...\(maxY)")

if arguments.count >= 4 {
    let data = Data(marked)
    if let provider = CGDataProvider(data: data as CFData),
       let image = CGImage(
           width: a.width, height: a.height, bitsPerComponent: 8, bitsPerPixel: 32,
           bytesPerRow: a.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
           provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
       ),
       let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: arguments[3]))
    }
}
exit(1)
