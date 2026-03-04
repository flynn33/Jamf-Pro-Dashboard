# Operations and Troubleshooting

## Credentials lifecycle

- Update credentials at any time from **Settings → Jamf Credentials**.
- Choose the authentication method, fill in the fields, and always run **Verify Connection** before saving.
- The app stores only the fields relevant to the selected auth method; unused fields are cleared on save.
- If you rotate a `client_secret` or change a password, re-enter the new value, verify, and save — the token cache invalidates automatically when the credential signature changes.
- After saving, the framework re-acquires a token on the next API call without requiring a restart.

## Diagnostics and logging

### Viewing diagnostics in the app

- From a Support Technician device detail, open **Diagnostics**.
- Toggle **Error Logs** to show the log section.
- Tap **Get Logs** to fetch recent logs from the device or to request them via MDM.
- Sensitive values (unlock tokens, LAPS passwords) have a clipboard copy button; use it rather than leaving values visible on screen.

### Diagnostics exports

- Open **Diagnostics** from the toolbar and tap **Export JSON** to write a timestamped JSON bundle to `Documents/JamfDashboardDiagnostics/`.
- The in-memory event stream is bounded; export before quitting if you are actively investigating an issue.

### Persistent error log

- `Documents/JamfDashboardDiagnostics/jamf-dashboard-errors.ndjson` — newline-delimited JSON, one `DiagnosticEvent` object per line.
- The log accumulates across sessions and survives app restarts.
- Clear it from the Diagnostics view when it is no longer needed.

### Forsetti runtime logging

- `JamfForsettiLogger` bridges Forsetti's `ForsettiLogger` protocol to `DiagnosticsCenter`.
- Framework-level events (module lifecycle, entitlement checks, boot sequence) appear in the same diagnostics stream as application-level events.

### DiagnosticEvent fields

| Field | Type | Description |
|---|---|---|
| `id` | UUID | Unique event identifier |
| `timestamp` | ISO-8601 date | When the event was recorded |
| `source` | string | Component that raised the event (e.g. `framework.api-gateway`) |
| `category` | string | Event category (e.g. `authentication`, `request`, `decoding`) |
| `severity` | `info` / `warning` / `error` | Severity level |
| `message` | string | Human-readable description |
| `metadata` | `[String: String]` | Additional key-value context |

## Data locations quick reference

| Data | Location |
|---|---|
| Credentials | Keychain, service `com.jamfdashboard.app` |
| Computer search profiles | `Application Support/JamfDashboard/computer-search-profiles.json` |
| Mobile device search profiles | `Application Support/JamfDashboard/mobile-device-search-profiles.json` |
| Diagnostics exports | `Documents/JamfDashboardDiagnostics/` |
| Persistent error log | `Documents/JamfDashboardDiagnostics/jamf-dashboard-errors.ndjson` |

## Common issues

### Authentication and connectivity

| Symptom | Likely cause | Resolution |
|---|---|---|
| Verify Connection fails immediately | Invalid or unreachable server URL | Confirm the URL is correct and reachable from your network or VPN |
| `401` on every action after saving credentials | Token expired or rotated secret | Re-enter credentials, verify, and save |
| `403 INVALID_PRIVILEGE` | Jamf API role lacks required privilege | Add the missing privilege to the API role or switch to a role with broader access |
| Token request returns `400` | `client_id`/`client_secret` incorrect | Verify the API client credentials in Jamf Pro and re-enter them |

### Modules

| Symptom | Likely cause | Resolution |
|---|---|---|
| No modules visible on dashboard | Forsetti runtime boot failed or manifests missing | Check diagnostics for boot events; verify manifest JSONs exist in `Resources/ForsettiManifests/` and are included in the bundle |
| Module fails to activate | Entry point mismatch | Verify the `entryPoint` in the manifest matches the registered factory key in `JamfDashboardBootstrap` |

### Search and inventory

| Symptom | Likely cause | Resolution |
|---|---|---|
| Search returns no results for a known device | Privilege restriction on inventory endpoint | Check diagnostics for `400`/`403` entries; the module retries with fallback queries but a missing privilege may block all paths |
| Pre-stage field missing in Mobile Device Search results | Pre-stage endpoint unavailable or restricted | Expected behavior; the field remains blank and a diagnostic event is logged |
| Legacy Jamf response shape causes missing fields | Older Jamf Pro version | Modules automatically retry with compatibility fallbacks; check diagnostics for detail |

### Scanner

| Symptom | Likely cause | Resolution |
|---|---|---|
| Scanner sheet shows "unavailable" | No camera on device or simulator | Expected; use manual text entry |
| Scanner sheet shows permission prompt each time | Camera permission not granted | Grant camera permission in device Settings |

## Collecting support data

1. Reproduce the issue.
2. Open **Diagnostics** from the toolbar, enable **Error Logs**, and tap **Get Logs**.
3. Export the diagnostics bundle from **Diagnostics → Export JSON**.
4. Retrieve the NDJSON error log from `Documents/JamfDashboardDiagnostics/jamf-dashboard-errors.ndjson`.
5. Include the exported JSON, the NDJSON log, the platform (iOS/macOS), the module name, the device type (computer/mobile), the action performed, and the timestamps when filing a report.

## Suggested bug report format

```
Platform: iOS / macOS
Module: <module name>
Device type: computer / mobile / n/a
Action performed: <what was tapped or entered>
Expected result: <what should have happened>
Actual result: <what actually happened>
Timestamp: <approximate time>
Diagnostics export: <attach the JSON bundle>
Error log snippet: <paste relevant NDJSON lines>
```
