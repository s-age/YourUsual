import SwiftUI

struct RunHistoryView: View {
    @Bindable var viewModel: RunHistoryViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(viewModel.runs) { run in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Image(systemName: run.succeeded ? "checkmark.circle" : "xmark.octagon")
                            .foregroundStyle(run.succeeded ? .green : .red)
                        Text(run.executedAt, format: .dateTime)
                            .font(.caption).foregroundStyle(.secondary)
                        if let code = run.exitCode {
                            Text("exit \(code)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Delete", role: .destructive) {
                            Task { await viewModel.delete(run) }
                        }
                    }
                    if let line = run.commandLine {
                        Text(line).font(.system(.caption, design: .monospaced))
                    }
                    if !run.stdout.isEmpty {
                        Text(run.stdout).font(.system(.caption2, design: .monospaced))
                    }
                    if !run.stderr.isEmpty {
                        Text(run.stderr)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.red)
                    }
                }
            }
            if viewModel.runs.count >= RunHistoryViewModel.displayLimit {
                Text("Showing the most recent \(RunHistoryViewModel.displayLimit) runs")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(viewModel.title)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
            ToolbarItem {
                Button("Clear", systemImage: "trash") {
                    Task { await viewModel.clearAll() }
                }
                .disabled(viewModel.runs.isEmpty)
            }
        }
        .frame(minWidth: 420, minHeight: 300)
        .task { await viewModel.load() }
        // Surface a failed read/delete instead of swallowing it (a read failure
        // would otherwise look like empty history).
        .actionErrorAlert($viewModel.actionError)
    }
}
