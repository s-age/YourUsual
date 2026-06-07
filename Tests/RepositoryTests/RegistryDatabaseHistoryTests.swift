import XCTest
import SwiftData
@testable import YourUsual

/// Exercises `RegistryDatabase` directly against an in-memory SwiftData store,
/// verifying that history reads, cascade deletes, and the fetchLimit work correctly
/// when mutations go through the `perform` transaction path.
final class RegistryDatabaseHistoryTests: XCTestCase {
    private var db: RegistryDatabase!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: EntryModel.self, CommandRunModel.self, CategoryModel.self,
            BrowseEntryModel.self, CommandEntryModel.self, AppleScriptEntryModel.self,
            configurations: config
        )
        db = RegistryDatabase(modelContainer: container)
    }

    override func tearDown() {
        db = nil
        super.tearDown()
    }

    // MARK: - Fixtures

    private func makeEntryDTO(id: UUID = UUID(), name: String = "Entry") -> RegisteredItemDTO {
        RegisteredItemDTO(
            id: id, name: name, sortIndex: 0,
            targetKind: "command", path: nil, commandLine: "echo",
            workingDirectory: nil, executable: nil, arguments: nil,
            handlerKind: "background", appBundleIdentifier: nil, terminal: nil
        )
    }

    private func makeRunDTO(
        id: UUID = UUID(),
        entryID: UUID,
        entryName: String = "Entry",
        executedAt: Date = Date()
    ) -> RunRecordDTO {
        RunRecordDTO(
            id: id,
            entryID: entryID,
            entryName: entryName,
            executedAt: executedAt,
            outcomeKind: "command",
            commandLine: "echo hello",
            exitCode: 0,
            stdout: "hello",
            stderr: ""
        )
    }

    // MARK: - stageInsertRun → fetch (newest-first order)

    func testFetch_returnsNewestFirst() async throws {
        let entryID = UUID()
        let older = makeRunDTO(entryID: entryID, executedAt: Date(timeIntervalSinceReferenceDate: 1_000))
        let newer = makeRunDTO(entryID: entryID, executedAt: Date(timeIntervalSinceReferenceDate: 2_000))
        try await db.transaction { tx in
            try tx.stageInsertRun(older)
            try tx.stageInsertRun(newer)
        }
        let fetched = try await db.fetch(forEntry: entryID)
        XCTAssertEqual(fetched.first?.id, newer.id)
    }

    func testFetch_returnsAllInsertedRuns() async throws {
        let entryID = UUID()
        let run1 = makeRunDTO(entryID: entryID)
        let run2 = makeRunDTO(entryID: entryID)
        try await db.transaction { tx in
            try tx.stageInsertRun(run1)
            try tx.stageInsertRun(run2)
        }
        let fetched = try await db.fetch(forEntry: entryID)
        XCTAssertEqual(fetched.count, 2)
    }

    // MARK: - Cascade delete: removing EntryModel deletes its runs

    func testCascadeDelete_removingEntry_deletesItsRuns() async throws {
        let entryID = UUID()
        let dto = RegistryDTO(items: [makeEntryDTO(id: entryID)])
        let run = makeRunDTO(entryID: entryID)
        try await db.transaction { tx in
            try tx.stageReplaceAllEntries(dto, preservingIDs: [])
            try tx.stageInsertRun(run)
        }
        let empty = RegistryDTO(items: [])
        try await db.transaction { tx in
            try tx.stageReplaceAllEntries(empty, preservingIDs: [])
        }
        let remaining = try await db.fetchAllRuns()
        XCTAssertEqual(remaining.count, 0)
    }

    func testCascadeDelete_otherEntryRunsUnaffected() async throws {
        let entryA = UUID()
        let entryB = UUID()
        let twoEntries = RegistryDTO(items: [makeEntryDTO(id: entryA, name: "A"), makeEntryDTO(id: entryB, name: "B")])
        let runA = makeRunDTO(entryID: entryA)
        let runB = makeRunDTO(entryID: entryB)
        try await db.transaction { tx in
            try tx.stageReplaceAllEntries(twoEntries, preservingIDs: [])
            try tx.stageInsertRun(runA)
            try tx.stageInsertRun(runB)
        }
        let onlyB = RegistryDTO(items: [makeEntryDTO(id: entryB, name: "B")])
        try await db.transaction { tx in try tx.stageReplaceAllEntries(onlyB, preservingIDs: []) }
        let remaining = try await db.fetchAllRuns()
        XCTAssertEqual(remaining.count, 1)
    }

    // MARK: - Edit entry (same id) preserves run rows

    func testEditEntry_sameID_preservesRunCount() async throws {
        let entryID = UUID()
        let before = RegistryDTO(items: [makeEntryDTO(id: entryID, name: "Before")])
        let after = RegistryDTO(items: [makeEntryDTO(id: entryID, name: "After")])
        let run = makeRunDTO(entryID: entryID)
        try await db.transaction { tx in
            try tx.stageReplaceAllEntries(before, preservingIDs: [])
            try tx.stageInsertRun(run)
        }
        try await db.transaction { tx in try tx.stageReplaceAllEntries(after, preservingIDs: []) }
        let runs = try await db.fetch(forEntry: entryID)
        XCTAssertEqual(runs.count, 1)
    }

    func testEditEntry_sameID_preservesRunID() async throws {
        let entryID = UUID()
        let runID = UUID()
        let before = RegistryDTO(items: [makeEntryDTO(id: entryID, name: "Before")])
        let after = RegistryDTO(items: [makeEntryDTO(id: entryID, name: "After")])
        let run = makeRunDTO(id: runID, entryID: entryID)
        try await db.transaction { tx in
            try tx.stageReplaceAllEntries(before, preservingIDs: [])
            try tx.stageInsertRun(run)
        }
        try await db.transaction { tx in try tx.stageReplaceAllEntries(after, preservingIDs: []) }
        let runs = try await db.fetch(forEntry: entryID)
        XCTAssertEqual(runs.first?.id, runID)
    }

    // MARK: - fetchLimit (fetchAll caps at 200)

    func testFetchAll_respectsFetchLimit() async throws {
        let entryID = UUID()
        for _ in 0..<201 {
            let run = makeRunDTO(entryID: entryID)
            try await db.transaction { tx in try tx.stageInsertRun(run) }
        }
        let all = try await db.fetchAllRuns()
        XCTAssertLessThanOrEqual(all.count, 200)
    }

    func testFetchAll_exactlyAtLimit_returnsAtMost200() async throws {
        let entryID = UUID()
        for _ in 0..<200 {
            let run = makeRunDTO(entryID: entryID)
            try await db.transaction { tx in try tx.stageInsertRun(run) }
        }
        let all = try await db.fetchAllRuns()
        XCTAssertEqual(all.count, 200)
    }

    // MARK: - stageDeleteRun

    func testStageDeleteRun_removesTargetRun() async throws {
        let entryID = UUID()
        let runID = UUID()
        let run = makeRunDTO(id: runID, entryID: entryID)
        try await db.transaction { tx in try tx.stageInsertRun(run) }
        try await db.transaction { tx in try tx.stageDeleteRun(id: runID) }
        let remaining = try await db.fetch(forEntry: entryID)
        XCTAssertEqual(remaining.count, 0)
    }

    func testStageDeleteRun_leavesOtherRunsUntouched() async throws {
        let entryID = UUID()
        let keep = UUID()
        let remove = UUID()
        let runKeep = makeRunDTO(id: keep, entryID: entryID)
        let runRemove = makeRunDTO(id: remove, entryID: entryID)
        try await db.transaction { tx in
            try tx.stageInsertRun(runKeep)
            try tx.stageInsertRun(runRemove)
        }
        try await db.transaction { tx in try tx.stageDeleteRun(id: remove) }
        let remaining = try await db.fetch(forEntry: entryID)
        XCTAssertEqual(remaining.first?.id, keep)
    }

    // MARK: - stageDeleteAllRuns(forEntry:)

    func testStageDeleteAllRunsForEntry_removesOnlyThatEntrysRuns() async throws {
        let entryA = UUID()
        let entryB = UUID()
        let runA = makeRunDTO(entryID: entryA)
        let runB = makeRunDTO(entryID: entryB)
        try await db.transaction { tx in
            try tx.stageInsertRun(runA)
            try tx.stageInsertRun(runB)
        }
        try await db.transaction { tx in try tx.stageDeleteAllRuns(forEntry: entryA) }
        let remaining = try await db.fetchAllRuns()
        XCTAssertEqual(remaining.count, 1)
    }

    func testStageDeleteAllRunsForEntry_leavesOtherEntrysRunsUntouched() async throws {
        let entryA = UUID()
        let entryB = UUID()
        let runA = makeRunDTO(entryID: entryA)
        let runB = makeRunDTO(entryID: entryB)
        try await db.transaction { tx in
            try tx.stageInsertRun(runA)
            try tx.stageInsertRun(runB)
        }
        try await db.transaction { tx in try tx.stageDeleteAllRuns(forEntry: entryA) }
        let remaining = try await db.fetchAllRuns()
        XCTAssertEqual(remaining.first?.entryID, entryB)
    }

    // MARK: - stageDeleteAllRuns

    func testStageDeleteAllRuns_removesAllRuns() async throws {
        let entryID = UUID()
        let run1 = makeRunDTO(entryID: entryID)
        let run2 = makeRunDTO(entryID: entryID)
        try await db.transaction { tx in
            try tx.stageInsertRun(run1)
            try tx.stageInsertRun(run2)
        }
        try await db.transaction { tx in try tx.stageDeleteAllRuns() }
        let remaining = try await db.fetchAllRuns()
        XCTAssertEqual(remaining.count, 0)
    }
}
