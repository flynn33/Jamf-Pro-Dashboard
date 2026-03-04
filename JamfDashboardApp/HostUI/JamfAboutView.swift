import SwiftUI

/// AboutView declaration.
struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandTheme.Spacing.section) {
                HStack(spacing: 12) {
                    Image(systemName: "desktopcomputer.and.iphone")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(BrandColors.bluePrimary)
                        .accessibilityHidden(true)

                    Text("Jamf Dashboard")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                }

                Text("Jamf Dashboard is a modular support app for Jamf Pro technicians. The framework provides secure credentials storage, centralized Jamf API communication, a module-based dashboard, and diagnostic logging.")
                    .font(.body.weight(.medium))

                Text("How To Use")
                    .font(.system(.headline, design: .rounded).weight(.semibold))

                VStack(alignment: .leading, spacing: BrandTheme.Spacing.item) {
                    Text("1. Open Settings, enter your Jamf Pro URL, choose API client or username/password, then verify the connection.")
                    Text("2. Save the verified credentials to Keychain.")
                    Text("3. Return to the dashboard and choose an installed module.")
                    Text("4. Use each module's workflow to search, review, and manage Jamf Pro data.")
                    Text("5. Open Diagnostics to review events and export logs as JSON when needed.")
                }
                .font(.body)

                Divider()

                VStack(alignment: .leading, spacing: BrandTheme.Spacing.compact) {
                    Text("Built on Forsetti Framework")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text("Forsetti provides sealed modular runtime composition, manifest-based module discovery, entitlement governance, and protocol-first dependency injection for native iOS and macOS applications.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("developed by Jim Daley")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BrandColors.bluePrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .appCardSurface()
            .padding(16)
        }
        .appBackground()
        .navigationTitle("About")
        .appInlineNavigationTitle()
    }
}

//endofline
