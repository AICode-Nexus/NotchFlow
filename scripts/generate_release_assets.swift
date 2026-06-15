import AppKit
import Foundation

struct ReleaseAssetGenerator {
    let root: URL

    var iconSetURL: URL {
        root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset")
    }

    var docsAssetsURL: URL {
        root.appendingPathComponent("docs/assets")
    }

    func run() throws {
        try FileManager.default.createDirectory(at: iconSetURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: docsAssetsURL, withIntermediateDirectories: true)

        let icon = makeIcon(size: 1024)
        try writePNG(icon, to: docsAssetsURL.appendingPathComponent("notchflow-logo.png"))
        try writePNG(icon, to: iconSetURL.appendingPathComponent("icon_512x512@2x.png"))

        for size in [16, 32, 64, 128, 256, 512] {
            let resized = resize(icon, to: NSSize(width: size, height: size))
            let name: String
            switch size {
            case 16: name = "icon_16x16.png"
            case 32: name = "icon_16x16@2x.png"
            case 64: name = "icon_32x32@2x.png"
            case 128: name = "icon_128x128.png"
            case 256: name = "icon_128x128@2x.png"
            case 512: name = "icon_512x512.png"
            default: continue
            }
            try writePNG(resized, to: iconSetURL.appendingPathComponent(name))
        }

        try writePNG(resize(icon, to: NSSize(width: 32, height: 32)), to: iconSetURL.appendingPathComponent("icon_32x32.png"))
        try writePNG(resize(icon, to: NSSize(width: 256, height: 256)), to: iconSetURL.appendingPathComponent("icon_256x256.png"))
        try writePNG(resize(icon, to: NSSize(width: 512, height: 512)), to: iconSetURL.appendingPathComponent("icon_256x256@2x.png"))

        let hero = makeHero(size: NSSize(width: 1800, height: 1100), icon: icon)
        try writePNG(hero, to: docsAssetsURL.appendingPathComponent("notchflow-hero.png"))
    }

    private func makeIcon(size: CGFloat) -> NSImage {
        draw(size: NSSize(width: size, height: size)) { rect in
            let radius = size * 0.22
            rounded(rect, radius: radius).addClip()

            let background = NSGradient(colors: [
                NSColor(calibratedRed: 0.035, green: 0.042, blue: 0.058, alpha: 1.0),
                NSColor(calibratedRed: 0.024, green: 0.031, blue: 0.038, alpha: 1.0),
                NSColor(calibratedRed: 0.100, green: 0.073, blue: 0.045, alpha: 1.0)
            ])
            background?.draw(in: rect, angle: -38)

            NSColor(calibratedWhite: 1, alpha: 0.08).setStroke()
            let outline = rounded(rect.insetBy(dx: size * 0.035, dy: size * 0.035), radius: radius * 0.82)
            outline.lineWidth = size * 0.018
            outline.stroke()

            let notch = NSRect(x: size * 0.285, y: size * 0.700, width: size * 0.430, height: size * 0.132)
            NSColor(calibratedWhite: 0.0, alpha: 0.92).setFill()
            rounded(notch, radius: notch.height * 0.48).fill()

            NSColor(calibratedRed: 0.396, green: 0.902, blue: 0.760, alpha: 1.0).setStroke()
            let flow = NSBezierPath()
            flow.lineWidth = size * 0.078
            flow.lineCapStyle = .round
            flow.move(to: NSPoint(x: size * 0.255, y: size * 0.440))
            flow.curve(
                to: NSPoint(x: size * 0.745, y: size * 0.500),
                controlPoint1: NSPoint(x: size * 0.360, y: size * 0.610),
                controlPoint2: NSPoint(x: size * 0.620, y: size * 0.310)
            )
            flow.stroke()

            NSColor(calibratedRed: 0.962, green: 0.706, blue: 0.357, alpha: 1.0).setFill()
            let dotSize = size * 0.118
            rounded(
                NSRect(x: size * 0.616, y: size * 0.370, width: dotSize, height: dotSize),
                radius: dotSize / 2
            ).fill()

            NSColor(calibratedWhite: 1, alpha: 0.72).setStroke()
            let glint = NSBezierPath()
            glint.lineWidth = size * 0.022
            glint.lineCapStyle = .round
            glint.move(to: NSPoint(x: size * 0.332, y: size * 0.544))
            glint.curve(
                to: NSPoint(x: size * 0.484, y: size * 0.517),
                controlPoint1: NSPoint(x: size * 0.382, y: size * 0.596),
                controlPoint2: NSPoint(x: size * 0.432, y: size * 0.530)
            )
            glint.stroke()
        }
    }

    private func makeHero(size: NSSize, icon: NSImage) -> NSImage {
        draw(size: size) { rect in
            let background = NSGradient(colors: [
                NSColor(calibratedRed: 0.026, green: 0.031, blue: 0.043, alpha: 1),
                NSColor(calibratedRed: 0.040, green: 0.060, blue: 0.065, alpha: 1),
                NSColor(calibratedRed: 0.125, green: 0.090, blue: 0.050, alpha: 1)
            ])
            background?.draw(in: rect, angle: -25)

            let display = NSRect(x: 300, y: 178, width: 1240, height: 744)
            NSColor(calibratedWhite: 0.0, alpha: 0.74).setFill()
            rounded(display, radius: 38).fill()

            NSColor(calibratedWhite: 1.0, alpha: 0.10).setStroke()
            let displayBorder = rounded(display.insetBy(dx: 1, dy: 1), radius: 38)
            displayBorder.lineWidth = 2
            displayBorder.stroke()

            NSColor(calibratedRed: 0.040, green: 0.047, blue: 0.057, alpha: 1).setFill()
            rounded(display.insetBy(dx: 34, dy: 34), radius: 24).fill()

            let notch = NSRect(x: display.midX - 146, y: display.maxY - 64, width: 292, height: 68)
            NSColor.black.setFill()
            rounded(notch, radius: 32).fill()

            let panel = NSRect(x: display.midX - 350, y: display.maxY - 312, width: 700, height: 256)
            NSColor(calibratedWhite: 0.02, alpha: 0.90).setFill()
            rounded(panel, radius: 34).fill()
            NSColor(calibratedWhite: 1.0, alpha: 0.14).setStroke()
            let panelBorder = rounded(panel, radius: 34)
            panelBorder.lineWidth = 1.5
            panelBorder.stroke()

            let compact = NSRect(x: display.midX - 124, y: display.maxY - 48, width: 248, height: 42)
            NSColor(calibratedWhite: 0.0, alpha: 1).setFill()
            rounded(compact, radius: 21).fill()

            icon.draw(in: NSRect(x: panel.minX + 32, y: panel.maxY - 92, width: 50, height: 50))
            drawText("NotchFlow", in: NSRect(x: panel.minX + 98, y: panel.maxY - 80, width: 250, height: 34), size: 28, weight: .bold, color: .white)
            drawText("Now playing / Weather / Battery", in: NSRect(x: panel.minX + 100, y: panel.maxY - 112, width: 360, height: 24), size: 16, weight: .medium, color: NSColor(calibratedWhite: 1, alpha: 0.62))

            drawModule(NSRect(x: panel.minX + 34, y: panel.minY + 34, width: 190, height: 104), title: "Media", value: "Pause", accent: NSColor(calibratedRed: 0.396, green: 0.902, blue: 0.760, alpha: 1))
            drawModule(NSRect(x: panel.minX + 250, y: panel.minY + 34, width: 190, height: 104), title: "Weather", value: "23 C", accent: NSColor(calibratedRed: 0.962, green: 0.706, blue: 0.357, alpha: 1))
            drawModule(NSRect(x: panel.minX + 466, y: panel.minY + 34, width: 190, height: 104), title: "Focus", value: "42 min", accent: NSColor(calibratedRed: 0.670, green: 0.740, blue: 1.0, alpha: 1))

            NSColor(calibratedWhite: 1, alpha: 0.10).setFill()
            rounded(NSRect(x: display.minX + 108, y: display.minY + 98, width: 420, height: 26), radius: 13).fill()
            rounded(NSRect(x: display.minX + 108, y: display.minY + 144, width: 280, height: 18), radius: 9).fill()
            rounded(NSRect(x: display.maxX - 418, y: display.minY + 104, width: 290, height: 18), radius: 9).fill()
            rounded(NSRect(x: display.maxX - 418, y: display.minY + 146, width: 360, height: 26), radius: 13).fill()
        }
    }

    private func drawModule(_ rect: NSRect, title: String, value: String, accent: NSColor) {
        NSColor(calibratedWhite: 1, alpha: 0.07).setFill()
        rounded(rect, radius: 18).fill()
        accent.setFill()
        rounded(NSRect(x: rect.minX + 18, y: rect.maxY - 32, width: 46, height: 8), radius: 4).fill()
        drawText(title, in: NSRect(x: rect.minX + 18, y: rect.maxY - 58, width: rect.width - 36, height: 18), size: 14, weight: .semibold, color: NSColor(calibratedWhite: 1, alpha: 0.62))
        drawText(value, in: NSRect(x: rect.minX + 18, y: rect.minY + 16, width: rect.width - 36, height: 30), size: 23, weight: .bold, color: .white)
    }

    private func drawText(_ text: String, in rect: NSRect, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        text.draw(in: rect, withAttributes: attributes)
    }

    private func resize(_ image: NSImage, to size: NSSize) -> NSImage {
        draw(size: size) { rect in
            image.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)
        }
    }

    private func draw(size: NSSize, actions: (NSRect) -> Void) -> NSImage {
        let pixelWidth = Int(size.width.rounded())
        let pixelHeight = Int(size.height.rounded())
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return NSImage(size: size)
        }

        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        actions(NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        return image
    }

    private func rounded(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }

    private func writePNG(_ image: NSImage, to url: URL) throws {
        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let data = bitmap.representation(using: .png, properties: [:])
        else {
            throw AssetError.pngEncodingFailed(url.path)
        }

        try data.write(to: url, options: .atomic)
    }
}

enum AssetError: Error {
    case pngEncodingFailed(String)
}

let generator = ReleaseAssetGenerator(root: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
try generator.run()
print("Generated NotchFlow release assets.")
