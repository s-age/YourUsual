import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// Filesystem + image-processing adapter for pad-icon PNGs. A substrate separate from
/// the SwiftData `RegistryDatabase`: it crops and downscales source images with
/// ImageIO/CoreGraphics (no AppKit/`NSImage`) and stores the results as PNGs under
/// Application Support. Stateless — the directory is recomputed on each call.
///
/// All methods are synchronous and may block on disk/decoding; callers (the Repository)
/// offload heavy work with `Task.detached` so the cooperative pool is not stalled.
final class PadIconStore: PadIconStoreProtocol, Sendable {

    private let edge = 512   // output PNG edge length (px)

    /// `PadIcons/` lives beside the registry store, under the same Application Support
    /// subdirectory the store uses (`com.yourusual.app`, see `RegistryStoreFactory`).
    func directory() throws -> URL {
        let dir = URL.applicationSupportDirectory
            .appending(path: "com.yourusual.app", directoryHint: .isDirectory)
            .appending(path: "PadIcons", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func probeSize(source: URL) throws -> PixelSizeDTO {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else {
            throw OperationError.invalidItem(reason: "Unsupported or unreadable image")
        }
        return PixelSizeDTO(width: width, height: height)
    }

    func normalize(source: URL, cropX: Int, cropY: Int, side: Int) throws -> String {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
              let full = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw OperationError.invalidItem(reason: "Unreadable image")
        }
        // Clamp the requested square to the image bounds; EXIF orientation is not applied
        // (plain CGImage) — see gotchas.md if rotated photos need handling later.
        let rect = CGRect(x: cropX, y: cropY, width: side, height: side)
            .intersection(CGRect(x: 0, y: 0, width: full.width, height: full.height))
        guard !rect.isNull, !rect.isEmpty, let cropped = full.cropping(to: rect) else {
            throw OperationError.invalidItem(reason: "Crop out of bounds")
        }
        // Draw into an edge×edge context to downscale.
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: edge, height: edge, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw OperationError.persistenceFailed(reason: "CGContext alloc failed")
        }
        ctx.interpolationQuality = .high
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: edge, height: edge))
        guard let out = ctx.makeImage() else {
            throw OperationError.persistenceFailed(reason: "Render failed")
        }
        // PNG-encode and write.
        let name = UUID().uuidString + ".png"
        let url = try directory().appending(path: name, directoryHint: .notDirectory)
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw OperationError.persistenceFailed(reason: "PNG destination failed")
        }
        CGImageDestinationAddImage(dest, out, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw OperationError.persistenceFailed(reason: "PNG write failed")
        }
        return name
    }

    func delete(name: String) throws {
        let url = try directory().appending(path: name, directoryHint: .notDirectory)
        try? FileManager.default.removeItem(at: url)   // best-effort: a missing file is fine
    }
}
