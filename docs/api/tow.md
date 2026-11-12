---
title: "Tow truck driver"
sidebar_position: 8
---


# Tow truck driver

## Server

Repeated single-vehicle recovery trips from the tow yard to one of 40 scattered `towspots`, paid per vehicle dropped off when the flatbed is returned.

Namespace: `Tow / qb-tow:server:*` · Source: `jobs/tow/server.lua, jobs/tow/shared.lua`

### How it works

All three main callbacks use Lua `assert` for their precondition failures rather than returning `false, reason` — a failed precondition therefore errors inside the callback (kora_lib's callback wrapper is relied on to turn that into a safe `false`/error to the client; this was not independently re-verified against kora_lib here).

### Session lifecycle

1. **Take out** — `TakeOutVehicle` grants flatbed keys and a first recovery location.
2. **Pick up / drop off** — `pickUp` at the recovery site, then `DropOff` at the yard; repeats, rolling a new location each drop-off.
3. **Return** — `ReturnVehicle` pays for everything dropped off so far and ends the session.

### Functions

Four callbacks.

#### `Kora.callback.register('qb-tow:server:TakeOutVehicle', fn)`

Starts a tow session: gives flatbed keys and rolls the first pickup location.

**Parameters**



**Returns**

- **`towDrivers[source]` table (`{ location, droppedOff = 0, hasPickedUp = false }`) on success; the handler `assert`s (errors, does not return false) if the player is too far, already has a session, or job data is missing, and silently returns nothing if `job.name ~= 'tow'`.**

**Example**

```lua
local session = Kora.callback.trigger('qb-tow:server:TakeOutVehicle')
```

**Representative console output**

```text
Does not check `job.onduty` — only `job.name == 'tow'`. Calls `exports.kora_vehiclekeys:giveKeys(source, 'TOW', true)` unconditionally on success.
```

#### `Kora.callback.register('qb-tow:server:pickUp', fn)`

Marks the current recovery vehicle picked up (client then attaches it), and later dropped off at the yard.

**Parameters**



**Returns**

- **`true`/`false` (pickUp); the session table (DropOff)** — both `assert` on missing session/distance rather than returning false for those cases.

**Example**

```lua
local ok = Kora.callback.trigger('qb-tow:server:pickUp')
```

**Representative console output**

```text
`DropOff` increments `droppedOff`, clears `hasPickedUp`, and immediately rolls a new `location` for the next vehicle — the client is expected to call `pickUp` again at the new location before attaching another vehicle.
```

#### `Kora.callback.register('qb-tow:server:ReturnVehicle', fn)`

Ends the tow session: pays for every vehicle dropped off and revokes flatbed keys.

**Parameters**



**Returns**

- **`true` on success; `assert`s if there is no session or the player is not at the yard.**

**Example**

```lua
local ok = Kora.callback.trigger('qb-tow:server:ReturnVehicle')
```

**Representative console output**

```text
Pays `droppedOff * Tow.payPerVehicle` ($100/vehicle) via `exports.kora_core:addMoney(source, 'bank', ...)` only if `droppedOff > 0`, then always clears the session and calls `exports.kora_vehiclekeys:removeKeys(source, 'TOW')`.
```

### Limits and related APIs

No on-duty check on `TakeOutVehicle`, only job name. The client's `Detach Vehicle` option calls `qb-tow:server:CheckDistance`, which this file does not register — see the How To Use notes for this job.

### Related guides

- [Job toggles and boot](./job-toggles.md)

## Client

Flatbed spawn/return zone at the yard, the recovery vehicle's attach/place targets, and map blips/waypoints for the current recovery vehicle and the yard itself.

Namespace: `Tow / qb-tow:server:*` · Source: `jobs/tow/client.lua`

### How it works

Uses `Kora.raycast.getCoords` to let the player choose where to place a detached recovery vehicle, then asks the server for the next drop-off/pickup pair and respawns the pickup marker.

### Functions

No exports; triggers the server callbacks above, plus a `qb-tow:server:CheckDistance` call that has no server handler (see server side note).

### Limits and related APIs

The 15.5-second delayed deletion of a replaced pickup vehicle (`reset()`) is purely cosmetic cleanup and has no server-side counterpart.

### Related guides

- [Job toggles and boot](./job-toggles.md)
