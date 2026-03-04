import SwiftUI

/// DiagnosticsView declaration.
struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: DiagnosticsViewModel

    /// Initializes the instance.
    init(viewModel: DiagnosticsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Actions") {
                    VStack(spacing: BrandTheme.Spacing.item) {
                        Button {
                            Task {
                                await viewModel.refresh()
                            }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.appSecondary)

                        Button {
                            Task {
                                await viewModel.exportJSON()
                            }
                        } label: {
                            Label("Export JSON", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.appPrimary)

                        Button(role: .destructive) {
                            Task {
                                await viewModel.clearLog()
                            }
                        } label: {
                            Label("Clear Log", systemImage: "trash")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.appDanger)
                    }
                    .padding(.vertical, 4)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                if let statusMessage = viewModel.statusMessage {
                    Section {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let fileURL = viewModel.persistentErrorLogFileURL {
                    Section("Persistent Error Log") {
                        Text(fileURL.path)
                            .font(.caption2)
                            .textSelection(.enabled)

                        Text("Documents/JamfDashboardDiagnostics/jamf-dashboard-errors.ndjson")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if viewModel.hasPersistentErrorLogEntries {
                            ShareLink(item: fileURL) {
                                Label("Share Persistent Error Log", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.appSecondary)
                        } else {
                            Text("No persistent error entries recorded yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let fileURL = viewModel.exportedFileURL {
                    Section("Last Export") {
                        Text(fileURL.lastPathComponent)
                            .font(.subheadline)

                        ShareLink(item: fileURL) {
                            Label("Share Exported JSON", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.appSecondary)
                    }
                }

                Section("Diagnostic Entries") {
                    if viewModel.entries.isEmpty {
                        Text("No diagnostic events recorded.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.entries) { entry in
                            DiagnosticEntryRow(entry: entry)
                        }
                    }
                }
            }
            .appInsetGroupedListStyle()
            .navigationTitle("Diagnostics")
            .appInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .appTopBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                }

                ToolbarItem(placement: .appTopBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.refresh()
            }
            .alert(
                "Diagnostics Error",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { isPresented in
                        if isPresented == false {
                            viewModel.errorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "Unknown error")
            }
        }
    }
}

/// DiagnosticEntryRow declaration.
private struct DiagnosticEntryRow: View {
    let entry: DiagnosticEvent

    private var severityColor: Color {
        switch entry.severity {
        case .info:
            return BrandColors.bluePrimary
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.severity.rawValue.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(severityColor)

                Spacer()

                Text(entry.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(entry.message)
                .font(.subheadline)

            Text("\(entry.source) • \(entry.category)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if entry.metadata.isEmpty == false {
                ForEach(entry.metadata.keys.sorted(), id: \.self) { key in
                    if let value = entry.metadata[key] {
                        Text("\(key): \(value)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

//endofline
