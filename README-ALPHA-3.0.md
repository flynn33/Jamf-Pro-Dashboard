# Jamf Dashboard - Alpha 3.0 Tester README

This document summarizes what changed in **Jamf Dashboard Alpha 3.0** compared with **Version 2**.

Comparison source used:
- V2 baseline: `/Users/jim.daley/Documents/Jamf-Dashboard-iOS-v2/jamf-dashboard.zip`
- V3 codebase: `/Users/jim.daley/Documents/Jamf-Dashboard/Jamf-Dashboard`

---

## 1) Release Snapshot

- Project version: `3`
- Marketing version: `3`
- New supported platforms:
  - iOS 26+
  - macOS 14+

### Delta at a glance (v2 -> v3)

- Total files: `87 -> 108`
- Changed files: `53`
- New items added in v3 path: `16` (includes new module, macOS assets, entitlements)
- Swift code size: `~8,300 -> ~20,512` lines
- New `SupportTechnician` module alone: `~9,752` lines

---

## 2) Major Additions

### A. New Module: Support Technician (Major New Feature)

A full help-desk workflow module was added:
- Unified search across **computers + mobile devices**
- Device detail pane with prioritized identity/inventory fields
- Manager views and shortcuts for:
  - Application Manager
  - Certificate Manager
  - Account Manager
  - Configuration Profile Manager
  - Group Membership Manager
  - Mobile PIN Control
- Device management actions (with safety confirmations)
- Expanded diagnostics view with graphical indicators/charts
- Action result handling with secure copy workflows for sensitive values

New files:
- `JamfDashboardApp/Modules/SupportTechnician/SupportTechnicianModule.swift`
- `JamfDashboardApp/Modules/SupportTechnician/Models/SupportTechnicianModels.swift`
- `JamfDashboardApp/Modules/SupportTechnician/ViewModels/SupportTechnicianViewModel.swift`
- `JamfDashboardApp/Modules/SupportTechnician/Views/SupportTechnicianView.swift`
- `JamfDashboardApp/Modules/SupportTechnician/Services/SupportTechnicianAPIService.swift`
- `JamfDashboardApp/Modules/SupportTechnician/SupportTechnicianModernAPIResearch.md`

And packaged as a module template:
- `ModulePackageTemplates/support-technician.json`

### B. macOS Distribution Readiness

Added/expanded for macOS support:
- App Sandbox entitlement file:
  - `JamfDashboardApp/JamfDashboardApp.entitlements`
- Hardened runtime/App Sandbox build settings in project config
- macOS app icon set assets added to `Assets.xcassets/AppIcon.appiconset`
- Platform compatibility helper:
  - `JamfDashboardApp/Framework/UI/SwiftUIPlatformCompat.swift`

---

## 3) Enhancements Across Existing Modules

### Computer Search

- More robust inventory fallback behavior
- Better handling of section restrictions and privilege-related 400/403 responses
- Additional fallback query strategies and default field fallback paths
- Improved pre-stage resolution and diagnostics reporting around pre-stage lookups

### Mobile Device Search

- Improved modern/legacy section parameter fallbacks
- Alternate filter retries and exact-match fallbacks
- Better parsing compatibility for mixed Jamf response shapes
- Enhanced pre-stage enrichment, lookup caching, and fallback behavior
- Clearer diagnostics for permission or section-parameter failures

### Prestage Director

- Improved multi-select move/remove flows
- Better progress-state reporting
- Rollback attempts on failed move operations (remove + add workflow safety)
- Cleaner status/error behavior for long-running operations

---

## 4) Technician Module: Feature and UX Additions/Fixes

### Device Information / Navigation

- Single-pane workflow with consistent back-chevron navigation model
- Dedicated entry buttons to open manager views from device detail
- Info/help popovers (`i` buttons) used consistently for control guidance

### Mobile Device Detail Improvements

- Unlock token support:
  - Unlock token is exposed via control flow in device info
  - Token can be copied to clipboard when available
- Update OS control for mobile workflows:
  - `Update iOS` action exposed in mobile device detail

### Diagnostics View Improvements

- Added dedicated, graphical diagnostics presentation:
  - Health indicator
  - Severity bar chart
  - Storage/RAM capacity visual charts
  - CPU, battery, uptime gauges
  - Additional graphic indicators/charts for diagnostic fields
- Added manager shortcut hub in diagnostics for:
  - Applications
  - Configuration Profiles
  - Group Memberships
  - Local User Accounts
  - Certificates
- Added OS update action in diagnostics view
- Added services detail open action from diagnostics
- Added error log controls in diagnostics:
  - `Error Logs` toggle
  - `Get Logs` action to fetch or request logs
  - copy-to-clipboard for retrieved logs
- Removed redundant data from diagnostics display where manager shortcuts now replace list sections (for example certificates/local user account listing in that view)
- Package receipts excluded from diagnostics display view

### Search and Data Quality Fixes

- Mobile search matching updated to denormalized-first field strategy in Support Technician search
- Name/user/serial matching robustness improved for mixed Jamf schemas
- Group membership remove flow improved:
  - Static group removal path implemented
  - Smart group remove attempts return explicit guidance

### Formatting and Readability

- Human-readable section and field labels improved (camelCase and symbol-heavy labels are normalized)
- Expanded readability tuning (larger dynamic type sizing in technician workflows)

### Control Safety

- Confirmation prompts expanded across technician control actions
- Destructive remove-management / erase actions require stronger confirmation flow (typed `Remove` step)

### Ticket Workflow Changes

- Technician bootstrapping for ticket logging is disabled in current alpha workflow
- Ticket-number entry / ticket logging path is no longer active as the primary support flow

---

## 5) Framework-Level Improvements

- Diagnostics system updates across framework and modules:
  - Persistent NDJSON error log
  - Improved event/error reporting metadata
  - JSON diagnostics export support
- Networking/auth/security layers updated for broader Jamf compatibility
- Module package management and registry behavior refined
- Dashboard/settings/credentials UI flows updated for cross-platform operation
- Design system updates (including additional background/theming components)

---

## 6) Alpha Tester Focus Areas (Please Validate)

### A. Support Technician End-to-End

1. Search by:
   - device name
   - username
   - serial number
   - across both computer and mobile scope
2. Open a mobile device and validate:
   - unlock token reveal/copy
   - update iOS control behavior
3. Open Diagnostics and validate:
   - charts/indicators render when data exists
   - `Error Logs` -> `Get Logs` flow
   - manager shortcut navigation
4. Validate manager actions:
   - Application install/update/reinstall/remove
   - Certificate add/remove
   - Account add/edit/remove/reset
   - Group add/remove (static vs smart behavior)
5. Validate confirmation UX for risky actions

### B. Existing Modules Regression

1. Computer Search profile save/load/delete
2. Mobile Search profile save/load/delete and pre-stage field behavior
3. Prestage Director move/remove multi-select behavior and rollback on failed move

### C. macOS-Specific

1. App launches and navigates cleanly on macOS
2. Credentials save/load/verify functions
3. Module package install/remove behavior in Settings

---

## 7) Known Alpha Constraints

- Some actions depend on Jamf API role privileges.
- If the Jamf role lacks permissions (for example app installer or MDM command scopes), actions may fail with `403 INVALID_PRIVILEGE`.
- This is expected behavior for insufficient Jamf permissions and should be logged in diagnostics.

---

## 8) Suggested Test Reporting Format

When filing findings, include:

- Platform: iOS or macOS
- Module
- Device type: computer/mobile
- Action performed
- Expected result
- Actual result
- Timestamp
- Diagnostic log export snippet (if available)

---

Thank you for testing **Jamf Dashboard Alpha 3.0**.
