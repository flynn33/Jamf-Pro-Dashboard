# Jamf Dashboard

Jamf Dashboard is a modular SwiftUI support application for Jamf Pro operations across **iOS and macOS**. Built on the **Forsetti Framework** for sealed modular runtime composition, manifest-based module discovery, and protocol-first dependency injection.

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
- Forsetti Framework (local SPM dependency)
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

Built on the Forsetti Framework, the application uses sealed modular runtime composition:

- `JamfDashboardBootstrap` initializes `ForsettiRuntime`, registers services in `ForsettiServiceContainer`, registers module factories in `ModuleRegistry`, and creates `ForsettiHostController`.
- `JamfAPIGateway` centralizes Jamf Pro requests for all modules, conforming to `JamfAPIGatewayProviding` for protocol-based resolution.
- `JamfAuthenticationService` manages token issuance, caching, and refresh.
- `JamfCredentialsStore` persists verified credentials in Keychain, conforming to `JamfCredentialsProviding`.
- `DiagnosticsCenter` handles diagnostics reporting/export, bridged to Forsetti via `JamfForsettiLogger`.
- `ForsettiHostController` manages module lifecycle, activation state, and UI selection.
- Modules are discovered via `ForsettiManifests/*.json` and instantiated by registered factories in `ModuleRegistry`.

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

## Module Discovery

Modules are declared via Forsetti manifest JSON files in `JamfDashboardApp/Resources/ForsettiManifests/`. Each manifest declares the module identity, capabilities, supported platforms, and entry point class name. The Forsetti runtime discovers these manifests at boot and activates modules through registered factories.

Manifest example:

```json
{
  "schemaVersion": "1.0",
  "moduleID": "com.jamftool.modules.computer-search",
  "displayName": "Computer Search",
  "moduleVersion": "1.0.0",
  "moduleType": "ui",
  "supportedPlatforms": ["iOS", "macOS"],
  "minForsettiVersion": "0.1.0",
  "capabilitiesRequested": ["networking", "secureStorage", "viewInjection"],
  "entryPoint": "ComputerSearchModule"
}
```

## Navigation and UX Notes

- Standardized top-left back behavior is provided via shared back-button toolbar support.
- Settings includes a top-left Home button for quick return to dashboard.

## Run the App

1. Open `Jamf Dashboard.xcodeproj`.
2. Ensure Forsetti Framework is resolved as a local SPM dependency.
3. Select a destination (iOS simulator/device or macOS "My Mac").
4. Build and run.
5. Open `Settings -> Jamf Credentials`.
6. Enter server URL and authentication credentials.
7. Verify connection, then save credentials.
8. Return to the dashboard and open a module.

## Local Data and Logs

- Credentials: Keychain (`com.jamfdashboard.app` service)
- Search profiles:
  - `Application Support/JamfDashboard/computer-search-profiles.json`
  - `Application Support/JamfDashboard/mobile-device-search-profiles.json`
- Diagnostics exports: `Documents/JamfDashboardDiagnostics/`
- Persistent error log: `Documents/JamfDashboardDiagnostics/jamf-dashboard-errors.ndjson`

## Guides

- Local guide: `WIKI.md`
- Wiki pages: `docs/wiki/`
