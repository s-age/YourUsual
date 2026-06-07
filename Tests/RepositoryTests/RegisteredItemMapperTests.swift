import XCTest
@testable import YourUsual

/// Round-trip coverage for `RegisteredItemMapper` — the single source of truth for
/// `SavedEntry` ⇄ `RegisteredItemDTO`. Asserts the menu-bar visibility flag survives
/// entity → DTO → entity, and that the decode-recovery placeholder is always visible.
final class RegisteredItemMapperTests: XCTestCase {

    private func browseEntry(isHiddenFromMenuBar: Bool) -> SavedEntry {
        SavedEntry(
            id: UUID(),
            name: "Browse",
            kind: .browse(BrowseEntry(url: URL(fileURLWithPath: "/tmp/test"), app: .default)),
            sortIndex: 0,
            isHiddenFromMenuBar: isHiddenFromMenuBar
        )
    }

    func test_roundTrip_isHiddenFromMenuBar_true_survives() throws {
        let entry = browseEntry(isHiddenFromMenuBar: true)
        let restored = try RegisteredItemMapper.toEntity(RegisteredItemMapper.toDTO(entry))
        XCTAssertTrue(restored.isHiddenFromMenuBar)
    }

    func test_roundTrip_isHiddenFromMenuBar_false_survives() throws {
        let entry = browseEntry(isHiddenFromMenuBar: false)
        let restored = try RegisteredItemMapper.toEntity(RegisteredItemMapper.toDTO(entry))
        XCTAssertFalse(restored.isHiddenFromMenuBar)
    }

    // A legacy blob predating the field decodes to `nil`, which must coalesce to visible.
    func test_toEntity_legacyNilFlag_coalescesToVisible() throws {
        var dto = RegisteredItemMapper.toDTO(browseEntry(isHiddenFromMenuBar: true))
        dto.isHiddenFromMenuBar = nil
        let restored = try RegisteredItemMapper.toEntity(dto)
        XCTAssertFalse(restored.isHiddenFromMenuBar)
    }

    // A recovered (undecodable) entry stays visible regardless of the stored flag, so the
    // user notices and re-enters it.
    func test_recoveredEntity_isAlwaysVisible() {
        var dto = RegisteredItemMapper.toDTO(browseEntry(isHiddenFromMenuBar: true))
        dto.isHiddenFromMenuBar = true
        let recovered = RegisteredItemMapper.recoveredEntity(from: dto)
        XCTAssertFalse(recovered.isHiddenFromMenuBar)
    }

    // MARK: - slider round-trip

    private func sliderEntry() -> SavedEntry {
        SavedEntry(
            id: UUID(),
            name: "Volume",
            kind: .slider(SliderEntry(
                commandLine: "osascript -e 'set volume output volume <VALUE>'",
                minValue: 0, maxValue: 100, step: 5, currentValue: 40
            )),
            sortIndex: 0
        )
    }

    func test_sliderRoundTrip_kindIsSlider() throws {
        let restored = try RegisteredItemMapper.toEntity(RegisteredItemMapper.toDTO(sliderEntry()))
        guard case .slider = restored.kind else {
            return XCTFail("expected slider kind, got \(restored.kind)")
        }
    }

    func test_sliderRoundTrip_preservesCommandLine() throws {
        let restored = try RegisteredItemMapper.toEntity(RegisteredItemMapper.toDTO(sliderEntry()))
        guard case .slider(let slider) = restored.kind else { return XCTFail("expected slider") }
        XCTAssertEqual(slider.commandLine, "osascript -e 'set volume output volume <VALUE>'")
    }

    func test_sliderRoundTrip_preservesNumericFields() throws {
        let restored = try RegisteredItemMapper.toEntity(RegisteredItemMapper.toDTO(sliderEntry()))
        guard case .slider(let slider) = restored.kind else { return XCTFail("expected slider") }
        XCTAssertEqual(slider.minValue, 0)
        XCTAssertEqual(slider.maxValue, 100)
        XCTAssertEqual(slider.step, 5)
        XCTAssertEqual(slider.currentValue, 40)
    }

    func test_toDTO_slider_setsDiscriminators() {
        let dto = RegisteredItemMapper.toDTO(sliderEntry())
        XCTAssertEqual(dto.targetKind, TargetKind.slider.rawValue)
        XCTAssertEqual(dto.handlerKind, HandlerKind.slider.rawValue)
    }

    func test_decodeKind_slider_missingNumericFields_throwsPersistenceFailed() {
        var dto = RegisteredItemMapper.toDTO(sliderEntry())
        dto.sliderStep = nil
        do {
            _ = try RegisteredItemMapper.toEntity(dto)
            XCTFail("expected persistenceFailed")
        } catch let error as OperationError {
            guard case .persistenceFailed = error else {
                return XCTFail("expected persistenceFailed, got \(error)")
            }
        } catch {
            XCTFail("expected OperationError, got \(error)")
        }
    }

    func test_decodeKind_slider_missingCommandLine_throwsPersistenceFailed() {
        var dto = RegisteredItemMapper.toDTO(sliderEntry())
        dto.commandLine = nil
        do {
            _ = try RegisteredItemMapper.toEntity(dto)
            XCTFail("expected persistenceFailed")
        } catch let error as OperationError {
            guard case .persistenceFailed = error else {
                return XCTFail("expected persistenceFailed, got \(error)")
            }
        } catch {
            XCTFail("expected OperationError, got \(error)")
        }
    }
}
