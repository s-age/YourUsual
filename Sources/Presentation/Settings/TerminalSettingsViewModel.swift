import Foundation
import Observation

/// Drives the global "Terminal App" settings pane: which terminal runs commands
/// and how. Every change persists immediately and reflects the resulting state
/// (the mode may be clamped to one the chosen app supports).
@Observable
@MainActor
final class TerminalSettingsViewModel {
    private(set) var settings: TerminalSettingsResponse?

    /// User-facing message for the most recent failed read/write/import, surfaced
    /// as a one-shot alert. Failures set this instead of nil-ing `settings`, so a
    /// failed preference write no longer blanks the pane into a permanent spinner.
    var actionError: String?

    private let readSettings: ReadTerminalSettingsUseCaseProtocol
    private let setPreference: SetTerminalPreferenceUseCaseProtocol
    private let resolveApp: ResolveTerminalAppUseCaseProtocol

    init(
        readSettings: ReadTerminalSettingsUseCaseProtocol,
        setPreference: SetTerminalPreferenceUseCaseProtocol,
        resolveApp: ResolveTerminalAppUseCaseProtocol
    ) {
        self.readSettings = readSettings
        self.setPreference = setPreference
        self.resolveApp = resolveApp
    }

    func load() {
        do {
            // Keep the last-known-good settings on failure rather than nil-ing the
            // pane. On first load `settings` is already nil (shows the spinner).
            settings = try readSettings.execute(ReadTerminalSettingsRequest())
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// Selected app's bundle id — bound to the terminal Picker.
    var selectedAppID: String {
        get { settings?.selected.id ?? "" }
        set {
            guard let current = settings,
                  let option = current.available.first(where: { $0.id == newValue }) else { return }
            apply(option: option, mode: current.launchMode)
        }
    }

    /// Selected launch mode — bound to the mode radio group.
    var selectedMode: TerminalLaunchModeResponse {
        get { settings?.launchMode ?? .newWindow }
        set {
            guard let current = settings else { return }
            apply(option: current.selected, mode: newValue)
        }
    }

    /// Handles the `.fileImporter` result: resolve the browsed app and select it.
    /// A cancelled importer (no URL) stays silent; a genuine resolve failure for a
    /// picked file surfaces as `actionError` rather than being silently dropped.
    func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        do {
            guard let option = try resolveApp.execute(ResolveTerminalAppRequest(url: url)) else {
                actionError = "“\(url.lastPathComponent)” isn’t a supported terminal application."
                return
            }
            apply(option: option, mode: .newWindow)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func apply(option: TerminalAppOptionResponse, mode: TerminalLaunchModeResponse) {
        let request = SetTerminalPreferenceRequest(
            appKind: option.kind,
            bundleIdentifier: option.id,
            name: option.name,
            launchMode: mode
        )
        do {
            settings = try setPreference.execute(request)
        } catch {
            // Leave the existing `settings` untouched so a failed write keeps the
            // pane usable instead of collapsing it into a permanent ProgressView.
            actionError = error.localizedDescription
        }
    }
}
