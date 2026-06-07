import Foundation

/// Probes a source image's pixel dimensions for the crop editor's layout. A thin
/// pass-through to `PadServiceProtocol.probeIconSize` (single Domain Service delegation).
final class ProbeIconImageUseCase: AsyncUseCase, Sendable {
    private let padService: any PadServiceProtocol

    init(padService: any PadServiceProtocol) {
        self.padService = padService
    }

    func execute(_ request: ProbeIconImageRequest) async throws -> IconImageSizeResponse {
        let size = try await padService.probeIconSize(source: URL(filePath: request.sourcePath))
        return IconImageSizeResponse(width: size.width, height: size.height)
    }
}
