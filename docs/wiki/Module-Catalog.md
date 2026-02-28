# Module Catalog

## Module contract

All modules conform to `JamfModule` and render their root view via `makeRootView(context:)`, receiving gateway, credentials, and diagnostics services through `ModuleContext`. See [Architecture](Architecture.md) for the full contract definition.

---

## Computer Search

**Package type:** `computer-search`  
**Default package ID:** `com.jamftool.modules.computer-search`  
**Icon:** `desktopcomputer`

### Overview

Searches Jamf Pro computer inventory and presents results in a configurable field layout. Operators can save reusable field-selection profiles and reload them across sessions.

### Features

- Free-text search against Jamf computer inventory.
- Field catalog: choose which inventory fields are displayed per result.
- Profile management: save, load, rename, and delete named field profiles.
- Profiles persist to `Application Support/JamfDashboard/computer-search-profiles.json`.
- Endpoint/query fallback strategy: the module retries with compatibility fallbacks when the primary endpoint returns a 400, 403, or unexpected shape, accommodating Jamf tenants with mixed API versions or privilege restrictions.
- Barcode/QR entry via the shared `CodeScannerSheet` where camera hardware is available.

### Typical workflow

1. Open Computer Search from the dashboard.
2. Enter a search term (computer name, serial, username, etc.).
3. Review results with the default field set, or load a saved profile.
4. To save a profile: choose fields, name the profile, and save.

---

## Mobile Device Search

**Package type:** `mobile-device-search`  
**Default package ID:** `com.jamftool.modules.mobile-device-search`  
**Icon:** `iphone.gen3`

### Overview

Searches Jamf Pro mobile device inventory with the same profile-based field selection model as Computer Search, extended with pre-stage enrichment for enrollment context.

### Features

- Free-text mobile inventory search.
- Field catalog and reusable profiles (save/load/delete), persisted to `Application Support/JamfDashboard/mobile-device-search-profiles.json`.
- Section/wildcard fallback behavior for tenants that restrict certain section parameters.
- Pre-stage enrichment: attempts to resolve pre-stage enrollment profile details for each result, with in-memory caching and graceful fallback when the pre-stage API is unavailable or restricted.
- Compatibility fallbacks for mixed Jamf response shapes.
- Barcode/QR entry via the shared `CodeScannerSheet`.

### Typical workflow

1. Open Mobile Device Search from the dashboard.
2. Enter a search term (device name, serial, username, UDID, etc.).
3. Review results; the pre-stage profile column enriches results when data is available.
4. Save or load a field profile as needed.

---

## Support Technician

**Package type:** `support-technician`  
**Default package ID:** `com.jamftool.modules.support-technician`  
**Icon:** `wrench.and.screwdriver`

### Overview

Unified help-desk workflow module that searches across both computers and mobile devices, presents device details with manager shortcuts, and enables management actions from a single interface.

### Features

#### Search

- Unified search across computers and mobile devices by:
  - Device name
  - Username / assigned user
  - Serial number
- Denormalized-first field matching strategy for compatibility with mixed Jamf schemas.

#### Device detail

- Identity and inventory priority signals displayed at the top.
- Dedicated shortcuts to manager views:
  - **Applications** — install, update, reinstall, remove
  - **Certificates** — add, remove
  - **Accounts** — add, edit, remove, reset
  - **Configuration Profiles** — manage profiles
  - **Group Membership** — add/remove static groups; smart group guidance for attempted removals
  - **Services** — service detail access

#### Mobile device extras

- **Unlock token** — revealed and available for clipboard copy when the Jamf role permits.
- **Update iOS** — queues an OS update MDM command.

#### Diagnostics view

- Health indicator.
- Severity bar chart for diagnostics events.
- Storage and RAM capacity visual charts.
- CPU, battery, and uptime gauges.
- Manager shortcut hub (Applications, Configuration Profiles, Group Memberships, Local User Accounts, Certificates).
- **Error Logs** toggle and **Get Logs** action for fetching or requesting logs from the device.
- OS update action available directly from the diagnostics view.
- Copy-to-clipboard for retrieved sensitive values.

#### Recovery and security secrets (computer)

- **FileVault recovery key** (`GET /api/v3/computers-inventory/{id}/filevault`)
- **Recovery lock password** (`GET /api/v3/computers-inventory/{id}/view-recovery-lock-password`)
- **Device lock PIN** (`GET /api/v3/computers-inventory/{id}/view-device-lock-pin`)

#### LAPS (Local Admin Password Solution)

- Lists LAPS-capable accounts (`GET /api/v2/local-admin-password/{clientManagementId}/accounts`).
- Views current password (`GET /api/v2/local-admin-password/{clientManagementId}/account/{username}/password`).
- Rotates password (`PUT /api/v2/local-admin-password/{clientManagementId}/set-password`).

#### Safety confirmations

- Confirmation prompts on all sensitive management actions.
- Destructive **remove management** and **erase** flows require the operator to type `Remove` before the action proceeds.

### Jamf API privilege requirements

The module degrades gracefully per action when the API role lacks a specific privilege. A `403 INVALID_PRIVILEGE` response is expected and logged to diagnostics for any capability the role does not include.

Minimum privileges for full functionality:

| Action | Required privilege |
|---|---|
| Computer/mobile inventory search | Read Computer Inventory / Read Mobile Devices |
| Queue MDM commands | Send MDM Commands |
| Computer erase | Erase Device |
| Remove MDM profile | Remove MDM Profile |
| Unmanage mobile device | Unmanage Devices |
| FileVault / Recovery Lock / PIN | View Disk Encryption Recovery Key |
| View LAPS password | View Local Admin Password |
| Rotate LAPS password | Set Local Admin Password |

### Typical workflow

1. Open Support Technician from the dashboard.
2. Enter a search term (username, serial, or device name).
3. Select a device from the result list.
4. Review inventory details, or open a manager view for a specific action.
5. For sensitive actions, confirm the prompt; for destructive actions, type `Remove` to proceed.

---

## Prestage Director

**Package type:** `prestage-director`  
**Default package ID:** `com.jamftool.modules.prestage-director`  
**Icon:** `arrow.left.arrow.right.square`

### Overview

Displays Jamf Pro pre-stage enrollment profiles and their scoped devices. Supports multi-select operations for moving devices between prestages or removing them from prestage scope.

### Features

- Lists all available pre-stage enrollment profiles.
- Displays devices scoped to each profile.
- Multi-select mode for bulk move or remove operations.
- Move workflow: removes devices from the current prestage, then adds them to the target prestage; a rollback step re-adds devices to the original prestage if the move fails.
- Progress tracking with live status updates per device during bulk operations.
- Designed to tolerate long-running Jamf operations with clear status and error reporting.

### Typical workflow

1. Open Prestage Director from the dashboard.
2. Select a pre-stage enrollment profile to see its scoped devices.
3. Select one or more devices.
4. Choose **Remove** to remove them from the prestage scope, or **Move** to transfer them to a different prestage.
5. Monitor progress; any failures are shown per device with retry guidance.
