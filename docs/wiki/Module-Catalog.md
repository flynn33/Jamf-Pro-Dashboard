# Module Catalog

## Module contract

All modules conform to `JamfModule` and render their root view via `makeRootView(context:)`, receiving gateway, credentials, and diagnostics services through `ModuleContext`.

## Computer Search

- Jamf computer inventory lookup with reusable field profiles.
- Profile operations: save, load, delete.
- Endpoint/query fallbacks handle Jamf tenants with mixed inventory schemas or privilege restrictions.
- Uses shared scanner sheet for barcode/QR entry where available.

## Mobile Device Search

- Mobile inventory search with reusable field profiles.
- Section/wildcard fallback behavior for tenants that restrict certain section parameters.
- Pre-stage enrichment with caching and compatibility fallbacks when responses are incomplete.
- Search profiles can be saved/loaded/removed from the module UI.

## Support Technician

- Unified search by username, serial number, or device name across computers and mobile devices.
- Device detail pane prioritizes identity and inventory signals, with shortcuts to manager views (applications, certificates, accounts, configuration profiles, group membership, services).
- Management actions include install/update/reinstall/remove app flows, configuration/profile actions, group membership changes, account resets, OS update, restart/shutdown, erase/unmanage, and service opens.
- Sensitive actions require confirmations; destructive remove-management/erase flows require typed `Remove`.
- Diagnostics view adds graphical indicators, log controls (toggle, **Get Logs**, copy), and manager shortcuts.
- Unlock token reveal/copy and local admin password (LAPS) flows are supported when Jamf privileges allow.

## Prestage Director

- Lists pre-stage enrollment profiles with scoped devices.
- Multi-select move/remove workflows with progress tracking and rollback attempts on failed move operations.
- Designed to tolerate long-running Jamf operations with clearer status/error reporting.
