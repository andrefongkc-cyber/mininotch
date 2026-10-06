#if DEBUG
import AppKit
import SwiftUI

/// Renders every Notch Style's miniature, dark and light, into one image.
///
/// Run with `MiniNotch --capture-styles out.png`. The miniatures are the ones Settings >
/// Appearance > Notch Style shows, and the Settings window cannot be captured, so this is how the
/// picker is reviewed. Languages not yet offered are drawn too, since this is also how one is
/// reviewed before it is.
@MainActor
enum DebugStyleGallery {
    static let flag = "--capture-styles"

    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag) else { return false }
        let path = arguments.indices.contains(index + 1) ? arguments[index + 1] : NSTemporaryDirectory() + "styles.png"

        let renderer = ImageRenderer(content: Gallery())
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("Could not render the gallery")
            return true
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("Rendered \(rep.pixelsWide)x\(rep.pixelsHigh) to \(path)")
        return true
    }

    private struct Gallery: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(NotchDesignLanguage.allCases) { language in
                    HStack(spacing: 16) {
                        Text(language.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 100, alignment: .leading)
                        cell(language, isDark: true)
                        cell(language, isDark: false)
                    }
                }
            }
            .padding(20)
            .background(Color(white: 0.16))
        }

        private func cell(_ language: NotchDesignLanguage, isDark: Bool) -> some View {
            NotchStylePreview(
                style: NotchStyle.make(language, isDark: isDark),
                accent: Color(nsColor: .systemBlue),
                showsHousing: true
            )
            .padding(.bottom, 14)
            .padding(.horizontal, 14)
            .background(
                LinearGradient(
                    colors: isDark
                        ? [Color(red: 0.24, green: 0.27, blue: 0.34), Color(red: 0.12, green: 0.13, blue: 0.17)]
                        : [Color(red: 0.72, green: 0.77, blue: 0.86), Color(red: 0.55, green: 0.61, blue: 0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}
#endif
