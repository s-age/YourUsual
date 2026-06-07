import Foundation

final class FileSystemRepository: FileSystemRepositoryProtocol, Sendable {
    private let probe: any DirectoryProbeProtocol

    init(probe: any DirectoryProbeProtocol) {
        self.probe = probe
    }

    func homeDirectory() -> URL {
        probe.homeDirectory
    }

    func isDirectory(_ url: URL) -> Bool {
        probe.isDirectory(url)
    }
}
