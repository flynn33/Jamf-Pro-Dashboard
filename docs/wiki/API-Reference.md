# API Reference

This page catalogs the Jamf Pro Modern API endpoints used by Jamf Dashboard, grouped by module. All requests are made through `JamfAPIGateway` using Bearer token authentication.

For the authoritative Jamf Pro API reference, see the [Jamf Developer Portal](https://developer.jamf.com/jamf-pro/reference/).

---

## Authentication

Authentication is handled by `JamfAuthenticationService` before any module call is made.

### API Client (OAuth 2.0 client credentials)

```
POST /api/v1/oauth/token
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials
&client_id=<client_id>
&client_secret=<client_secret>
```

Response fields used: `access_token` (string), `expires_in` (seconds).

### Username & Password (Basic auth token exchange)

```
POST /api/v1/auth/token
Authorization: Basic <base64(username:password)>
```

Response fields used: `token` (string), `expires` (ISO-8601 string or Unix timestamp).

---

## Computer Search

### Search computer inventory

Primary endpoint (Jamf Pro 11.23+):

```
GET /api/v3/computers-inventory
```

Fallback (Jamf Pro 10.x – 11.22):

```
GET /api/v2/computers-inventory
GET /api/v1/computers-inventory   (deprecated, used only for oldest tenants)
```

Common query parameters: `page`, `page-size`, `section`, `filter` (RSQL), `sort`.

### Get computer detail

```
GET /api/v3/computers-inventory-detail/{id}
```

---

## Mobile Device Search

### Search mobile device inventory

```
GET /api/v2/mobile-devices/detail
```

Common query parameters: `page`, `page-size`, `section`, `filter` (RSQL), `sort`.

### Get mobile device detail

```
GET /api/v2/mobile-devices/{id}/detail
```

### Pre-stage enrichment

```
GET /api/v3/mobile-device-prestages
GET /api/v3/mobile-device-prestages/{id}/scope
```

---

## Support Technician

### Computer inventory

Same as Computer Search (see above).

### Mobile device inventory

Same as Mobile Device Search (see above).

### MDM commands

Queue an MDM command for a computer or mobile device:

```
POST /api/v2/mdm/commands
Content-Type: application/json

{
  "clientData": [
    { "managementId": "<managementId>", "clientType": "COMPUTER" }
  ],
  "commandData": {
    "commandType": "<COMMAND_TYPE>"
  }
}
```

Common `commandType` values:

| Command | Target |
|---|---|
| `RESTART_DEVICE` | Computer, mobile |
| `UPDATE_INVENTORY` | Computer, mobile |
| `INSTALLED_APPLICATION_LIST` | Computer, mobile |
| `ERASE_DEVICE` | Mobile |
| `DEVICE_LOCK` | Mobile |
| `UNLOCK_DEVICE` | Mobile |
| `SETTINGS` | Computer, mobile |

### Computer management actions

Erase a computer:

```
POST /api/v1/computer-inventory/{id}/erase
```

Remove MDM profile:

```
POST /api/v1/computer-inventory/{id}/remove-mdm-profile
```

### Mobile device management actions

Unmanage a mobile device:

```
POST /api/v2/mobile-devices/{id}/unmanage
```

Update OS:

```
POST /api/v2/mdm/commands
commandType: SETTINGS  (with OS update payload)
```

### Recovery and security secrets (computer)

Get FileVault recovery key:

```
GET /api/v3/computers-inventory/{id}/filevault
```

Get recovery lock password:

```
GET /api/v3/computers-inventory/{id}/view-recovery-lock-password
```

Get device lock PIN:

```
GET /api/v3/computers-inventory/{id}/view-device-lock-pin
```

### LAPS (Local Admin Password Solution)

List LAPS-capable accounts:

```
GET /api/v2/local-admin-password/{clientManagementId}/accounts
```

View current local admin password:

```
GET /api/v2/local-admin-password/{clientManagementId}/account/{username}/password
```

Rotate (set) local admin password:

```
PUT /api/v2/local-admin-password/{clientManagementId}/set-password
```

### Mobile device unlock token

The unlock token is returned as part of the mobile device detail response:

```
GET /api/v2/mobile-devices/{id}/detail
```

The `unlockToken` field in the response contains the value when the Jamf role permits access.

---

## Prestage Director

### List computer prestages

```
GET /api/v3/computer-prestages
```

### Get computer prestage scope

```
GET /api/v3/computer-prestages/{id}/scope
```

### Update computer prestage scope

```
PUT /api/v3/computer-prestages/{id}/scope
```

### List mobile device prestages

```
GET /api/v3/mobile-device-prestages
```

### Get mobile device prestage scope

```
GET /api/v3/mobile-device-prestages/{id}/scope
```

### Update mobile device prestage scope

```
PUT /api/v3/mobile-device-prestages/{id}/scope
```

---

## Version notes

- Endpoints prefixed `/api/v3/` for computer inventory are preferred for Jamf Pro 11.23+.
- The `/api/v2/computers-inventory` and `/api/v2/computers-inventory-detail` routes are deprecated (announced 2025-11-06); modules fall back to them only for older tenants.
- The `/api/v1/` computer inventory routes are deprecated (2025-06-30) and used only as a last resort.
- `POST /api/v2/mdm/commands` is the preferred command queue endpoint. `POST /api/v1/mdm/commands` is used as a fallback.

## Privilege requirements summary

| Capability | API role privilege |
|---|---|
| Read computer inventory | Read Computer Inventory |
| Read mobile device inventory | Read Mobile Devices |
| Read pre-stage profiles | Read Computer Prestage Enrollments / Read Mobile Device Prestage Enrollments |
| Update pre-stage scope | Update Computer Prestage Enrollments / Update Mobile Device Prestage Enrollments |
| Queue MDM commands | Send MDM Commands |
| Erase computer | Erase Device |
| Remove MDM profile | Remove MDM Profile |
| Unmanage mobile device | Unmanage Devices |
| View disk encryption recovery key | View Disk Encryption Recovery Key |
| View LAPS password | View Local Admin Password |
| Rotate LAPS password | Set Local Admin Password |

A `403 INVALID_PRIVILEGE` response from Jamf Pro means the API role is missing the required privilege for that specific action. The app logs this to diagnostics and degrades gracefully without crashing.
