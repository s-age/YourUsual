import XCTest
import SwiftData
@testable import YourUsual

/// Proves the full UseCase-owned transaction stack end-to-end against a real
/// `RegistryDatabase`: `RegistryDatabaseGateway.perform` opens one SwiftData
/// transaction on the actor, the Domain `Transaction` token stages writes
/// (entity→DTO conversion in the Repository adapter, synchronous staging on the
/// actor), and the transaction commits once. A throwing body rolls back.
final class RegistryDatabaseGatewayTests: XCTestCase {
    private var db: RegistryDatabase!
    private var sut: RegistryDatabaseGateway!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: EntryModel.self, CommandRunModel.self, CategoryModel.self,
            BrowseEntryModel.self, CommandEntryModel.self, AppleScriptEntryModel.self,
            configurations: config
        )
        db = RegistryDatabase(modelContainer: container)
        sut = RegistryDatabaseGateway(runner: db)
    }

    override func tearDown() {
        sut = nil
        db = nil
        super.tearDown()
    }

    private func makeRecord(id: UUID = UUID(), entryID: UUID = UUID()) -> RunRecord {
        RunRecord(
            id: id,
            entryID: entryID,
            entryName: "Entry",
            executedAt: Date(),
            outcome: .command(CommandRunOutcome(
                commandLine: "echo hi",
                result: CommandResult(exitCode: 0, stdout: "hi", stderr: "")
            ))
        )
    }

    // MARK: - Commit on success

    func testPerform_registerRun_commitsAndPersists() async throws {
        let record = makeRecord()
        try await sut.transaction { tx in try tx.registerRun(record) }
        let runs = try await db.fetch(forEntry: record.entryID)
        XCTAssertEqual(runs.map(\.id), [record.id])
    }

    func testPerform_returnsBodyValue() async throws {
        let value = try await sut.transaction { _ in 42 }
        XCTAssertEqual(value, 42)
    }

    func testPerform_deleteRun_removesPersistedRow() async throws {
        let record = makeRecord()
        try await sut.transaction { tx in try tx.registerRun(record) }
        try await sut.transaction { tx in try tx.deleteRun(id: record.id) }
        let runs = try await db.fetch(forEntry: record.entryID)
        XCTAssertEqual(runs.count, 0)
    }

    func testPerform_deleteAllRunsForEntry_removesOnlyThatEntry() async throws {
        let entryA = UUID()
        let entryB = UUID()
        let runA = makeRecord(entryID: entryA)
        let runB = makeRecord(entryID: entryB)
        try await sut.transaction { tx in
            try tx.registerRun(runA)
            try tx.registerRun(runB)
        }
        try await sut.transaction { tx in try tx.deleteAllRuns(forEntry: entryA) }
        let remaining = try await db.fetchAllRuns()
        XCTAssertEqual(remaining.map(\.entryID), [entryB])
    }

    func testPerform_deleteAllRuns_removesEverything() async throws {
        let first = makeRecord()
        let second = makeRecord()
        try await sut.transaction { tx in
            try tx.registerRun(first)
            try tx.registerRun(second)
        }
        try await sut.transaction { tx in try tx.deleteAllRuns() }
        let remaining = try await db.fetchAllRuns()
        XCTAssertEqual(remaining.count, 0)
    }

    func testPerform_multipleStagesInOneTransaction_allCommit() async throws {
        let keep = makeRecord()
        let drop = makeRecord(entryID: keep.entryID)
        // Two mutations in one transaction: insert two, delete one → one survives.
        try await sut.transaction { tx in
            try tx.registerRun(keep)
            try tx.registerRun(drop)
            try tx.deleteRun(id: drop.id)
        }
        let runs = try await db.fetch(forEntry: keep.entryID)
        XCTAssertEqual(runs.map(\.id), [keep.id])
    }

    // MARK: - Rollback on throw

    func testPerform_bodyThrowsAfterStaging_rollsBackInsert() async throws {
        struct Boom: Error {}
        let record = makeRecord()
        do {
            try await sut.transaction { tx in
                try tx.registerRun(record)
                throw Boom()
            }
            XCTFail("Expected the body to throw")
        } catch is Boom {
            // expected
        }
        let runs = try await db.fetch(forEntry: record.entryID)
        XCTAssertEqual(runs.count, 0, "Staged insert must roll back when the body throws")
    }

    func testPerform_bodyThrows_propagatesError() async throws {
        struct Boom: Error {}
        do {
            try await sut.transaction { _ in throw Boom() }
            XCTFail("Expected the body to throw")
        } catch is Boom {
            // expected
        }
    }
}
