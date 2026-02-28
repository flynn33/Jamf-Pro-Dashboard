# Operations and Troubleshooting

## Credentials lifecycle

- Update credentials from `Settings -> Jamf Credentials`; choose the auth method and run **Verify Connection** before saving.
- Connection failures: confirm the Jamf URL, auth method, and that the role has inventory and management privileges required for the action you attempted.
- If you rotate credentials, re-verify to force a fresh token; the framework invalidates tokens when credential signatures change.

## Module packages

- Manage packages in `Settings -> Module Packages`:
  - Install from a JSON manifest (see `ModulePackageTemplates/` for examples).
  - Remove custom packages as needed; bundled defaults are restored on bootstrap if missing.
  - Duplicate package IDs and unsupported module types are rejected during install.
- Persisted state lives at `Application Support/JamfDashboard/installed-module-packages.json`.

## Diagnostics and logging

- Diagnostics are available from modules and Settings:
  - Toggle **Error Logs** and use **Get Logs** to fetch or request logs from Jamf.
  - Copy results when sensitive values are displayed (for example unlock tokens or LAPS passwords).
- Persistent NDJSON error log: `Documents/JamfDashboardDiagnostics/jamf-dashboard-errors.ndjson`.
- Diagnostics exports: `Documents/JamfDashboardDiagnostics/`.
- The in-memory diagnostics stream is bounded; export logs before quitting when investigating an issue.

## Data locations quick reference

- Credentials: Keychain service `com.jamfdashboard.app`.
- Search profiles:
  - `Application Support/JamfDashboard/computer-search-profiles.json`
  - `Application Support/JamfDashboard/mobile-device-search-profiles.json`
- Module packages: `Application Support/JamfDashboard/installed-module-packages.json`
- Diagnostics exports and error log: `Documents/JamfDashboardDiagnostics/`

## Common issues

- `401/403 INVALID_PRIVILEGE`: the Jamf role lacks the required permission; rerun with a role that can read inventory or queue MDM commands.
- Missing modules after cleanup: relaunch to allow bundled defaults to re-apply or reinstall a manifest from `ModulePackageTemplates/`.
- Scanner unavailable: camera permissions are handled in the shared scanner sheet; ensure camera is available/authorized on the device.
- Legacy Jamf shapes: modules automatically retry with compatibility fallbacks; check diagnostics if responses omit expected sections or fields.

## Collecting support data

1. Reproduce the issue.
2. Open Diagnostics (module view or Settings), enable **Error Logs**, and select **Get Logs**.
3. Export the diagnostics bundle from `Documents/JamfDashboardDiagnostics/` and include recent timestamps when filing a report.
