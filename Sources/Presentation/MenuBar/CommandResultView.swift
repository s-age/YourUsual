import SwiftUI

/// Standalone window showing a background command's latest run. It observes the
/// shared `MenuItemsViewModel`, so streaming output updates live and the body
/// re-resolves whenever `resultWindowEntryID` changes (a newer run retargets the
/// same window).
///
/// This replaces both the in-menu inline panel (cramped at the menu's fixed
/// width) and the popover (its beak inserts a gap that broke the hover path to
/// the Delete button). A real, resizable window has none of those constraints.
struct CommandResultView: View {
    let viewModel: MenuItemsViewModel

    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        let entry = viewModel.resultWindowEntry
        let output = entry.flatMap { viewModel.output(for: $0.id) }
        VStack(alignment: .leading, spacing: 0) {
            header(entry: entry, output: output)
            Divider()
            ScrollView {
                outputBody(output)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 420, minHeight: 260)
    }

    @ViewBuilder
    private func header(entry: SavedEntryResponse?, output: CommandOutput?) -> some View {
        HStack(spacing: 8) {
            Button(role: .destructive) {
                if let entry { viewModel.deleteResult(entry) }
                dismissWindow(id: "result")
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .controlSize(.small)
            .disabled(entry == nil)

            Text(entry?.name ?? "No result")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            statusLabel(output)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func statusLabel(_ output: CommandOutput?) -> some View {
        if let output, case .finished(let code, let ok) = output.completion {
            HStack(spacing: 4) {
                Image(systemName: ok ? "checkmark.circle" : "xmark.octagon")
                    .foregroundStyle(ok ? .green : .red)
                Text("exit \(code)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if output != nil {
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text("Running…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Renders stdout and stderr as two adjacent `Text` views rather than merging
    /// them into a single string each render. With one merged `Text`, observing
    /// `outputs` rebuilt and re-laid-out a ~400k-char string on every streamed
    /// chunk (O(n) per chunk → O(n²) overall). Splitting the buffers means each
    /// `Text` only re-lays-out its own contents, and no concatenation happens.
    /// Both live in the same `ScrollView`, so selection still spans them.
    @ViewBuilder
    private func outputBody(_ output: CommandOutput?) -> some View {
        if let output {
            if !output.stdout.isEmpty || !output.stderr.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    if !output.stdout.isEmpty {
                        Text(output.stdout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !output.stderr.isEmpty {
                        Text(output.stderr)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                // Both buffers empty: "…" while still running, "(no output)"
                // once finished (`output.isFinished` is `exitCode != nil`).
                Text(output.isFinished ? "(no output)" : "…")
            }
        }
        // nil output (no run resolved): render nothing, matching the prior
        // merged-string path which returned "" for a nil output.
    }
}
