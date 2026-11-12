---
title: "Taxi driver"
sidebar_position: 9
---


# Taxi driver

## Server

Single-passenger fares between random pickup/drop-off pairs, paid cash by straight-line distance. `Taxi` additionally self-registers its own fields with kora_lib's config editor (`Kora.config.adopt`), independent of the generic `businesses.config.local.lua` mechanism described in Installation.

Namespace: `Taxi / qb-taxi:*` · Source: `jobs/taxi/server.lua, jobs/taxi/shared.lua`

### How it works

`currentTaxis[source]` tracks one in-progress fare per player: the rolled pickup/drop-off, the precomputed distance, and whether pickup has been completed. Both `pickup` and `dropOff` require the player within 5 m of the relevant recorded point, and use `assert` for failures (same pattern as the tow job).

### Config fields registered with kora_lib (taxi/shared.lua)

Each is wrapped with `Kora.config.string/boolean/vector3/list` when `Kora.config.adopt` is available, then the whole `Taxi` table is replaced by `config.adopt(Taxi)`'s return value — so these are live, editor-visible settings, not just plain Lua constants.

| Option | Type | Description |
| --- | --- | --- |
| `jobRequired` | string | Default `taxi`. Labelled "unused" in its own kora_lib config description: this is the only place the value is read (the server's job-name comparison), and the description warns changing it does not otherwise restrict access. |
| `Management` | boolean | Default false. Labelled "unused": trips always pay the driver cash directly regardless of this value; there is no society/company payout path in this job's code. |
| `parkLocation` | vector3 | Taxi depot: where the spawn/return interaction and the spawned taxi appear. |
| `PickUp` | vector4[] | Random passenger pickup points (16 by default). Keep at least one entry. |
| `DropOffs` | vector4[] | Random passenger destinations (23 by default). Trip distance between the chosen pickup and drop-off also sets driver pay. |
| `Peds` | string[] | Pool of ped models randomly chosen for the passenger NPC. |

### Functions

One callback, two net events.

#### `Kora.callback.register('qb-taxi:getPickupLocation', fn)`

Starts a new fare: picks a random pickup/drop-off pair and records the trip distance for pay.

**Parameters**



**Returns**

- **`{ pickup, dropoff }` for a player whose job is `Taxi.jobRequired`; `nil` otherwise.**

**Example**

```lua
local trip = Kora.callback.trigger('qb-taxi:getPickupLocation')
```

**Representative console output**

```text
Distance is computed once with `Kora.util.vecDistance(pickup, dropoff)` and reused at drop-off to compute pay, so it cannot be inflated by the route the driver actually takes.
```

#### `RegisterNetEvent('qb-taxi:pickup', fn)`

Marks the current fare's two legs complete and, on drop-off, pays the driver.

**Parameters**



**Returns**

- **No return value; `assert`s (errors) if the player is not on the taxi job, has no current fare, is not within 5 m of the recorded point, or (for drop-off) has not yet completed pickup.**

**Example**

```lua
TriggerServerEvent('qb-taxi:pickup')
-- ...later...
TriggerServerEvent('qb-taxi:dropOff')
```

**Representative console output**

```text
`dropOff` pays `floor(distance * 0.2)` cash via `exports.kora_core:addMoney`, clears the fare, and triggers `qb-taxi:client:spawnPickup` back on the same client to offer the next fare.
```

### Limits and related APIs

No society/company payout path exists despite the `Management` field's name — read every trip as driver-paid cash only. Pay has no configurable rate or minimum/maximum beyond the fixed `distance * 0.2` formula in `jobs/taxi/server.lua`.

### Related guides

- [Job toggles and boot](./job-toggles.md)

## Client

Spawn/return interaction at the depot, the passenger NPC and its enter/leave animation, and the pickup/drop-off trigger zones (`Kora.zones.box`).

Namespace: `Taxi / qb-taxi:*` · Source: `jobs/taxi/client.lua`

### How it works

`qb-taxi:client:spawnPickup` is only acted on when it targets the local player specifically (`source ~= 65535` guard, i.e. only a direct `TriggerClientEvent` to this client, never a broadcast) — it is triggered by the server at the end of `dropOff` to offer the next fare without the player needing to return to the depot.

### Functions

No exports; triggers the server callback/events above.

### Limits and related APIs

Spawning the taxi vehicle itself has no job check client-side; only requesting an actual fare (`qb-taxi:getPickupLocation`) is job-gated server-side.

### Related guides

- [Job toggles and boot](./job-toggles.md)
