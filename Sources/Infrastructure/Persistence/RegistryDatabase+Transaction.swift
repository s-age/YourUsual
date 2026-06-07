import Foundation
import SwiftData

// The UseCase-owned transaction mechanism. `transaction` is the single commit site
// in the whole app: one actor hop that runs `body` inside one synchronous
// `modelContext.transaction`, committing once on success and rolling back if
// `body` throws. The actor itself is the `TxContextProtocol` handed to `body`,
// so the synchronous staging primitives mutate the same `modelContext` that the
// surrounding transaction commits. Lives in its own extension to keep the actor
// body within the type-length budget.
extension RegistryDatabase: TransactionRunnerProtocol, TxContextProtocol {

    func transaction<T: Sendable>(
        _ body: @Sendable (any TxContextProtocol) throws -> T
    ) async throws -> T {
        // `modelContext.transaction` is synchronous and cannot span `await`, so
        // `body` is synchronous; it stages writes via the `TxContextProtocol`
        // primitives below. The whole body runs inside one transaction → one
        // commit (or one rollback on throw). This is the only place a SwiftData
        // transaction is opened/committed.
        //
        // SwiftData does NOT auto-rollback the in-memory object graph when the
        // transaction body throws — staged inserts/deletes linger on this
        // long-lived `@ModelActor` context and would leak into the next operation.
        // So on throw we explicitly `rollback()` to discard the staged (uncommitted)
        // changes before rethrowing.
        var result: T?
        do {
            try modelContext.transaction {
                // `self` is the witness. The staging methods are `nonisolated` (so
                // the existential is `Sendable`), but we are running inside this
                // actor-isolated method, so each staging call re-enters via
                // `assumeIsolated` — sound because execution is genuinely on the actor.
                result = try body(self)
            }
        } catch {
            modelContext.rollback()
            throw error
        }
        // `transaction` only returns normally after a successful commit, so by
        // here `result` is always assigned; the throwing path exits above.
        guard let result else {
            throw OperationError.persistenceFailed(reason: "transaction body produced no value")
        }
        return result
    }

    // MARK: - TxContextProtocol — synchronous staging (no commit; the open
    // `transaction` transaction commits once on return). `nonisolated` so the actor
    // can satisfy the `Sendable` existential requirement; each method runs while
    // the actor is already isolated (invoked from inside `transaction`'s
    // `modelContext.transaction`), so `assumeIsolated` reaches `modelContext`
    // soundly. A delete must `fetch` its models to tear down the inverse
    // relationship; that read sits inside the staging op, which is fine — we are
    // inside the single transaction and the actor serializes access.

    nonisolated func stageInsertRun(_ run: RunRecordDTO) throws {
        try assumeIsolated { db in
            let id = run.entryID
            let parent = try db.modelContext.fetch(
                FetchDescriptor<EntryModel>(predicate: #Predicate { $0.id == id })
            ).first
            // `entryID` (the queryable source of truth) and `entry` (the cascade
            // edge) must be set together and stay consistent — see CommandRunModel's
            // invariant. This is the only place that writes either.
            let model = CommandRunModel(
                id: run.id,
                entryID: run.entryID,
                entryName: run.entryName,
                executedAt: run.executedAt,
                outcomeKind: run.outcomeKind,
                commandLine: run.commandLine,
                exitCode: run.exitCode.map(Int.init),
                stdout: run.stdout,
                stderr: run.stderr
            )
            model.entry = parent
            db.modelContext.insert(model)
        }
    }

    nonisolated func stageDeleteRun(id: UUID) throws {
        try assumeIsolated { db in
            let runID = id
            let models = try db.modelContext.fetch(
                FetchDescriptor<CommandRunModel>(predicate: #Predicate { $0.id == runID })
            )
            for model in models { db.modelContext.delete(model) }
        }
    }

    nonisolated func stageDeleteAllRuns(forEntry id: UUID) throws {
        try assumeIsolated { db in
            let entryID = id
            let models = try db.modelContext.fetch(
                FetchDescriptor<CommandRunModel>(predicate: #Predicate { $0.entryID == entryID })
            )
            for model in models { db.modelContext.delete(model) }
        }
    }

    nonisolated func stageDeleteAllRuns() throws {
        try assumeIsolated { db in
            let models = try db.modelContext.fetch(FetchDescriptor<CommandRunModel>())
            for model in models { db.modelContext.delete(model) }
        }
    }

    // MARK: - Entry registry staging (whole-collection reconcile)
    // Mirrors the read-modify-write in RegistryDatabase+EntryStore.replaceAll(_:),
    // but inside the open transaction (no `write{}`). Reads happen here because
    // we are already inside the actor-serialized `transaction` body.

    nonisolated func stageReplaceAllEntries(_ dto: RegistryDTO, preservingIDs: Set<UUID>) throws {
        try assumeIsolated { db in
            let existing = try db.modelContext.fetch(FetchDescriptor<EntryModel>())
            let categoriesByID = Dictionary(
                uniqueKeysWithValues: try db.modelContext.fetch(FetchDescriptor<CategoryModel>()).map { ($0.id, $0) }
            )
            let incomingIDs = Set(dto.items.map(\.id))
            var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

            for model in existing where !incomingIDs.contains(model.id) {
                db.modelContext.delete(model)
            }
            for item in dto.items {
                // Preserve an existing row for a recovery placeholder: the incoming DTO is
                // only the display shape, so applying it would overwrite the still-intact
                // original. With no existing row (e.g. a fresh import) there is nothing to
                // preserve, so fall through and insert the placeholder.
                if preservingIDs.contains(item.id), byID[item.id] != nil { continue }
                let model: EntryModel
                if let existing = byID[item.id] {
                    db.apply(item, to: existing)
                    model = existing
                } else {
                    model = db.makeModel(item)
                    byID[item.id] = model
                }
                model.category = item.categoryID.flatMap { categoriesByID[$0] }
            }
        }
    }

    // MARK: - Category staging (whole-collection reconcile)
    // Mirrors the read-modify-write in RegistryDatabase+CategoryStore.replaceAll(_:),
    // but inside the open transaction (no `write{}`).

    nonisolated func stageReplaceAllCategories(_ dtos: [CategoryDTO]) throws {
        try assumeIsolated { db in
            let existing = try db.modelContext.fetch(FetchDescriptor<CategoryModel>())
            let incomingIDs = Set(dtos.map(\.id))
            var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

            for model in existing where !incomingIDs.contains(model.id) {
                db.modelContext.delete(model)
            }
            for dto in dtos {
                if let model = byID[dto.id] {
                    Self.applyCategoryDTO(dto, to: model)
                } else {
                    let model = Self.makeCategoryModel(dto)
                    db.modelContext.insert(model)
                    byID[dto.id] = model
                }
            }
        }
    }

    // MARK: - PadLayout staging (per-record) + PadCell staging (per-layout replacement)
    // Layouts are inserted/updated/deleted individually (like RunHistory); cells for
    // a layout are always replaced as a group to stay atomic. A delete cascades to
    // the layout's cells via PadLayoutModel.cells (deleteRule: .cascade).

    nonisolated func stageInsertPadLayout(_ dto: PadLayoutDTO) throws {
        // Insert-only — no fetch — so the body never throws (unlike the other staging
        // ops which fetch). `throws` stays in the signature to satisfy the protocol.
        assumeIsolated { db in
            let model = PadLayoutModel(
                id: dto.id, name: dto.name,
                columns: dto.columns, rows: dto.rows, sortIndex: dto.sortIndex
            )
            db.modelContext.insert(model)
        }
    }

    nonisolated func stageUpdatePadLayout(_ dto: PadLayoutDTO) throws {
        try assumeIsolated { db in
            let id = dto.id
            guard let model = try db.modelContext.fetch(
                FetchDescriptor<PadLayoutModel>(predicate: #Predicate { $0.id == id })
            ).first else { throw OperationError.itemNotFound(id: id) }
            model.name      = dto.name
            model.columns   = dto.columns
            model.rows      = dto.rows
            model.sortIndex = dto.sortIndex
        }
    }

    nonisolated func stageDeletePadLayout(id: UUID) throws {
        try assumeIsolated { db in
            let layoutID = id
            let models = try db.modelContext.fetch(
                FetchDescriptor<PadLayoutModel>(predicate: #Predicate { $0.id == layoutID })
            )
            for model in models { db.modelContext.delete(model) }
            // SwiftData cascade-deletes PadCellModel rows via @Relationship(deleteRule: .cascade)
        }
    }

    nonisolated func stageReplacePadCells(layoutID: UUID, cells: [PadCellDTO]) throws {
        try assumeIsolated { db in
            let lid = layoutID
            // 1. Delete existing cells for this layout
            let existing = try db.modelContext.fetch(
                FetchDescriptor<PadCellModel>(predicate: #Predicate { $0.layoutID == lid })
            )
            for model in existing { db.modelContext.delete(model) }

            // 2. Resolve the parent layout for the relationship
            let parent = try db.modelContext.fetch(
                FetchDescriptor<PadLayoutModel>(predicate: #Predicate { $0.id == lid })
            ).first

            // 3. Insert new cells
            for dto in cells {
                let model = PadCellModel(
                    id: dto.id, layoutID: dto.layoutID,
                    column: dto.column, row: dto.row,
                    columnSpan: dto.columnSpan, rowSpan: dto.rowSpan,
                    entryID: dto.entryID,
                    backgroundColor: dto.backgroundColor,
                    customIconName: dto.customIconName,
                    customIconImageName: dto.customIconImageName,
                    customLabel: dto.customLabel,
                    orientation: dto.orientation
                )
                model.layout = parent
                db.modelContext.insert(model)
            }
        }
    }
}
