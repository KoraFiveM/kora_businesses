---
title: "Mechanic / bodyshop"
sidebar_position: 6
---


# Mechanic / bodyshop

## Server

Vehicle repair (full garage repair, roadside stabilisation) and cosmetics (respray, bumpers), gated by job name/type and, for full repairs and optionally cosmetics, a configured garage radius. No payment logic exists in this job — pricing, if any, is left to whatever other resource manages the mechanic business, or to the optional `consume` item costs.

Namespace: `Mechanic / kora_businesses:mechanic:*` · Source: `jobs/mechanic/server.lua, jobs/mechanic/shared.lua`

### How it works

A two-step permit pattern: `kora_businesses:mechanic:permit` authorises an action and returns a permit id; the client's progress bar is purely presentational (a cancel there does not refund or reset anything server-side since nothing was charged yet); `kora_businesses:server:serviceCompleted` redeems the permit and re-validates everything from scratch before applying the result.

### Service flow

1. **Permit** — Client targets a vehicle and action; server checks role/zone and issues a short-lived permit.
2. **Progress bar** — Client plays a duration based on the action (`Mechanic.fullRepair.duration` etc.); cancelling here simply aborts, nothing was spent yet.
3. **Redeem** — Client sends the permit id and payload back; server re-validates, optionally consumes an item, and tells the client to apply the visible result.

### Terms used on this page

| Term | Meaning |
| --- | --- |
| Automotive job | Job name equal to `Mechanic.roles.fullRepairJob` (`mechanic`) or job `type` equal to `Mechanic.roles.automotiveType` (`automotive`). Can perform roadside repairs; full repairs additionally require not being in `Mechanic.roles.roadsideJobs`. |
| Bodyshop job | Job name in `Mechanic.roles.bodyshopJobs` or job `type` in `Mechanic.roles.bodyshopTypes` (both default to just `bodyshop`). Gates paint and bumpers. |

### Functions

One callback, one net event.

#### `Kora.callback.register('kora_businesses:mechanic:permit', fn, { rateLimit = Mechanic.interaction.permitRateLimit })`

Issues a short-lived, single-use permit for one service action on one vehicle, after validating role and (for a full repair) garage proximity.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `action` | string | One of `fullRepair`, `roadsideRepair`, `paint`, `bumpers`. |
| `netId` | number | Network id of the target vehicle; resolved and distance-checked via `Kora.world.resolveNetworkEntity` (max `Mechanic.interaction.distance`, 3.0 m). |

**Returns**

- **`true, permitId` on success.**
- **`false, message` if the vehicle cannot be resolved or the role/zone checks in `canPerform` fail.**

**Example**

```lua
local ok, permitId = Kora.callback.trigger('kora_businesses:mechanic:permit', 'fullRepair', netId)
```

**Representative console output**

```text
Permits expire after `Mechanic.interaction.permitLifetime` (45000 ms) and a background sweep (every 60 s) purges expired ones; `playerDropped` purges a disconnecting player's permits immediately.
```

#### `RegisterNetEvent('kora_businesses:server:serviceCompleted', fn)`

Net event the client fires after its progress bar finishes, redeeming the permit and applying the service.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `permitId` | string | From `kora_businesses:mechanic:permit`. |
| `payload` | table \| nil | Action-specific: `{ primary, secondary }` for paint, `{ front, rear }` for bumpers, empty/nil for the two repair actions. |

**Returns**

- **No return value; the server replies by triggering `kora_businesses:client:serviceApplied` on success, or a notification on failure.**

**Example**

```lua
TriggerServerEvent('kora_businesses:server:serviceCompleted', permitId, { primary = 12, secondary = 88 })
```

**Representative console output**

```text
The permit is deleted the instant it is looked up, even if later validation fails, so a permit can only ever be redeemed once. Role, vehicle and payload are all re-validated here independently of the earlier permit check.
```

### Limits and related APIs

No money or item cost by default (`consume = nil` on all three service groups) — add your own item costs via `Mechanic.fullRepair.consume`/`roadsideRepair.consume`/`cosmetics.consume` (`{ item, amount }`) if you want this job to cost anything.

### Related guides

- [Job toggles and boot](./job-toggles.md)

## Client

The `qb-target` global vehicle options (full repair, roadside stabilisation, respray, bumpers), the respray/bumper input dialogs, and an independent passive vehicle-wear/tyre-burst/limp-mode simulation that runs for any driver of any (non-excluded) vehicle regardless of job.

Namespace: `Mechanic / kora_businesses:mechanic:*` · Source: `jobs/mechanic/client.lua, jobs/mechanic/shared.lua`

### How it works

`Mechanic.damage` wear only runs while the local player is in the driver seat of an eligible vehicle class; it reads and writes native vehicle health directly, so it coexists with ordinary GTA collision damage rather than replacing it. `distanceWear` is opt-in and off by default; `collision` wear (extra damage beyond native collision) is on by default.

### Functions

No callbacks of its own beyond triggering the server's permit flow; registers options on `exports['qb-target']:AddGlobalVehicle`.

### Limits and related APIs

Passive wear, tyre bursts and limp mode are purely client-local effects on native vehicle health — they are not synced, persisted or re-validated server-side.

### Related guides

- [Job toggles and boot](./job-toggles.md)
