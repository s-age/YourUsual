#!/usr/bin/env swift

import AppKit

let iconSizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent()
let projectDir = scriptDir.deletingLastPathComponent()
let sourceURL = projectDir
    .appendingPathComponent("Resources")
    .appendingPathComponent("AppIconSource.png")

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    FileHandle.standardError.write(Data("Error: failed to load \(sourceURL.path)\n".utf8))
    exit(1)
}

func render(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)!
    let cg = NSGraphicsContext.current!.cgContext
    cg.interpolationQuality = .high
    cg.clear(CGRect(x: 0, y: 0, width: size, height: size))

    let cornerRadius = size * 0.2237
    let clipPath = CGPath(
        roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )
    cg.addPath(clipPath)
    cg.clip()

    let imageSize = sourceImage.size
    let scale = max(size / imageSize.width, size / imageSize.height)
    let drawWidth = imageSize.width * scale
    let drawHeight = imageSize.height * scale
    let originX = (size - drawWidth) / 2
    let originY = (size - drawHeight) / 2
    let destRect = CGRect(x: originX, y: originY, width: drawWidth, height: drawHeight)

    sourceImage.draw(
        in: destRect,
        from: .zero,
        operation: .sourceOver,
        fraction: 1.0,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high.rawValue]
    )

    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])!
}

let outputDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/AppIcon.iconset"

let fm = FileManager.default
try fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

for (name, pixels) in iconSizes {
    let data = render(pixels: pixels)
    try data.write(to: URL(fileURLWithPath: "\(outputDir)/\(name).png"))
}

print("Generated iconset: \(outputDir)")
