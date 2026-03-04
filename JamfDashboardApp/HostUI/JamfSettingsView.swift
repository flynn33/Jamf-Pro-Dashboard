// MARK: - Forsetti Compliance
// Adapted from the original SettingsView. Module package import and management sections
// have been removed because Forsetti handles module discovery through manifest JSON files
// in the ForsettiManifests/ bundle directory, and module activation through ActivationStore.
// Credentials and diagnostics configuration remain as host-level concerns.

import SwiftUI

/// JamfSettingsView declaration.
/// Adapted from the original SettingsView with module package management removed
/// (superseded by Forsetti manifest-based discovery).
struct JamfSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var credentialsStore: JamfCredentialsStore
    let diagnosticsReporter: (any DiagnosticsReporting)?

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
            .navigationTitle("Settings")
            .appInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .appTopBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}
