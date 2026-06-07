import Foundation

// MARK: - Read

struct ReadPadLayoutsRequest: UseCaseRequest {}

// MARK: - Layout mutations (ValidatableRequest = validation decorator applies)

struct RegisterPadLayoutRequest: ValidatableRequest {
    let name: String
    let columns: Int
    let rows: Int

    func validate() throws {
        try validatePadLayoutFields(name: name, columns: columns, rows: rows)
    }
}

struct EditPadLayoutRequest: ValidatableRequest {
    let id: UUID
    let name: String
    let columns: Int
    let rows: Int

    func validate() throws {
        try validatePadLayoutFields(name: name, columns: columns, rows: rows)
    }
}

/// Trimmed-length ceiling for a pad layout name. Measured on the trimmed string so it stays
/// consistent with the emptiness check (which also trims).
private let maxPadLayoutNameLength = 200

/// Shared layout-field validation for register/edit — both carry the same invariant
/// (non-blank name within the length ceiling + dimensions within the Domain grid bounds),
/// so the check lives once.
private func validatePadLayoutFields(name: String, columns: Int, rows: Int) throws {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedName.isEmpty {
        throw ValidationError.emptyField(name: "Name")
    }
    if trimmedName.count > maxPadLayoutNameLength {
        throw ValidationError.outOfRange(field: "Name", range: "≤ \(maxPadLayoutNameLength) characters")
    }
    if !PadLayout.columnRange.contains(columns) {
        throw ValidationError.outOfRange(
            field: "Columns", range: "\(PadLayout.columnRange.lowerBound)–\(PadLayout.columnRange.upperBound)")
    }
    if !PadLayout.rowRange.contains(rows) {
        throw ValidationError.outOfRange(
            field: "Rows", range: "\(PadLayout.rowRange.lowerBound)–\(PadLayout.rowRange.upperBound)")
    }
}

struct DeletePadLayoutRequest: UseCaseRequest {
    let id: UUID
}

/// Reorders pad layouts to match `orderedIDs` (renumbering each layout's `sortIndex`).
/// Bare request — no input invariant to validate; an unknown/short id list is a no-op.
struct ReorderPadLayoutsRequest: UseCaseRequest {
    let orderedIDs: [UUID]
}

// MARK: - Cell mutations (bounds validated inside UseCase using fetched layout)

/// Trimmed-length ceiling for a cell's custom label. Geometry (spans/grid bounds) is NOT
/// validated here — that invariant is enforced inside the UseCase against the fetched layout.
private let maxCustomLabelLength = 100

/// True when `hex` is a `#RRGGBB` or `#RRGGBBAA` string: a `#` followed by exactly 6 or 8 hex
/// digits (case-insensitive). The accepted set deliberately mirrors `Color(hex:)` (Presentation's
/// parser, which takes both 6- and 8-digit/alpha forms) so any value the UI can render also passes
/// validation — a narrower validator would reject legacy or alpha-bearing colors on edit-save even
/// though they display fine. Dependency-free — no NSRegularExpression.
private func isHexColor(_ hex: String) -> Bool {
    guard hex.hasPrefix("#") else { return false }
    let digits = hex.dropFirst()
    guard digits.count == 6 || digits.count == 8 else { return false }
    return digits.allSatisfy(\.isHexDigit)
}

struct SavePadCellRequest: ValidatableRequest {
    let layoutID: UUID
    let column: Int
    let row: Int
    let columnSpan: Int
    let rowSpan: Int
    let entryID: UUID?
    let backgroundColor: String?
    let customIconName: String?
    let customLabel: String?
    let sliderOrientation: SliderOrientation   // slider cells only; ignored for buttons

    // Image-icon intent. Three states:
    //  - unchanged: `newIconSourcePath == nil`, `customIconImageName` carries the existing name
    //  - new image: `newIconSourcePath != nil` (+ crop) → import, swap to the new filename
    //  - cleared:   `customIconImageName == nil` and `newIconSourcePath == nil` → drop the old file
    let customIconImageName: String?      // existing filename carried through (nil when cleared)
    let newIconSourcePath: String?        // file path from `.fileImporter`; set ⇒ import on save
    let newIconCrop: PadIconCropInput?    // square crop in source-image pixel coordinates
    let previousIconImageName: String?    // filename captured at populate time, for best-effort cleanup

    func validate() throws {
        // backgroundColor: nil/empty means "system default" — allowed. A non-empty value
        // must be a #RRGGBB or #RRGGBBAA hex color (matching the Color(hex:) parser).
        if let color = backgroundColor, !color.isEmpty, !isHexColor(color) {
            throw ValidationError.invalidFormat(
                field: "backgroundColor", reason: "must be a #RRGGBB or #RRGGBBAA hex color")
        }
        // customLabel: empty/nil is allowed (means "entry's name"); only cap the length.
        if let label = customLabel {
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > maxCustomLabelLength {
                throw ValidationError.outOfRange(
                    field: "customLabel", range: "≤ \(maxCustomLabelLength) characters")
            }
        }
    }
}

/// Square crop rectangle in the source image's pixel coordinates. Lives in Requests so
/// Presentation can construct it; the UseCase converts it to the Domain `IconCrop`.
struct PadIconCropInput: Equatable, Sendable {
    let originX: Int
    let originY: Int
    let side: Int

    var toDomain: IconCrop { IconCrop(originX: originX, originY: originY, side: side) }
}

/// Probes a source image's pixel dimensions so the crop editor can lay out its viewport.
struct ProbeIconImageRequest: UseCaseRequest {
    let sourcePath: String
}

struct DeletePadCellRequest: UseCaseRequest {
    let layoutID: UUID
    let column: Int
    let row: Int
    let iconImageName: String?   // best-effort image cleanup on cell delete
}
