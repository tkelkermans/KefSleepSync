import AppKit
import Foundation

struct IconSpec {
    let filename: String
    let pixelSize: Int
}

let specs: [IconSpec] = [
    .init(filename: "icon_16x16.png", pixelSize: 16),
    .init(filename: "icon_16x16@2x.png", pixelSize: 32),
    .init(filename: "icon_32x32.png", pixelSize: 32),
    .init(filename: "icon_32x32@2x.png", pixelSize: 64),
    .init(filename: "icon_128x128.png", pixelSize: 128),
    .init(filename: "icon_128x128@2x.png", pixelSize: 256),
    .init(filename: "icon_256x256.png", pixelSize: 256),
    .init(filename: "icon_256x256@2x.png", pixelSize: 512),
    .init(filename: "icon_512x512.png", pixelSize: 512),
    .init(filename: "icon_512x512@2x.png", pixelSize: 1024),
]

guard CommandLine.arguments.count == 2 else {
    fputs("usage: swift generate_app_icon.swift <AppIcon.appiconset>\n", stderr)
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for spec in specs {
    let bitmap = try drawIcon(pixelSize: spec.pixelSize)
    let destination = outputDirectory.appendingPathComponent(spec.filename)
    try write(bitmap: bitmap, to: destination)
}

private func drawIcon(pixelSize: Int) throws -> NSBitmapImageRep {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "KefSleepSync.IconGenerator", code: 1)
    }

    bitmap.size = NSSize(width: pixelSize, height: pixelSize)

    guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "KefSleepSync.IconGenerator", code: 2)
    }

    let size = NSSize(width: pixelSize, height: pixelSize)
    let rect = NSRect(origin: .zero, size: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    graphicsContext.imageInterpolation = .high

    defer {
        NSGraphicsContext.restoreGraphicsState()
    }

    let cornerRadius = size.width * 0.224
    let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    path.addClip()

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.97, green: 0.72, blue: 0.40, alpha: 1),
        NSColor(calibratedRed: 0.92, green: 0.52, blue: 0.20, alpha: 1),
        NSColor(calibratedRed: 0.55, green: 0.24, blue: 0.10, alpha: 1),
    ])!
    gradient.draw(in: rect, angle: -55)

    let shadowRect = rect.insetBy(dx: size.width * 0.03, dy: size.height * 0.03)
    let shadowPath = NSBezierPath(roundedRect: shadowRect, xRadius: cornerRadius * 0.92, yRadius: cornerRadius * 0.92)
    NSColor(calibratedWhite: 1, alpha: 0.10).setStroke()
    shadowPath.lineWidth = max(1, size.width * 0.018)
    shadowPath.stroke()

    let context = graphicsContext.cgContext
    drawBackgroundWave(context: context, size: size)
    drawSpeakerSymbol(size: size)

    return bitmap
}

private func drawBackgroundWave(context: CGContext, size: NSSize) {
    context.saveGState()
    defer { context.restoreGState() }

    let lineWidth = size.width * 0.065
    context.setLineWidth(lineWidth)
    context.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.16).cgColor)
    context.setLineCap(.round)

    let firstArc = CGRect(
        x: size.width * 0.48,
        y: size.height * 0.22,
        width: size.width * 0.52,
        height: size.height * 0.56
    )
    context.strokeEllipse(in: firstArc)

    let secondArc = CGRect(
        x: size.width * 0.58,
        y: size.height * 0.08,
        width: size.width * 0.58,
        height: size.height * 0.84
    )
    context.strokeEllipse(in: secondArc)
}

private func drawSpeakerSymbol(size: NSSize) {
    let symbolSize = size.width * 0.58
    let configuration = NSImage.SymbolConfiguration(
        pointSize: symbolSize,
        weight: .bold,
        scale: .large
    )

    guard let symbol = NSImage(
        systemSymbolName: "hifispeaker.fill",
        accessibilityDescription: nil
    )?.withSymbolConfiguration(configuration) else {
        return
    }

    let symbolRect = NSRect(
        x: size.width * 0.20,
        y: size.height * 0.20,
        width: size.width * 0.60,
        height: size.height * 0.60
    )

    let tint = NSColor(calibratedWhite: 0.09, alpha: 0.96)
    symbol.isTemplate = true
    tint.set()
    symbol.draw(
        in: symbolRect,
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: nil
    )
}

private func write(bitmap: NSBitmapImageRep, to url: URL) throws {
    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "KefSleepSync.IconGenerator", code: 4)
    }

    try pngData.write(to: url)
}
