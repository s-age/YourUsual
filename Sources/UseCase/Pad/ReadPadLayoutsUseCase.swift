import Foundation

final class ReadPadLayoutsUseCase: AsyncUseCase, Sendable {
    private let padService: any PadServiceProtocol
    private let entryService: any SavedEntryServiceProtocol

    init(padService: any PadServiceProtocol, entryService: any SavedEntryServiceProtocol) {
        self.padService   = padService
        self.entryService = entryService
    }

    func execute(_ request: ReadPadLayoutsRequest) async throws -> PadLayoutsResponse {
        // Sequential await — every read hits the single RegistryDatabase actor, so
        // `async let` would be fake parallelism (knowledge: shared-modelactor-no-async-let).
        let allLayouts = try await padService.listAll()
        let allEntries = try await entryService.listAll()

        // Reuse the existing entity→response mapping (UseCase/Entry/EntryMapping.swift);
        // do not re-derive kind/icon/execution here.
        let entryByID: [UUID: SavedEntryResponse] = Dictionary(
            uniqueKeysWithValues: allEntries.map { ($0.id, SavedEntryResponse(from: $0)) }
        )

        // One bulk read of every layout's cells, folding what was an N+1 per-layout
        // fan-out into a single actor hop (knowledge: shared-modelactor-no-async-let).
        let allCells = try await padService.listAllCells()

        // Fetch the icons directory once and resolve each cell's filename into an
        // absolute URL. `try?` — a directory failure is rare and only costs the icon
        // (degrade, don't crash); cells still render with their SF Symbol fallback.
        let iconsDir = try? await padService.iconsDirectory()

        return PadLayoutsResponse(
            layouts: allLayouts.map(PadLayoutResponse.init(from:)),
            cells: allCells.map { cell in
                PadCellResponse(from: cell,
                                entry: cell.entryID.flatMap { entryByID[$0] },
                                iconsDirectory: iconsDir)
            }
        )
    }
}
