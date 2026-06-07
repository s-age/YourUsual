import Foundation
import Observation

/// Drives the "Command Output" settings pane: how many trailing lines of a background
/// command's output to retain. The entered value is committed on submit/blur; the use
/// case clamps it to the valid range and the confirmed value is reflected back into
/// the field.
@Observable
@MainActor
final class CommandOutputSettingsViewModel {
    private(set) var settings: CommandOutputSettingsResponse?
    /// Editable field value (a string, so partial edits are allowed). Committed via
    /// `commit()`, then reset to the confirmed (possibly clamped) value.
    var bufferLinesText = ""

    /// User-facing message for the most recent failed read/write, surfaced as a
    /// one-shot alert. Failures set this instead of nil-ing `settings`.
    var actionError: String?

    private let readSettings: ReadCommandOutputSettingsUseCaseProtocol
    private let setBuffer: SetCommandOutputBufferUseCaseProtocol

    init(
        readSettings: ReadCommandOutputSettingsUseCaseProtocol,
        setBuffer: SetCommandOutputBufferUseCaseProtocol
    ) {
        self.readSettings = readSettings
        self.setBuffer = setBuffer
    }

    func load() {
        do {
            let response = try readSettings.execute(ReadCommandOutputSettingsRequest())
            settings = response
            bufferLinesText = String(response.bufferLines)
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// Commits the entered value: parse, persist (the use case clamps), and reflect the
    /// confirmed result back into the field. A non-numeric entry is discarded and the
    /// last confirmed value restored, rather than persisting garbage.
    func commit() {
        guard let value = Int(bufferLinesText.trimmingCharacters(in: .whitespaces)) else {
            if let settings { bufferLinesText = String(settings.bufferLines) }
            return
        }
        // Skip the persist when the entered value already equals the confirmed value —
        // `.onDisappear`/`.onSubmit` fire even on an unchanged field, and writing it
        // would be a needless UserDefaults write.
        if value == settings?.bufferLines { return }
        do {
            let response = try setBuffer.execute(SetCommandOutputBufferRequest(bufferLines: value))
            settings = response
            bufferLinesText = String(response.bufferLines)   // reflect any clamping
        } catch {
            actionError = error.localizedDescription
        }
    }
}
