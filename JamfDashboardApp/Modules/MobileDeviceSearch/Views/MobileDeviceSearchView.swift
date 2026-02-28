import SwiftUI

/// MobileDeviceSearchView declaration.
struct MobileDeviceSearchView: View {
    @StateObject private var viewModel: MobileDeviceSearchViewModel

    /// Initializes the instance.
    init(viewModel: MobileDeviceSearchViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        List {
            Section("Search") {
                HStack(spacing: 8) {
                    TextField("Serial number or username", text: $viewModel.query)
                        .appNoAutoCorrectionTextInput()
                        .onSubmit {
                            Task {
                                await viewModel.executeSearch()
                            }
                        }
#if os(iOS)
                        .submitLabel(.search)
#endif

                    ScanIntoTextFieldButton(text: $viewModel.query)
                }

                Picker("Search Profile", selection: $viewModel.selectedProfileID) {
                    Text("None").tag(nil as UUID?)
                    ForEach(viewModel.profiles) { profile in
                        Text(profile.name).tag(profile.id as UUID?)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Button("Fields") {
                        viewModel.isFieldCatalogPresented = true
                    }
                    .buttonStyle(.appSecondary)

                    Spacer()

                    Button {
                        Task {
                            await viewModel.executeSearch()
                        }
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.appPrimary)
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if viewModel.profiles.isEmpty == false {
                Section("Search Profiles") {
                    ForEach(viewModel.profiles) { profile in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(profile.name)
                                Text("\(profile.fieldKeys.count) fields")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if viewModel.selectedProfileID == profile.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(BrandColors.greenPrimary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.selectedProfileID = profile.id
                            viewModel.applySelectedProfileFields()
                        }
                    }
                    .onDelete(perform: viewModel.deleteProfiles)
                }
            }

            Section("Results") {
                if viewModel.isSearching {
                    ProgressView("Searching Jamf Pro...")
                } else if viewModel.searchResults.isEmpty {
                    Text("No results yet. Run a search to view devices.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.searchResults) { record in
                        MobileDeviceResultRow(
                            record: record,
                            fields: viewModel.resultFields
                        )
                    }
                }
            }
        }
        .appInsetGroupedListStyle()
        .task {
            await viewModel.loadProfiles()
        }
        .onChange(of: viewModel.selectedProfileID) { _, _ in
            viewModel.applySelectedProfileFields()
        }
        .sheet(isPresented: $viewModel.isFieldCatalogPresented) {
            FieldCatalogView(
                selectedFieldKeys: $viewModel.selectedFieldKeys,
                onSaveProfileRequested: {
                    viewModel.isFieldCatalogPresented = false

                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        viewModel.presentSaveProfilePrompt()
                    }
                }
            )
        }
        .alert("Save Search Profile", isPresented: $viewModel.isSaveProfilePromptPresented) {
            TextField("Profile name", text: $viewModel.pendingProfileName)

            Button("Cancel", role: .cancel) { }
            Button("Save") {
                Task {
                    await viewModel.saveProfileFromPrompt()
                }
            }
        } message: {
            Text("This profile stores the currently selected field toggles.")
        }
    }
}

/// MobileDeviceResultRow declaration.
private struct MobileDeviceResultRow: View {
    let record: MobileDeviceRecord
    let fields: [MobileDeviceField]
    private let prestageFieldKey = "prestageEnrollmentProfile"

    private var displayTitle: String {
        record.value(for: "deviceName") ?? record.deviceName
    }

    private var prestageDisplayValue: String? {
        record.value(for: prestageFieldKey)
    }

    private var visibleFields: [MobileDeviceField] {
        fields.filter { field in
            guard field.key != "deviceName", field.key != prestageFieldKey else {
                return false
            }

            guard let value = record.value(for: field.key) else {
                return false
            }

            return value.isEmpty == false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayTitle)
                .font(BrandSearchResultTypography.headline())

            if visibleFields.isEmpty && prestageDisplayValue == nil {
                Text("Serial: \(record.serialNumber)")
                    .font(BrandSearchResultTypography.subheadline())
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleFields) { field in
                    if let value = record.value(for: field.key) {
                        Text("\(field.displayName): \(value)")
                            .font(BrandSearchResultTypography.caption())
                            .foregroundStyle(.secondary)
                    }
                }

                if let prestageDisplayValue {
                    Text("Pre-Stage Enrollment: \(prestageDisplayValue)")
                        .font(BrandSearchResultTypography.caption())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

//endofline
