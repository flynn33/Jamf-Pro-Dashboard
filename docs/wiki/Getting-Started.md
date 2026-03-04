# Getting Started

Audience: operators, testers, and engineers preparing Jamf Dashboard locally.

## Prerequisites

- Xcode 26+ on macOS with an iOS 26 simulator or a macOS 14+ destination ("My Mac")
- Forsetti Framework (local SPM dependency)
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
2. Ensure Forsetti Framework is resolved as a local SPM dependency.
3. Select a destination from the toolbar — iOS simulator, a connected device, or **My Mac** for native macOS.
4. Press **Run** (⌘R) or choose **Product → Run**.
5. In the running app, open **Settings → Jamf Credentials**.
6. Enter the Jamf Pro server URL (e.g. `https://yourorg.jamfcloud.com`).
7. Select the authentication method (API Client or Username & Password).
8. Enter the credential fields for the selected method.
9. Tap or click **Verify Connection**.
10. After a successful verification, tap or click **Save**.
11. Return to the dashboard. The four built-in modules appear as tiles.

> The server URL is normalized automatically: a missing `https://` scheme is prepended before any network call is made.

## First-launch module discovery

On first launch the Forsetti runtime discovers module manifests from `Resources/ForsettiManifests/` and activates the four built-in modules through registered factories. After boot, the dashboard displays:

| Module | Module ID |
|---|---|
| Computer Search | `com.jamftool.modules.computer-search` |
| Mobile Device Search | `com.jamftool.modules.mobile-device-search` |
| Support Technician | `com.jamftool.modules.support-technician` |
| Prestage Director | `com.jamftool.modules.prestage-director` |

Module activation state is persisted by Forsetti's `ActivationStore` and restored automatically on relaunch.

## Local data locations

| Data | Location |
|---|---|
| Credentials | Keychain — service `com.jamfdashboard.app`, key `jamf.credentials` |
| Computer search profiles | `Application Support/JamfDashboard/computer-search-profiles.json` |
| Mobile device search profiles | `Application Support/JamfDashboard/mobile-device-search-profiles.json` |
| Diagnostics exports | `Documents/JamfDashboardDiagnostics/` |
| Persistent error log | `Documents/JamfDashboardDiagnostics/jamf-dashboard-errors.ndjson` |

On iOS these paths are inside the app's sandboxed container. On macOS they are in the user's home directory under `~/Library/` and `~/Documents/`.

## Resetting the app

To perform a clean reset:

1. Delete credentials — open **Settings → Jamf Credentials** and clear all fields, then save; or delete the Keychain item for service `com.jamfdashboard.app` directly.
2. Delete search profiles — remove `computer-search-profiles.json` and `mobile-device-search-profiles.json` from Application Support.
3. Delete diagnostics — remove the `JamfDashboardDiagnostics/` folder from Documents.
4. Relaunch to re-discover modules through the Forsetti runtime.

## Quick smoke test

After first launch, run through these steps to confirm everything is working:

1. **Credentials** — open **Settings → Jamf Credentials**, enter a valid URL and credentials, tap **Verify Connection**, confirm the success indicator, then save.
2. **Computer Search** — open the Computer Search module, search for a known computer name, and confirm results appear with inventory fields.
3. **Search Profiles** — save a Computer Search profile, relaunch the module, and confirm the saved profile loads correctly.
4. **Support Technician** — search by a known username or serial number, open a device, and confirm inventory fields are displayed.
5. **Diagnostics** — from a Support Technician device detail, open **Diagnostics**, toggle **Error Logs**, and tap **Get Logs** to confirm logging functions.
