import SwiftUI

/// ComputerSearchView declaration.
struct ComputerSearchView: View {
    @StateObject private var viewModel: ComputerSearchViewModel

    /// Initializes the instance.
    init(viewModel: ComputerSearchViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        List {
            Section("Search") {
                HStack(spacing: 8) {
                    TextField("Computer name, serial, username, email", text: $viewModel.query)
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
                    Text("No results yet. Run a search to view computers.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.searchResults) { record in
                        ComputerResultRow(record: record)
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
            ComputerFieldCatalogView(
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

/// ComputerResultRow declaration.
private struct ComputerResultRow: View {
    let record: ComputerRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.computerName)
                .font(BrandSearchResultTypography.headline())

            Text("Serial: \(record.serialNumber)")
                .font(BrandSearchResultTypography.subheadline())

            if let model = record.model {
                Text("Model: \(model)")
                    .font(BrandSearchResultTypography.caption())
                    .foregroundStyle(.secondary)
            }

            if let osVersion = record.osVersion {
                let osBuildSuffix = record.osBuild.map { " (\($0))" } ?? ""
                Text("OS: \(osVersion)\(osBuildSuffix)")
                    .font(BrandSearchResultTypography.caption())
                    .foregroundStyle(.secondary)
            }

            if let username = record.username, username.isEmpty == false {
                Text("User: \(username)")
                    .font(BrandSearchResultTypography.caption())
                    .foregroundStyle(.secondary)
            }

            if let email = record.email, email.isEmpty == false {
                Text("Email: \(email)")
                    .font(BrandSearchResultTypography.caption())
                    .foregroundStyle(.secondary)
            }

            if let ipAddress = record.lastIpAddress, ipAddress.isEmpty == false {
                Text("Last IP: \(ipAddress)")
                    .font(BrandSearchResultTypography.caption())
                    .foregroundStyle(.secondary)
            }

            if let assetTag = record.assetTag, assetTag.isEmpty == false {
                Text("Asset Tag: \(assetTag)")
                    .font(BrandSearchResultTypography.caption())
                    .foregroundStyle(.secondary)
            }

            if let prestageDisplay = record.prestageDisplayValue, prestageDisplay.isEmpty == false {
                Text("Pre-Stage Enrollment: \(prestageDisplay)")
                    .font(BrandSearchResultTypography.caption())
                    .foregroundStyle(.secondary)
            }

            if let udid = record.udid {
                Text("UDID: \(udid)")
                    .font(BrandSearchResultTypography.caption2())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 4)
    }
}

//endofline
