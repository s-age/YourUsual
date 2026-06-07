import SwiftUI

/// One registered entry, laid out as a card with its row actions. Actions are
/// passed as closures so the card stays free of navigation/ViewModel state.
struct EntryCard: View {
    let item: SavedEntryResponse
    /// Cached icon of the app a File/Directory entry opens with, when resolved.
    /// nil for other kinds, the default app, or an uninstalled/unresolved app —
    /// the row then falls back to the kind's SF Symbol.
    let appIconURL: URL?
    let showHistory: () -> Void
    let edit: () -> Void
    let requestDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            entryIcon
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if item.isRecovered {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .help("This item couldn’t be loaded and is shown as a placeholder. "
                                  + "Editing and saving will overwrite the original definition.")
                    }
                }
                Text(item.kind.displayLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                // History is only persisted for background commands, so the affordance
                // appears only there — other kinds would open an always-empty list.
                if item.recordsRunHistory {
                    Button("History", systemImage: "clock", action: showHistory)
                        .labelStyle(.iconOnly)
                        .help("History")
                }

                Button("Edit", systemImage: "pencil", action: edit)
                    .labelStyle(.iconOnly)
                    .help("Edit")

                Button("Delete", systemImage: "trash", role: .destructive, action: requestDelete)
                    .labelStyle(.iconOnly)
                    .help("Delete")
            }
            .buttonStyle(.borderless)
            .controlSize(.large)
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }

    /// The leading icon: the chosen app's real icon for a File/Directory entry, else
    /// the kind's SF Symbol (background commands muted to `.secondary`; others `.tint`).
    @ViewBuilder
    private var entryIcon: some View {
        if let appIconURL {
            AsyncImage(url: appIconURL) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                symbolIcon
            }
            .frame(width: 24, height: 24)
        } else {
            symbolIcon
        }
    }

    private var symbolIcon: some View {
        Image(systemName: item.kind.iconSystemName)
            .font(.system(size: 22))
            .foregroundStyle(item.kind.isBackgroundCommand
                ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
    }
}
