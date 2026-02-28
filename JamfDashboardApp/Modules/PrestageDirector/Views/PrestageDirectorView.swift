import SwiftUI

/// PrestageDirectorView declaration.
struct PrestageDirectorView: View {
    @StateObject private var viewModel: PrestageDirectorViewModel

    /// Initializes the instance.
    init(viewModel: PrestageDirectorViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    private var selectedPrestageBinding: Binding<String?> {
        Binding(
            get: { viewModel.selectedPrestageID },
            set: { newValue in
                viewModel.selectedPrestageID = newValue
                Task {
                    await viewModel.loadDevicesForSelectedPrestage()
                }
            }
        )
    }

    var body: some View {
        List {
            Section("Pre-Stage Enrollment Profiles") {
                if viewModel.isLoadingPrestages {
                    ProgressView("Loading pre-stages...")
                }

                if viewModel.prestages.isEmpty {
                    Text("No pre-stages loaded yet.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Current Pre-Stage", selection: selectedPrestageBinding) {
                        ForEach(viewModel.prestages) { prestage in
                            Text(prestage.name).tag(prestage.id as String?)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(viewModel.isApplyingChanges)
                }

                Button {
                    Task {
                        await viewModel.refreshPrestages()
                    }
                } label: {
                    Label("Refresh Pre-Stages", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.appSecondary)
                .disabled(viewModel.isLoadingPrestages || viewModel.isApplyingChanges)
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if let statusMessage = viewModel.statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let progress = viewModel.operationProgress {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(progress.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)

                        ProgressView(value: progress.fractionCompleted, total: 1.0)
                            .tint(BrandColors.bluePrimary)

                        Text(progress.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Assigned Devices") {
                if viewModel.isLoadingScopedDevices || viewModel.isSearchingAcrossPrestages {
                    if viewModel.isGlobalSearchActive {
                        ProgressView("Searching all pre-stage profiles...")
                    } else {
                        ProgressView("Loading assigned devices...")
                    }
                } else if viewModel.isGlobalSearchActive && viewModel.filteredScopedDevices.isEmpty {
                    Text("No devices match that serial number across any pre-stage profile.")
                        .foregroundStyle(.secondary)
                } else if viewModel.scopedDevices.isEmpty {
                    Text("No devices assigned to this pre-stage.")
                        .foregroundStyle(.secondary)
                } else if viewModel.filteredScopedDevices.isEmpty {
                    Text("No devices match that serial number.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.filteredScopedDevices) { device in
                        Button {
                            viewModel.toggleSelection(for: device)
                        } label: {
                            PrestageDeviceRow(
                                device: device,
                                isSelected: viewModel.selectedDeviceKeys.contains(device.selectionKey)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isApplyingChanges || viewModel.isGlobalSearchActive)
                    }
                }
            }
        }
        .appInsetGroupedListStyle()
        .searchable(text: $viewModel.deviceSerialSearchText, prompt: "Find serial number")
        .task {
            await viewModel.loadInitialState()
            viewModel.handleDeviceSearchTextChanged()
        }
        .onChange(of: viewModel.deviceSerialSearchText) { _, _ in
            viewModel.handleDeviceSearchTextChanged()
        }
        .safeAreaInset(edge: .bottom) {
            actionBar
        }
        .sheet(isPresented: $viewModel.isMoveDestinationPresented) {
            PrestageMoveDestinationView(
                prestages: viewModel.moveDestinationPrestages,
                isApplyingChanges: viewModel.isApplyingChanges,
                onConfirm: { selectedPrestage in
                    Task {
                        await viewModel.moveSelection(to: selectedPrestage)
                    }
                }
            )
        }
    }

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(viewModel.selectedCount) selected")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button(viewModel.allDevicesSelected ? "Clear" : "Select All") {
                    viewModel.toggleSelectAll()
                }
                .buttonStyle(.appSecondary)
                .disabled(
                    viewModel.filteredScopedDevices.isEmpty ||
                        viewModel.isLoadingScopedDevices ||
                        viewModel.isSearchingAcrossPrestages ||
                        viewModel.isGlobalSearchActive ||
                        viewModel.isApplyingChanges
                )

                Button("Remove") {
                    Task {
                        await viewModel.confirmRemoval()
                    }
                }
                .buttonStyle(.appDanger)
                .disabled(viewModel.canRemoveSelection == false)

                Button("Move") {
                    viewModel.presentMoveDestinationPicker()
                }
                .buttonStyle(.appPrimary)
                .disabled(viewModel.canMoveSelection == false)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .appBottomBarSurface()
    }
}

/// PrestageDeviceRow declaration.
private struct PrestageDeviceRow: View {
    let device: PrestageAssignedDevice
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? BrandColors.greenPrimary : .secondary)
                .font(BrandSearchResultTypography.title3())
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(device.deviceName)
                    .font(BrandSearchResultTypography.headline())
                    .foregroundStyle(.primary)

                if let serial = device.normalizedSerialNumber {
                    Text("Serial: \(serial)")
                        .font(BrandSearchResultTypography.subheadline())
                } else {
                    Text("Serial unavailable")
                        .font(BrandSearchResultTypography.subheadline())
                        .foregroundStyle(.red)
                }

                if let model = device.model {
                    Text("Model: \(model)")
                        .font(BrandSearchResultTypography.caption())
                        .foregroundStyle(.secondary)
                }

                if let udid = device.udid {
                    Text("UDID: \(udid)")
                        .font(BrandSearchResultTypography.caption2())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// PrestageMoveDestinationView declaration.
private struct PrestageMoveDestinationView: View {
    @Environment(\.dismiss) private var dismiss

    let prestages: [PrestageSummary]
    let isApplyingChanges: Bool
    let onConfirm: (PrestageSummary) -> Void

    @State private var searchText = ""
    @State private var selectedPrestageID: String?

    private var filteredPrestages: [PrestageSummary] {
        guard searchText.isEmpty == false else {
            return prestages
        }

        let loweredSearch = searchText.localizedLowercase
        return prestages.filter { $0.name.localizedLowercase.contains(loweredSearch) }
    }

    private var selectedPrestage: PrestageSummary? {
        guard let selectedPrestageID else {
            return nil
        }

        return prestages.first(where: { $0.id == selectedPrestageID })
    }

    var body: some View {
        NavigationStack {
            List {
                if filteredPrestages.isEmpty {
                    Text("No destination pre-stages match your search.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredPrestages) { prestage in
                        Button {
                            selectedPrestageID = prestage.id
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedPrestageID == prestage.id ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(
                                        selectedPrestageID == prestage.id
                                            ? BrandColors.greenPrimary
                                            : .secondary
                                    )
                                    .font(.title3)

                                Text(prestage.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .appInsetGroupedListStyle()
            .disabled(isApplyingChanges)
            .searchable(text: $searchText, prompt: "Find pre-stage")
            .navigationTitle("Move To Pre-Stage")
            .appInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .appTopBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                moveConfirmationBar
            }
        }
    }

    private var moveConfirmationBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let selectedPrestage {
                Text("Destination: \(selectedPrestage.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Select a destination pre-stage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Confirm Move") {
                guard let selectedPrestage else {
                    return
                }

                onConfirm(selectedPrestage)
                dismiss()
            }
            .buttonStyle(.appPrimary)
            .disabled(selectedPrestage == nil || isApplyingChanges)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .appBottomBarSurface()
    }
}

//endofline
