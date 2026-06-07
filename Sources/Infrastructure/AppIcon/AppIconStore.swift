import AppKit
import Foundation

/// Resolves an installed app's icon and caches it as a PNG under Application Support,
/// returning the file URL for Presentation to render via `AsyncImage(url:)` — so no
/// `NSImage` ever crosses into the SwiftUI layer (mirroring `PadIconStore`). A substrate
/// separate from the SwiftData registry: holds no state, recomputes the directory per call.
///
/// `resolveIconFile` is synchronous, blocking I/O (icon read + PNG encode + file write); the
/// Repository offloads it with `Task.detached` so the cooperative pool is not stalled.
final class AppIconStore: AppIconStoreProtocol, Sendable {

    private let edge = 128   // output PNG edge length (px) — crisp at the list's 36pt slot

    /// `AppIcons/` lives beside the registry store, under the same Application Support
    /// subdirectory the registry uses (`com.yourusual.app`, see `RegistryStoreFactory`).
    private func directory() throws -> URL {
        let dir = URL.applicationSupportDirectory
            .appending(path: "com.yourusual.app", directoryHint: .isDirectory)
            .appending(path: "AppIcons", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func resolveIconFile(forBundleIdentifier bundleIdentifier: String) throws -> URL? {
        guard let appURL = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            // Not installed / unresolvable — the caller falls back to the folder SF Symbol.
            return nil
        }

        // Sanitize the app-supplied bundle id before using it as a filename: strip any
        // character outside the reverse-DNS alphabet so a stray `/` can't escape the
        // cache directory (path traversal). Real bundle ids are unaffected.
        let cacheURL = try directory()
            .appending(path: Self.sanitizedFileName(bundleIdentifier), directoryHint: .notDirectory)

        // Reuse the cached PNG unless the app bundle is newer than it (handles app updates).
        if let cachedAt = modificationDate(of: cacheURL),
           let appAt = modificationDate(of: appURL),
           cachedAt >= appAt {
            return cacheURL
        }

        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: edge, height: edge)   // bias rep selection toward a crisp size
        guard let tiff = icon.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        try png.write(to: cacheURL, options: .atomic)
        return cacheURL
    }

    private func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Maps a bundle id to a safe `<id>.png` filename, replacing any character outside
    /// `[A-Za-z0-9._-]` with `_` so a path separator can never escape the cache directory.
    private static func sanitizedFileName(_ bundleIdentifier: String) -> String {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-_")
        let safe = String(bundleIdentifier.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        return safe + ".png"
    }
}
