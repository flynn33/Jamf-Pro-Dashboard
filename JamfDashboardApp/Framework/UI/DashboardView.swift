import SwiftUI

/// DashboardView declaration.
struct DashboardView: View {
    /// ActiveSheet declaration.
    private enum ActiveSheet: String, Identifiable {
        case settings
        case diagnostics

        var id: String { rawValue }
    }

    @ObservedObject var container: JamfFrameworkContainer
    @ObservedObject private var moduleRegistry: ModuleRegistry

    @State private var activeSheet: ActiveSheet?

    /// Initializes the instance.
    init(container: JamfFrameworkContainer) {
        self.container = container
        _moduleRegistry = ObservedObject(wrappedValue: container.moduleRegistry)
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 164), spacing: BrandTheme.Spacing.item)]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BrandTheme.Spacing.section) {
                    AppHeader()
                    CredentialStatusCard(hasCredentials: container.credentialsStore.hasStoredCredentials)

                    VStack(alignment: .leading, spacing: BrandTheme.Spacing.item) {
                        Text("Installed Modules")
                            .font(.system(.headline, design: .rounded).weight(.semibold))

                        if moduleRegistry.modules.isEmpty {
                            Text("No modules are installed.")
                                .foregroundStyle(.secondary)
                        } else {
                            LazyVGrid(columns: columns, alignment: .leading, spacing: BrandTheme.Spacing.item) {
                                ForEach(moduleRegistry.modules, id: \.id) { module in
                                    NavigationLink(value: module.id) {
                                        ModuleCard(
                                            title: module.title,
                                            subtitle: module.subtitle,
                                            iconSystemName: module.iconSystemName
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, BrandTheme.Spacing.section)
                .padding(.vertical, BrandTheme.Spacing.section)
            }
            .background {
                ZStack {
                    BrandTheme.groupedSurface
                    BrandMetalBackgroundView()
                    BrandTheme.appBackdropGradient.opacity(0.62)
                }
                .ignoresSafeArea()
            }
            .navigationTitle("Jamf Dashboard")
            .toolbar {
                ToolbarItem(placement: .appTopBarLeading) {
                    Button {
                        activeSheet = .diagnostics
                    } label: {
                        Label("Diagnostics", systemImage: "stethoscope")
                    }
                }

                ToolbarItem(placement: .appTopBarTrailing) {
                    Button {
                        activeSheet = .settings
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .sheet(item: $activeSheet) { activeSheet in
                switch activeSheet {
                case .settings:
#if os(macOS)
                    SettingsView(
                        credentialsStore: container.credentialsStore,
                        diagnosticsReporter: container.diagnosticsCenter,
                        modulePackageManager: container.modulePackageManager
                    )
                    .frame(minWidth: 900, minHeight: 650)
#else
                    SettingsView(
                        credentialsStore: container.credentialsStore,
                        diagnosticsReporter: container.diagnosticsCenter,
                        modulePackageManager: container.modulePackageManager
                    )
#endif
                case .diagnostics:
#if os(macOS)
                    DiagnosticsView(
                        viewModel: DiagnosticsViewModel(diagnosticsReporter: container.diagnosticsCenter)
                    )
                    .frame(minWidth: 860, minHeight: 620)
#else
                    DiagnosticsView(
                        viewModel: DiagnosticsViewModel(diagnosticsReporter: container.diagnosticsCenter)
                    )
#endif
                }
            }
            .navigationDestination(for: String.self) { moduleID in
                if let module = moduleRegistry.module(withID: moduleID) {
                    module.makeRootView(context: container.moduleContext)
                        .navigationTitle(module.title)
                        .appInlineNavigationTitle()
#if os(macOS)
                        .frame(minWidth: 1200, minHeight: 820)
#endif
                } else {
                    ContentUnavailableView(
                        "Module Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("The selected module could not be loaded.")
                    )
                }
            }
            .onAppear {
                container.credentialsStore.refreshState()
            }
        }
    }
}

/// CredentialStatusCard declaration.
private struct CredentialStatusCard: View {
    let hasCredentials: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: BrandTheme.Spacing.compact) {
            Label(
                hasCredentials ? "Connected credentials configured" : "Credentials required",
                systemImage: hasCredentials ? "checkmark.seal.fill" : "lock.trianglebadge.exclamationmark"
            )
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .foregroundStyle(hasCredentials ? BrandColors.greenPrimary : .orange)

            Text(hasCredentials ?
                 "Modules can call the Jamf API through the framework gateway." :
                 "Open Settings to add Jamf Pro URL, choose one login method, verify, then save.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .appCardSurface()
    }
}

/// ModuleCard declaration.
private struct ModuleCard: View {
    let title: String
    let subtitle: String
    let iconSystemName: String

    var body: some View {
        VStack(alignment: .leading, spacing: BrandTheme.Spacing.item) {
            Image(systemName: iconSystemName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(BrandColors.bluePrimary)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(BrandColors.blueSecondary.opacity(0.22))
                )

            Text(title)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 152, alignment: .topLeading)
        .padding(16)
        .appCardSurface()
    }
}

/// AppHeader declaration.
private struct AppHeader: View {
    var body: some View {
        HStack {
            Image(systemName: "desktopcomputer.and.iphone")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(BrandColors.bluePrimary)
                .accessibilityHidden(true)

            Text("Jamf Dashboard")
                .font(.system(.title3, design: .rounded).weight(.bold))

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCardSurface(fill: BrandTheme.groupedSurface)
    }
}

//endofline
