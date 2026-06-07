import XCTest
@testable import YourUsual

// MARK: - Mocks

final class MockTerminalPreferenceStore: TerminalPreferenceStoreProtocol, @unchecked Sendable {
    var loadResult: TerminalPreferenceDTO?
    /// When set, `load()` throws this — simulates a JSON-level corrupt blob (decode
    /// failure), distinct from `loadResult == nil` (absent).
    var loadError: Error?
    var savedDTO: TerminalPreferenceDTO?

    func load() throws -> TerminalPreferenceDTO? {
        if let loadError { throw loadError }
        return loadResult
    }

    func save(_ dto: TerminalPreferenceDTO) throws {
        savedDTO = dto
    }
}

private struct CorruptBlobError: Error {}

final class MockInstalledAppStore: InstalledAppStoreProtocol, @unchecked Sendable {
    func isInstalled(bundleIdentifier: String) -> Bool { false }
    func resolveApp(at url: URL) -> AppInfoDTO? { nil }
}

// MARK: - Tests

final class TerminalSettingsRepositoryTests: XCTestCase {
    private var sut: TerminalSettingsRepository!
    private var store: MockTerminalPreferenceStore!
    private var logger: MockDiagnosticsLogger!

    override func setUp() {
        super.setUp()
        store = MockTerminalPreferenceStore()
        logger = MockDiagnosticsLogger()
        sut = TerminalSettingsRepository(
            preferenceStore: store,
            installedApps: MockInstalledAppStore(),
            logger: logger
        )
    }

    override func tearDown() {
        sut = nil
        store = nil
        logger = nil
        super.tearDown()
    }

    // MARK: - loadPreference — happy paths

    func testLoadPreference_knownKind_mapsToKnownSelection() {
        store.loadResult = TerminalPreferenceDTO(
            kind: "known", app: "terminal", bundleIdentifier: nil, name: nil,
            launchMode: TerminalLaunchMode.default.rawValue
        )
        guard case .known = sut.loadPreference().selection else {
            return XCTFail("Expected .known selection for kind 'known'")
        }
    }

    func testLoadPreference_otherKind_mapsToOtherSelection() {
        store.loadResult = TerminalPreferenceDTO(
            kind: "other", app: nil, bundleIdentifier: "com.example.term", name: "Example",
            launchMode: TerminalLaunchMode.default.rawValue
        )
        guard case .other(let id, let name) = sut.loadPreference().selection else {
            return XCTFail("Expected .other selection for kind 'other'")
        }
        XCTAssertEqual([id, name], ["com.example.term", "Example"])
    }

    func testLoadPreference_validDTO_doesNotLog() {
        store.loadResult = TerminalPreferenceDTO(
            kind: "known", app: "terminal", bundleIdentifier: nil, name: nil,
            launchMode: TerminalLaunchMode.default.rawValue
        )
        _ = sut.loadPreference()
        XCTAssertEqual(logger.warnings.count, 0)
    }

    // MARK: - loadPreference — absent store value

    func testLoadPreference_noStoredValue_returnsDefault() {
        store.loadResult = nil
        XCTAssertEqual(sut.loadPreference(), .default)
    }

    func testLoadPreference_noStoredValue_doesNotLog() {
        // Absence is a fresh install, not corruption — no warning. (Corruption now
        // throws from the store and is logged by the Repository, below.)
        store.loadResult = nil
        _ = sut.loadPreference()
        XCTAssertEqual(logger.warnings.count, 0)
    }

    // MARK: - loadPreference — schema evolution (missing launchMode is not corruption)

    func testLoadPreference_missingLaunchMode_preservesSelection() {
        // An old blob saved before launchMode existed decodes with launchMode == nil;
        // the selection must survive (mapper coerces only the mode to .default).
        store.loadResult = TerminalPreferenceDTO(
            kind: "known", app: "terminal", bundleIdentifier: nil, name: nil, launchMode: nil
        )
        XCTAssertEqual(sut.loadPreference().selection, .known(.terminal))
    }

    func testLoadPreference_missingLaunchMode_doesNotLog() {
        store.loadResult = TerminalPreferenceDTO(
            kind: "known", app: "terminal", bundleIdentifier: nil, name: nil, launchMode: nil
        )
        _ = sut.loadPreference()
        XCTAssertEqual(logger.warnings.count, 0)
    }

    // MARK: - loadPreference — unknown launchMode VALUE (present but unparseable → observable)

    func testLoadPreference_unknownLaunchModeValue_preservesSelection() {
        // The value is garbage but the selection is intact — keep the selection, default
        // only the mode (do not discard the whole preference).
        store.loadResult = TerminalPreferenceDTO(
            kind: "known", app: "terminal", bundleIdentifier: nil, name: nil, launchMode: "bogusMode"
        )
        XCTAssertEqual(sut.loadPreference().selection, .known(.terminal))
    }

    func testLoadPreference_unknownLaunchModeValue_defaultsTheMode() {
        store.loadResult = TerminalPreferenceDTO(
            kind: "known", app: "terminal", bundleIdentifier: nil, name: nil, launchMode: "bogusMode"
        )
        XCTAssertEqual(sut.loadPreference().launchMode, .default)
    }

    func testLoadPreference_unknownLaunchModeValue_logsWarning() {
        // Unlike a *missing* mode (silent schema evolution), a present-but-unparseable
        // value is unexpected and must be observable — not silently swallowed.
        store.loadResult = TerminalPreferenceDTO(
            kind: "known", app: "terminal", bundleIdentifier: nil, name: nil, launchMode: "bogusMode"
        )
        _ = sut.loadPreference()
        XCTAssertEqual(logger.warnings.count, 1)
    }

    func testLoadPreference_unknownLaunchModeValue_logNamesTheBadValue() {
        store.loadResult = TerminalPreferenceDTO(
            kind: "known", app: "terminal", bundleIdentifier: nil, name: nil, launchMode: "bogusMode"
        )
        _ = sut.loadPreference()
        XCTAssertTrue(logger.warnings.first?.contains("bogusMode") ?? false)
    }

    // MARK: - loadPreference — JSON-level corruption (store throws)

    func testLoadPreference_corruptBlob_returnsDefault() {
        store.loadError = CorruptBlobError()
        XCTAssertEqual(sut.loadPreference(), .default)
    }

    func testLoadPreference_corruptBlob_logsWarning() {
        store.loadError = CorruptBlobError()
        _ = sut.loadPreference()
        XCTAssertEqual(logger.warnings.count, 1)
    }

    // MARK: - loadPreference — semantic corruption recovery (observable)

    func testLoadPreference_unknownKind_returnsDefault() {
        store.loadResult = TerminalPreferenceDTO(
            kind: "garbage", app: nil, bundleIdentifier: nil, name: nil,
            launchMode: TerminalLaunchMode.default.rawValue
        )
        XCTAssertEqual(sut.loadPreference(), .default)
    }

    func testLoadPreference_unknownKind_logsWarning() {
        store.loadResult = TerminalPreferenceDTO(
            kind: "garbage", app: nil, bundleIdentifier: nil, name: nil,
            launchMode: TerminalLaunchMode.default.rawValue
        )
        _ = sut.loadPreference()
        XCTAssertEqual(logger.warnings.count, 1)
    }

    func testLoadPreference_knownKindMissingApp_logsWarning() {
        store.loadResult = TerminalPreferenceDTO(
            kind: "known", app: nil, bundleIdentifier: nil, name: nil,
            launchMode: TerminalLaunchMode.default.rawValue
        )
        _ = sut.loadPreference()
        XCTAssertEqual(logger.warnings.count, 1)
    }

    func testLoadPreference_otherKindMissingName_logsWarning() {
        store.loadResult = TerminalPreferenceDTO(
            kind: "other", app: nil, bundleIdentifier: "com.example.term", name: nil,
            launchMode: TerminalLaunchMode.default.rawValue
        )
        _ = sut.loadPreference()
        XCTAssertEqual(logger.warnings.count, 1)
    }

    // MARK: - recovery log names the specific cause (not just `kind`)

    func testLoadPreference_unknownKind_logsTheOffendingKind() {
        store.loadResult = TerminalPreferenceDTO(
            kind: "garbage", app: nil, bundleIdentifier: nil, name: nil,
            launchMode: TerminalLaunchMode.default.rawValue
        )
        _ = sut.loadPreference()
        XCTAssertTrue(logger.warnings.first?.contains("garbage") ?? false)
    }

    func testLoadPreference_knownKindMissingApp_logBlamesTheAppField() {
        // The kind itself is valid ("known"); the real cause is the missing app —
        // the message must say so, not finger the kind (regression this fix prevents).
        store.loadResult = TerminalPreferenceDTO(
            kind: "known", app: nil, bundleIdentifier: nil, name: nil,
            launchMode: TerminalLaunchMode.default.rawValue
        )
        _ = sut.loadPreference()
        XCTAssertTrue(logger.warnings.first?.contains("app") ?? false)
    }

    func testLoadPreference_otherKindMissingName_logBlamesTheNameField() {
        // bundleIdentifier is present, so "name" in the message can only mean the
        // name field is the cause — not an artifact of both fields being listed.
        store.loadResult = TerminalPreferenceDTO(
            kind: "other", app: nil, bundleIdentifier: "com.example.term", name: nil,
            launchMode: TerminalLaunchMode.default.rawValue
        )
        _ = sut.loadPreference()
        XCTAssertTrue(logger.warnings.first?.contains("name") ?? false)
    }

    func testLoadPreference_otherKindMissingBundleIdentifier_logBlamesThatField() {
        store.loadResult = TerminalPreferenceDTO(
            kind: "other", app: nil, bundleIdentifier: nil, name: "Example",
            launchMode: TerminalLaunchMode.default.rawValue
        )
        _ = sut.loadPreference()
        XCTAssertTrue(logger.warnings.first?.contains("bundleIdentifier") ?? false)
    }

    // MARK: - savePreference round-trip discriminator

    func testSavePreference_knownSelection_persistsKnownKind() throws {
        try sut.savePreference(TerminalPreference(selection: .known(.terminal), launchMode: .default))
        XCTAssertEqual(store.savedDTO?.kind, "known")
    }

    func testSavePreference_otherSelection_persistsOtherKind() throws {
        try sut.savePreference(
            TerminalPreference(
                selection: .other(bundleIdentifier: "com.example.term", name: "Example"),
                launchMode: .default
            )
        )
        XCTAssertEqual(store.savedDTO?.kind, "other")
    }

    // MARK: - normalizeStoredPreference — one-shot startup hygiene

    func testNormalize_corruptBlob_returnsTrue() throws {
        store.loadResult = TerminalPreferenceDTO(
            kind: "garbage", app: nil, bundleIdentifier: nil, name: nil,
            launchMode: TerminalLaunchMode.default.rawValue
        )
        XCTAssertTrue(try sut.normalizeStoredPreference())
    }

    func testNormalize_corruptBlob_overwritesStoreWithDefault() throws {
        store.loadResult = TerminalPreferenceDTO(
            kind: "garbage", app: nil, bundleIdentifier: nil, name: nil,
            launchMode: TerminalLaunchMode.default.rawValue
        )
        _ = try sut.normalizeStoredPreference()
        // The corrupt blob is replaced with the encoded default, not left in place.
        XCTAssertEqual(store.savedDTO?.kind, TerminalPreferenceMapperFixture.defaultKind)
    }

    func testNormalize_corruptBlob_logsWarning() throws {
        store.loadResult = TerminalPreferenceDTO(
            kind: "garbage", app: nil, bundleIdentifier: nil, name: nil,
            launchMode: TerminalLaunchMode.default.rawValue
        )
        _ = try sut.normalizeStoredPreference()
        XCTAssertEqual(logger.warnings.count, 1)
    }

    func testNormalize_validBlob_returnsFalse() throws {
        store.loadResult = TerminalPreferenceDTO(
            kind: "known", app: "terminal", bundleIdentifier: nil, name: nil,
            launchMode: TerminalLaunchMode.default.rawValue
        )
        XCTAssertFalse(try sut.normalizeStoredPreference())
    }

    func testNormalize_validBlob_doesNotWrite() throws {
        store.loadResult = TerminalPreferenceDTO(
            kind: "known", app: "terminal", bundleIdentifier: nil, name: nil,
            launchMode: TerminalLaunchMode.default.rawValue
        )
        _ = try sut.normalizeStoredPreference()
        XCTAssertNil(store.savedDTO)
    }

    func testNormalize_absentBlob_returnsFalse() throws {
        store.loadResult = nil
        XCTAssertFalse(try sut.normalizeStoredPreference())
    }

    func testNormalize_absentBlob_doesNotWrite() throws {
        store.loadResult = nil
        _ = try sut.normalizeStoredPreference()
        XCTAssertNil(store.savedDTO)
    }

    // A present-but-unparseable launchMode is not "corrupt" (the selection is valid and
    // kept), but left in the store it makes loadPreference() re-warn on every read. The
    // startup normalize rewrites it once, preserving the selection — not a reset.

    func testNormalize_coercedLaunchMode_returnsTrue() throws {
        store.loadResult = TerminalPreferenceDTO(
            kind: "known", app: "terminal", bundleIdentifier: nil, name: nil,
            launchMode: "no-such-mode"
        )
        XCTAssertTrue(try sut.normalizeStoredPreference())
    }

    func testNormalize_coercedLaunchMode_keepsSelection() throws {
        store.loadResult = TerminalPreferenceDTO(
            kind: "known", app: "terminal", bundleIdentifier: nil, name: nil,
            launchMode: "no-such-mode"
        )
        _ = try sut.normalizeStoredPreference()
        // Selection is preserved (still "known"/"terminal"); only the mode was defaulted.
        XCTAssertEqual(store.savedDTO?.kind, "known")
        XCTAssertEqual(store.savedDTO?.app, "terminal")
        XCTAssertEqual(store.savedDTO?.launchMode, TerminalLaunchMode.default.rawValue)
    }

    func testNormalize_coercedLaunchMode_logsWarning() throws {
        store.loadResult = TerminalPreferenceDTO(
            kind: "known", app: "terminal", bundleIdentifier: nil, name: nil,
            launchMode: "no-such-mode"
        )
        _ = try sut.normalizeStoredPreference()
        XCTAssertEqual(logger.warnings.count, 1)
    }

    // JSON-level corruption (store.load() throws) is now resettable too — the gap a
    // missing launchMode key (pre-launchMode blob) used to fall into.

    func testNormalize_jsonCorruptBlob_returnsTrue() throws {
        store.loadError = CorruptBlobError()
        XCTAssertTrue(try sut.normalizeStoredPreference())
    }

    func testNormalize_jsonCorruptBlob_overwritesStoreWithDefault() throws {
        store.loadError = CorruptBlobError()
        _ = try sut.normalizeStoredPreference()
        XCTAssertEqual(store.savedDTO?.kind, TerminalPreferenceMapperFixture.defaultKind)
    }

    func testNormalize_jsonCorruptBlob_logsWarning() throws {
        store.loadError = CorruptBlobError()
        _ = try sut.normalizeStoredPreference()
        XCTAssertEqual(logger.warnings.count, 1)
    }
}

/// The persisted `kind` the default preference encodes to — kept next to the tests so
/// the reset assertion does not hard-code the discriminator string.
private enum TerminalPreferenceMapperFixture {
    static let defaultKind = TerminalPreferenceMapper.toDTO(.default).kind
}
