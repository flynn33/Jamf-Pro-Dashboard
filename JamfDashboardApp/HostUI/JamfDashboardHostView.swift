// MARK: - Forsetti Compliance
// Custom branded host view that delegates module lifecycle to ForsettiHostController.
// Reads controller.uiModules for discovered modules, calls controller.openModule(moduleID:)
// for navigation, and resolves module workspace views through ForsettiViewInjectionRegistry.
// Replaces the developer-facing ForsettiHostRootView with a production Jamf-branded experience
// while preserving all Forsetti runtime guarantees (entitlement checks, activation state, lifecycle).

import SwiftUI
import ForsettiCore
import ForsettiHostTemplate

/// JamfDashboardHostView declaration.
/// Custom branded host view that wraps ForsettiHostController for Jamf Dashboard.
/// Replaces ForsettiHostRootView with the Jamf-branded dashboard experience.
struct JamfDashboardHostView: View {
    private enum ActiveSheet: String, Identifiable {
        case settings
        case diagnostics

        var id: String { rawValue }
    }

    @ObservedObject private var controller: ForsettiHostController
    private let injectionRegistry: ForsettiViewInjectionRegistry
    @ObservedObject private var credentialsStore: JamfCredentialsStore
    private let diagnosticsCenter: DiagnosticsCenter

    @State private var activeSheet: ActiveSheet?

    init(
        controller: ForsettiHostController,
        injectionRegistry: ForsettiViewInjectionRegistry,
        credentialsStore: JamfCredentialsStore,
        diagnosticsCenter: DiagnosticsCenter
    ) {
        self.controller = controller
        self.injectionRegistry = injectionRegistry
        self.credentialsStore = credentialsStore
        self.diagnosticsCenter = diagnosticsCenter
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 164), spacing: BrandTheme.Spacing.item)]
    }

    var body: some View {
        NavigationStack {
            if let selectedModule = controller.selectedModuleItem() {
                moduleWorkspace(module: selectedModule)
            } else {
                dashboardHome
            }
        }
        .task {
            await controller.bootIfNeeded()
            credentialsStore.refreshState()
        }
        .sheet(item: $activeSheet) { activeSheet in
            switch activeSheet {
            case .settings:
#if os(macOS)
                JamfSettingsView(
                    credentialsStore: credentialsStore,
                    diagnosticsReporter: diagnosticsCenter
                )
                .frame(minWidth: 900, minHeight: 650)
#else
                JamfSettingsView(
                    credentialsStore: credentialsStore,
                    diagnosticsReporter: diagnosticsCenter
                )
#endif
            case .diagnostics:
#if os(macOS)
                DiagnosticsView(
                    viewModel: DiagnosticsViewModel(diagnosticsReporter: diagnosticsCenter)
                )
                .frame(minWidth: 860, minHeight: 620)
#else
                DiagnosticsView(
                    viewModel: DiagnosticsViewModel(diagnosticsReporter: diagnosticsCenter)
                )
#endif
            }
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { controller.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        controller.clearError()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                controller.clearError()
            }
        } message: {
            Text(controller.errorMessage ?? "Unknown error")
        }
    }

    private var dashboardHome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandTheme.Spacing.section) {
                AppHeader()
                CredentialStatusCard(hasCredentials: credentialsStore.hasStoredCredentials)

                VStack(alignment: .leading, spacing: BrandTheme.Spacing.item) {
                    Text("Installed Modules")
                        .font(.system(.headline, design: .rounded).weight(.semibold))

                    if controller.uiModules.isEmpty {
                        Text("No modules are installed.")
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: BrandTheme.Spacing.item) {
                            ForEach(controller.uiModules) { module in
                                Button {
                                    Task {
                                        await controller.openModule(moduleID: module.moduleID)
                                    }
                                } label: {
                                    ModuleCard(
                                        title: module.displayName,
                                        subtitle: resolveModuleSubtitle(moduleID: module.moduleID),
                                        iconSystemName: resolveModuleIcon(moduleID: module.moduleID)
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
    }

    @ViewBuilder
    private func moduleWorkspace(module: ForsettiHostModuleItem) -> some View {
        if let contributions = controller.uiContributions(for: module.moduleID) {
            let workspaceInjections = contributions.viewInjections.filter {
                $0.slot == SlotCatalog.moduleWorkspace
            }.sorted(by: { $0.priority > $1.priority })

            if let injection = workspaceInjections.first,
               let injectedView = injectionRegistry.resolve(viewID: injection.viewID) {
                injectedView
                    .navigationTitle(module.displayName)
                    .appInlineNavigationTitle()
#if os(macOS)
                    .frame(minWidth: 1200, minHeight: 820)
#endif
                    .toolbar {
                        ToolbarItem(placement: .appTopBarLeading) {
                            Button {
                                controller.goHome()
                            } label: {
                                Label("Back", systemImage: "chevron.left")
                            }
                        }

                        ToolbarItem(placement: .appTopBarTrailing) {
                            Button {
                                activeSheet = .diagnostics
                            } label: {
                                Label("Diagnostics", systemImage: "stethoscope")
                            }
                        }
                    }
            } else {
                moduleUnavailableView(module: module)
            }
        } else {
            moduleUnavailableView(module: module)
        }
    }

    private func moduleUnavailableView(module: ForsettiHostModuleItem) -> some View {
        ContentUnavailableView(
            "Module Unavailable",
            systemImage: "exclamationmark.triangle",
            description: Text("The view for \(module.displayName) could not be loaded.")
        )
        .toolbar {
            ToolbarItem(placement: .appTopBarLeading) {
                Button {
                    controller.goHome()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
            }
        }
    }

    private func resolveModuleSubtitle(moduleID: String) -> String {
        let subtitleMap: [String: String] = [
            "com.jamftool.modules.computer-search": "Search computer inventory and create reusable field-based profiles.",
            "com.jamftool.modules.mobile-device-search": "Search inventory and create reusable field-based profiles.",
            "com.jamftool.modules.support-technician": "Unified support workflow for computers and mobile devices.",
            "com.jamftool.modules.prestage-director": "View prestages and move or remove assigned devices."
        ]
        return subtitleMap[moduleID] ?? ""
    }

    private func resolveModuleIcon(moduleID: String) -> String {
        let iconMap: [String: String] = [
            "com.jamftool.modules.computer-search": "desktopcomputer",
            "com.jamftool.modules.mobile-device-search": "iphone.gen3",
            "com.jamftool.modules.support-technician": "wrench.and.screwdriver",
            "com.jamftool.modules.prestage-director": "arrow.left.arrow.right.square"
        ]
        return iconMap[moduleID] ?? "puzzlepiece"
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
