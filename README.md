# Jamf Dashboard

Jamf Dashboard is a modular SwiftUI support application for Jamf Pro operations across **iOS and macOS**.

Current release: `3` (`CURRENT_PROJECT_VERSION = 3`, `MARKETING_VERSION = 3`)

**Attribution:** developed by Jim Daley

## Downloads and Distribution

This project is distributed in two ways:

1. **Packaged releases** (recommended for testers)
   - Download the latest **DMG / PKG** from the **GitHub Releases** page for this repo.
   - These are the builds intended for real testing, without requiring Xcode.

2. **Build from source**
   - If you prefer to audit or build locally, follow the steps in **Run the App** below.


## Requirements for building

- Xcode 26+
- Deployment targets:
  - iOS 26.0+
  - macOS 14.0+
- Valid Jamf Pro server URL
- Authentication using either:
  - Jamf API Client (`client_id` + `client_secret`)
  - Jamf account (`username` + `password`)

## Security and Distribution (macOS)

For notarization/App Store distribution, the macOS build is configured with:

- App Sandbox entitlement (`com.apple.security.app-sandbox = true`)
- Hardened Runtime enabled

Configured in:

- `JamfDashboardApp/JamfDashboardApp.entitlements`
- `Jamf Dashboard.xcodeproj/project.pbxproj`

## Architecture Overview

- `JamfFrameworkContainer` bootstraps shared services and module loading.
- `JamfAPIGateway` centralizes Jamf Pro requests for all modules.
- `JamfAuthenticationService` manages token issuance, caching, and refresh.
- `JamfCredentialsStore` persists verified credentials in Keychain.
- `DiagnosticsCenter` handles diagnostics reporting/export.
- `ModuleRegistry` and `ModulePackageManager` control module availability.

## Built-In Modules

- `Computer Search`
  - Computer inventory search with reusable field profiles
  - Endpoint/query fallback behavior for broader Jamf compatibility

- `Mobile Device Search`
  - Mobile inventory search with reusable field profiles
  - Section/filter fallback handling and pre-stage enrichment

  ##THE SUPPORT TECHNICIAN MODULE IS AN ALPHA BUILD. DO NOT USE ON A PRODUCTION SERVER OR INSTANCE.  MANY OF THE FEATURES ARE NOT FULLY IMPLEMENTED AND COULD LEAD TO UNEXPECTED RESULTS.

- `Support Technician`
  - Unified help-desk workflow across computer and mobile inventory
  - Device command confirmations for sensitive actions
  - Typed `Remove` confirmation requirement for destructive remove-device action
  - Dedicated **Manage Applications** view for per-device app actions:
    - Install
    - Update
    - Reinstall
    - Remove

- `Prestage Director`
  - View pre-stage enrollment profiles and scoped devices
  - Multi-select remove/move workflows with progress and rollback handling

## Navigation and UX Notes

- Standardized top-left back behavior is provided via shared back-button toolbar support.
- Settings includes a top-left Home button for quick return to dashboard.

## Module Packages

- Module packages are JSON manifests.
- Install/remove is available in `Settings -> Module Packages`.
- Bundled default modules are protected and re-applied during bootstrap.
- Examples are in `ModulePackageTemplates/`.

Minimum manifest shape:

```json
{
  "package_id": "com.jamftool.modules.example",
  "module_type": "computer-search",
  "package_version": "1.0.0",
  "module_display_name": "Example Module",
  "module_subtitle": "Example subtitle",
  "icon_system_name": "square.grid.2x2"
}
```

## Run the App

1. Open `Jamf Dashboard.xcodeproj`.
2. Select a destination (iOS simulator/device or macOS "My Mac").
3. Build and run.
4. Open `Settings -> Jamf Credentials`.
5. Enter server URL and authentication credentials.
6. Verify connection, then save credentials.
7. Return to the dashboard and open a module.

## Local Data and Logs

- Credentials: Keychain (`com.jamfdashboard.app` service)
- Module packages: `Application Support/JamfDashboard/installed-module-packages.json`
- Search profiles:
  - `Application Support/JamfDashboard/computer-search-profiles.json`
  - `Application Support/JamfDashboard/mobile-device-search-profiles.json`
- Diagnostics exports: `Documents/JamfDashboardDiagnostics/`
- Persistent error log: `Documents/JamfDashboardDiagnostics/jamf-dashboard-errors.ndjson`

## Guides

- Local guide: `WIKI.md`
- Module reference notes: `JamfDashboardApp/Modules/SupportTechnician/SupportTechnicianModernAPIResearch.md`
