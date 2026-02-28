# Getting Started

Audience: operators, testers, and engineers preparing Jamf Dashboard locally.

## Prerequisites

- Xcode 26+ on macOS with an iOS 26 simulator or a macOS 14+ destination ("My Mac")
- Jamf Pro base URL reachable from the device or simulator
- One authentication option:
  - **API Client** — a Jamf API client with `client_id` and `client_secret`
  - **Username & Password** — a Jamf account `username` and `password`
- Jamf role with at minimum read access to computer and mobile inventory; additional MDM command privileges are required to use management actions in Support Technician

## Setting up a Jamf API Client (recommended)

1. In Jamf Pro, navigate to **Settings → System → API Roles and Clients**.
2. Create a role with the minimum privileges you need (inventory read is sufficient for search-only use).
3. Create an API Client assigned to that role and copy the `client_id` and `client_secret`.
4. Use the **API Client** auth method in Jamf Dashboard with those values.

For management actions in Support Technician, add the following privileges to the role:

| Capability | Privilege |
|---|---|
| Queue MDM commands | Send MDM Commands |
| Erase computer | Erase Device |
| Remove MDM profile | Remove MDM Profile |
| Unmanage mobile device | Unmanage Devices |
| View FileVault / Recovery Lock | View Disk Encryption Recovery Key |
| View LAPS password | View Local Admin Password |
| Rotate LAPS password | Set Local Admin Password |

## Build and run

1. Open `Jamf Dashboard.xcodeproj` in Xcode.
2. Select a destination from the toolbar — iOS simulator, a connected device, or **My Mac** for native macOS.
3. Press **Run** (⌘R) or choose **Product → Run**.
4. In the running app, open **Settings → Jamf Credentials**.
5. Enter the Jamf Pro server URL (e.g. `https://yourorg.jamfcloud.com`).
6. Select the authentication method (API Client or Username & Password).
7. Enter the credential fields for the selected method.
8. Tap or click **Verify Connection**.
9. After a successful verification, tap or click **Save**.
10. Return to the dashboard. The four built-in modules appear as tiles.

> The server URL is normalized automatically: a missing `https://` scheme is prepended before any network call is made.

## First-launch module bootstrap

On first launch `ModulePackageManager.bootstrap()` runs and installs the four bundled default modules if they are not already present. After bootstrap, the dashboard displays:

| Module | Package ID |
|---|---|
| Computer Search | `com.jamftool.modules.computer-search` |
| Mobile Device Search | `com.jamftool.modules.mobile-device-search` |
| Support Technician | `com.jamftool.modules.support-technician` |
| Prestage Director | `com.jamftool.modules.prestage-director` |

These defaults are protected — if they are removed, bootstrap re-installs them on the next launch.

## Module packages

- Install additional packages from **Settings → Module Packages** using a JSON manifest.
- Template manifests live in `ModulePackageTemplates/`.
- The minimum required fields are `package_id` and `module_type`.
- Duplicate `package_id` values and unrecognized `module_type` strings are rejected with an error.

Minimal manifest example:

```json
{
  "package_id": "com.example.extra-computer-search",
  "module_type": "computer-search",
  "package_version": "1.0.0",
  "module_display_name": "Extra Computer Search",
  "module_subtitle": "A second computer search tile",
  "icon_system_name": "desktopcomputer"
}
```

Supported `module_type` values: `computer-search`, `mobile-device-search`, `support-technician`, `prestage-director`.

## Local data locations

| Data | Location |
|---|---|
| Credentials | Keychain — service `com.jamfdashboard.app`, key `jamf.credentials` |
| Installed module packages | `Application Support/JamfDashboard/installed-module-packages.json` |
| Computer search profiles | `Application Support/JamfDashboard/computer-search-profiles.json` |
| Mobile device search profiles | `Application Support/JamfDashboard/mobile-device-search-profiles.json` |
| Diagnostics exports | `Documents/JamfDashboardDiagnostics/` |
| Persistent error log | `Documents/JamfDashboardDiagnostics/jamf-dashboard-errors.ndjson` |

On iOS these paths are inside the app's sandboxed container. On macOS they are in the user's home directory under `~/Library/` and `~/Documents/`.

## Resetting the app

To perform a clean reset:

1. Delete credentials — open **Settings → Jamf Credentials** and clear all fields, then save; or delete the Keychain item for service `com.jamfdashboard.app` directly.
2. Delete persisted module packages — remove `installed-module-packages.json` from Application Support.
3. Delete search profiles — remove `computer-search-profiles.json` and `mobile-device-search-profiles.json` from Application Support.
4. Delete diagnostics — remove the `JamfDashboardDiagnostics/` folder from Documents.
5. Relaunch to re-apply default module packages through bootstrap.

## Quick smoke test

After first launch, run through these steps to confirm everything is working:

1. **Credentials** — open **Settings → Jamf Credentials**, enter a valid URL and credentials, tap **Verify Connection**, confirm the success indicator, then save.
2. **Computer Search** — open the Computer Search module, search for a known computer name, and confirm results appear with inventory fields.
3. **Search Profiles** — save a Computer Search profile, relaunch the module, and confirm the saved profile loads correctly.
4. **Support Technician** — search by a known username or serial number, open a device, and confirm inventory fields are displayed.
5. **Diagnostics** — from a Support Technician device detail, open **Diagnostics**, toggle **Error Logs**, and tap **Get Logs** to confirm logging functions.
6. **Module Packages** — open **Settings → Module Packages** and install the `ModulePackageTemplates/computer-search.json` template to confirm manifest loading; confirm the duplicate detection rejects a second install attempt.
