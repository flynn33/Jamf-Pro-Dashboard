import SwiftUI
import UniformTypeIdentifiers

/// SettingsView declaration.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var credentialsStore: JamfCredentialsStore
    let diagnosticsReporter: (any DiagnosticsReporting)?
    @ObservedObject var modulePackageManager: ModulePackageManager

    @State private var isModuleImporterPresented = false
    @State private var modulePackageStatusMessage: String?
    @State private var modulePackageErrorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .font(.headline)
                    }
                    .buttonStyle(.appSecondary)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, BrandTheme.Spacing.section)
                .padding(.top, BrandTheme.Spacing.compact)
                .padding(.bottom, 4)

                List {
                    Section("Configuration") {
                        NavigationLink {
                            ServerCredentialsView(
                                credentialsStore: credentialsStore,
                                diagnosticsReporter: diagnosticsReporter
                            )
                        } label: {
                            Label("Jamf Credentials", systemImage: "key.fill")
                        }
                    }

                    Section("Module Packages") {
                        Button {
                            isModuleImporterPresented = true
                        } label: {
                            Label("Add Module Package", systemImage: "plus.square.on.square")
                        }

                        if modulePackageManager.installedPackages.isEmpty {
                            Text("No module packages installed.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(modulePackageManager.installedPackages) { package in
                                ModulePackageRow(package: package)
                            }
                            .onDelete(perform: removePackages)
                        }

                        Text("Import a JSON module package manifest. Computer Search, Mobile Device Search, and Prestage Director are bundled with the framework and remain preinstalled by default.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let modulePackageStatusMessage {
                        Section {
                            Text(modulePackageStatusMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("About") {
                        NavigationLink {
                            AboutView()
                        } label: {
                            Label("About Jamf Dashboard", systemImage: "info.circle")
                        }
                    }
                }
                .appInsetGroupedListStyle()
            }
            .fileImporter(
                isPresented: $isModuleImporterPresented,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleModulePackageImport(result: result)
            }
            .navigationTitle("Settings")
            .appInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .appTopBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .alert(
                "Module Package Error",
                isPresented: Binding(
                    get: { modulePackageErrorMessage != nil },
                    set: { isPresented in
                        if isPresented == false {
                            modulePackageErrorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(modulePackageErrorMessage ?? "Unknown error.")
            }
        }
    }

    /// Handles handleModulePackageImport.
    private func handleModulePackageImport(result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else {
                return
            }

            Task {
                await installModulePackage(from: url)
            }
        case let .failure(error):
            modulePackageStatusMessage = nil
            modulePackageErrorMessage = error.localizedDescription
        }
    }

    /// Handles installModulePackage.
    private func installModulePackage(from fileURL: URL) async {
        do {
            let installedPackage = try await modulePackageManager.installPackage(from: fileURL)
            modulePackageStatusMessage = "Installed \(installedPackage.resolvedModuleTitle) (\(installedPackage.packageVersion))."
            modulePackageErrorMessage = nil
        } catch {
            modulePackageStatusMessage = nil
            modulePackageErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Handles removePackages.
    private func removePackages(at offsets: IndexSet) {
        Task {
            await modulePackageManager.removePackages(at: offsets)
            modulePackageStatusMessage = "Updated installed module packages."
            modulePackageErrorMessage = nil
        }
    }
}

/// ModulePackageRow declaration.
private struct ModulePackageRow: View {
    let package: ModulePackageManifest

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(package.resolvedModuleTitle)
                .font(.subheadline.weight(.semibold))

            Text("Type: \(package.moduleType.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Package ID: \(package.packageID)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Text("Version: \(package.packageVersion)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if package.isBundledDefault {
                Text("Bundled default module")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BrandColors.bluePrimary)
            }
        }
        .padding(.vertical, 2)
    }
}

//endofline
