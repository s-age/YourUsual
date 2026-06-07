import XCTest
@testable import YourUsual

/// Guards against a silent DI regression: every Request that overrides
/// `validate()` must reach the Domain through a `Validation*UseCaseDecorator`.
/// Validation lives only in the decorator (`arch-usecase.md`), and the wrapping
/// is hand-wired in `UseCaseContainer`. If a validating use case is wired without
/// its decorator, `validate()` is silently skipped and invalid input flows to the
/// Domain — with no compile-time guarantee against it.
///
/// These tests drive the **real** `UseCaseContainer` (built from the real DI
/// graph) and feed each validating use case an empty input. A wrapped use case
/// throws `ValidationError` before delegating; an unwrapped one would skip
/// validation and fail here. `validate()` runs before the decoratee, so no
/// Domain/DB work is triggered — the invalid input never reaches the store.
final class ValidationWiringTests: XCTestCase {
    private var useCases: UseCaseContainer!

    override func setUp() {
        super.setUp()
        useCases = UseCaseContainer(
            domain: DomainContainer(repo: RepositoryContainer(infra: InfrastructureContainer()))
        )
    }

    override func tearDown() {
        useCases = nil
        super.tearDown()
    }

    // MARK: - Helper

    private func assertEmptyField(
        _ body: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await body()
            XCTFail("Expected ValidationError.emptyField — is the use case wrapped in a validation decorator?", file: file, line: line)
        } catch {
            guard case ValidationError.emptyField = error else {
                return XCTFail("Expected ValidationError.emptyField, got \(error)", file: file, line: line)
            }
        }
    }

    // MARK: - RegisterCategoryRequest

    func test_registerCategory_emptyName_throwsValidationError() async {
        await assertEmptyField {
            _ = try await useCases.registerCategory.execute(RegisterCategoryRequest(name: ""))
        }
    }

    // MARK: - EditCategoryRequest

    func test_editCategory_emptyName_throwsValidationError() async {
        await assertEmptyField {
            _ = try await useCases.editCategory.execute(
                EditCategoryRequest(id: UUID(), name: "", isHiddenFromMenuBar: false)
            )
        }
    }

    // MARK: - RegisterEntryRequest

    func test_registerEntry_emptyName_throwsValidationError() async {
        await assertEmptyField {
            _ = try await useCases.registerEntry.execute(
                RegisterEntryRequest(name: "", kind: .browse(BrowsePayload(path: "/tmp/x.txt", app: .default)))
            )
        }
    }

    // MARK: - EditEntryRequest

    func test_editEntry_emptyName_throwsValidationError() async {
        await assertEmptyField {
            _ = try await useCases.editEntry.execute(
                EditEntryRequest(id: UUID(), name: "", kind: .browse(BrowsePayload(path: "/tmp/x.txt", app: .default)),
                                 isHiddenFromMenuBar: false)
            )
        }
    }

    // MARK: - RegisterPadLayoutRequest

    func test_registerPadLayout_emptyName_throwsValidationError() async {
        await assertEmptyField {
            _ = try await useCases.registerPadLayout.execute(
                RegisterPadLayoutRequest(name: "", columns: 4, rows: 3)
            )
        }
    }

    // MARK: - EditPadLayoutRequest

    func test_editPadLayout_emptyName_throwsValidationError() async {
        await assertEmptyField {
            _ = try await useCases.editPadLayout.execute(
                EditPadLayoutRequest(id: UUID(), name: "", columns: 4, rows: 3)
            )
        }
    }

    // MARK: - SavePadCellRequest
    //
    // Confirms `savePadCell` is wrapped in `ValidationAsyncUseCaseDecorator`: an invalid
    // backgroundColor must be rejected by `validate()` *before* any Domain/DB work. A wired
    // decorator throws `invalidFormat`; an unwrapped use case would skip validation and reach
    // the store. (Unlike the other cases, the relevant invariant here is the hex format, not
    // emptiness — so this asserts `invalidFormat` directly.)
    func test_savePadCell_invalidBackgroundColor_throwsValidationError() async {
        let request = SavePadCellRequest(
            layoutID: UUID(), column: 0, row: 0, columnSpan: 1, rowSpan: 1,
            entryID: nil,
            backgroundColor: "not-a-hex-color", customIconName: nil, customLabel: nil,
            sliderOrientation: .horizontal,
            customIconImageName: nil, newIconSourcePath: nil, newIconCrop: nil,
            previousIconImageName: nil
        )
        do {
            _ = try await useCases.savePadCell.execute(request)
            XCTFail("Expected ValidationError.invalidFormat — is savePadCell wrapped in a validation decorator?")
        } catch {
            guard case ValidationError.invalidFormat = error else {
                return XCTFail("Expected ValidationError.invalidFormat, got \(error)")
            }
        }
    }
}
