# Getting Started

Audience: operators, testers, and engineers preparing Jamf Dashboard locally.

## Prerequisites

- Xcode 26+ on macOS with an iOS 26 simulator or macOS 14 destination
- Jamf Pro base URL reachable from the device/simulator
- One authentication option:
  - Jamf API Client (`client_id` + `client_secret`)
  - Jamf account (`username` + `password`)
- Jamf role permissions for inventory reads and any management commands you plan to use

## Build and run

1. Open `Jamf Dashboard.xcodeproj` in Xcode.
2. Pick a destination (iOS simulator/device or macOS “My Mac”).
3. Build and run.
4. In the app, open `Settings -> Jamf Credentials`.
5. Enter the Jamf URL, pick the auth method, and fill the credential fields.
6. Select **Verify Connection**. Save credentials only after verification succeeds.
7. Return to the dashboard and launch a module.

## Module packages

- Default bundled modules install on first launch:
  - Computer Search
  - Mobile Device Search
  - Support Technician
  - Prestage Director
- Install additional packages from `Settings -> Module Packages` using a JSON manifest (templates live in `ModulePackageTemplates/`).
- Package validation prevents duplicate package IDs and unsupported module types; bundled defaults are re-applied during bootstrap if removed.

## Local data and resets

- Credentials: stored in Keychain (service `com.jamfdashboard.app`).
- Module packages: `Application Support/JamfDashboard/installed-module-packages.json`.
- Saved search profiles:
  - `Application Support/JamfDashboard/computer-search-profiles.json`
  - `Application Support/JamfDashboard/mobile-device-search-profiles.json`
- Diagnostics exports: `Documents/JamfDashboardDiagnostics/`.
- Persistent error log: `Documents/JamfDashboardDiagnostics/jamf-dashboard-errors.ndjson`.

## Quick smoke test

- Run Support Technician and search by username or serial; confirm a device opens with inventory details.
- Open Diagnostics from that device, toggle **Error Logs**, and try **Get Logs** to confirm logging works.
- From Settings, install a sample package from `ModulePackageTemplates/` to confirm manifest loading and duplicate detection.
