---
title: "Garbage collector"
sidebar_position: 4
---


# Garbage collector

## Server

A randomised multi-stop trash collection route, paid a flat amount per stop on successful return of the truck. All state is in-memory (`onJob`, keyed by player source) and lost on restart or player disconnect.

Namespace: `Garbage / qb-garbagejob:*` · Source: `jobs/garbage/server.lua, jobs/garbage/shared.lua`

### How it works

Every step re-validates distance and route/truck state server-side; the client only decides when to attempt each step and renders the truck/zones/animations. No step other than `returnTruck` touches money.

### Route lifecycle

1. **Spawn** — `spawnTruck` builds the route; `setTruck` binds the client's spawned vehicle to it.
2. **Work each stop** — Alternate `collectBag` and `depositBag` until a stop's bag count is both picked up and deposited, then `completeStop`.
3. **Return** — Once every stop is done, bring the truck back to the depot and call `returnTruck` for payment.

### Functions

Six callbacks.

#### `Kora.callback.register('qb-garbagejob:spawnTruck', fn)`

Starts a new route for an on-job player with no truck out.

**Parameters**



**Returns**

- **`route` table (array of `{ stop, bags }`) on success, `false` if the player already has a route or is not job `garbage`.**

**Example**

```lua
local route = Kora.callback.trigger('qb-garbagejob:spawnTruck')
```

**Representative console output**

```text
Route length is `math.random(Garbage.MinStops, Garbage.MaxStops)` clamped to the number of trashcan locations, with stops shuffled (Fisher–Yates) out of `Garbage.Locations.trashcan`.
```

#### `Kora.callback.register('qb-garbagejob:setTruck', fn)`

Registers the client-spawned truck's network id against the player's route.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `vehicleNet` | number | Required positive network id. |

**Returns**

- **`true` on success, `false` if there is no route, a truck is already registered, the id is invalid, the model does not match `Garbage.Vehicle`, or the vehicle is more than 30 m from the depot ped.**

**Example**

```lua
local ok = Kora.callback.trigger('qb-garbagejob:setTruck', netId)
```

**Representative console output**

```text
On success, wraps `exports.kora_vehiclekeys:giveKeys(source, 'GARBAGE')` in `pcall`.
```

#### `Kora.callback.register('qb-garbagejob:collectBag', fn)`

Per-bag pickup (from a trashcan) and deposit (into the truck) validation.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `stopId` | number | Index into `Garbage.Locations.trashcan` for the current stop (collect), or the current route index (deposit). |

**Returns**

- **`true`/`false`.**

**Example**

```lua
local ok = Kora.callback.trigger('qb-garbagejob:collectBag', stopId)
```

**Representative console output**

```text
Collect requires the player within 4 m of that trashcan and fewer bags picked up than the stop needs. Deposit requires the player within 6 m of their own registered truck and deposited count below both picked-up count and the stop's bag count.
```

#### `Kora.callback.register('qb-garbagejob:completeStop', fn)`

Advances the route once a stop's bags are fully picked up and deposited.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `routeIndex` | number | Must equal the player's current route index. |

**Returns**

- **`true`/`false`.**

**Example**

```lua
local ok = Kora.callback.trigger('qb-garbagejob:completeStop', routeIndex)
```

**Representative console output**

```text
Resets the per-stop picked-up/deposited counters to 0 and increments `routeIndex`.
```

#### `Kora.callback.register('qb-garbagejob:returnTruck', fn)`

Ends the route: pays the driver and deletes the truck.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `vehicleNet` | number | Must match the player's registered truck network id. |

**Returns**

- **`number` (payment, `stops * 50`) on success, `false` if the route is not finished, the truck does not match, or the player/truck are not within `Garbage.ReturnDistance` (10 m) of the depot.**

**Example**

```lua
local paid = Kora.callback.trigger('qb-garbagejob:returnTruck', netId)
```

**Representative console output**

```text
Pays with `exports.kora_core:addMoney(source, 'bank', payment, 'garbage-route')` before deleting the truck entity and clearing job state; a failed payment leaves the job state intact so the player can retry.
```

#### `Kora.callback.register('qb-garbagejob:cancel', fn)`

Deletes the player's truck (if any) and clears their job state without payment. Used on job change and client-detected failures.

**Parameters**



**Returns**

- **`true` always.**

**Example**

```lua
Kora.callback.trigger('qb-garbagejob:cancel')
```

**Representative console output**

```text
Also runs implicitly via `playerDropped` and `onResourceStop` cleanup, which clear the whole `onJob` table.
```

### Limits and related APIs

No job/duty re-check inside the per-bag callbacks beyond the initial `spawnTruck` gate — a job change mid-route is only caught client-side (`QBCore:Client:OnJobUpdate` cancels the route), so a quit-without-cancel player leaves no server-side truck behind only because `playerDropped` clears `onJob` (the truck entity itself is not force-deleted server-side in that handler).

### Related guides

- [Job toggles and boot](./job-toggles.md)

## Client

Depot ped, route blips, trashcan zones, truck target options and the carried-bag prop/animation. Holds no authority: every action the player takes round-trips to the matching server callback before any visible state (bag count, route index) advances.

Namespace: `Garbage / qb-garbagejob:*` · Source: `jobs/garbage/client.lua`

### How it works

Re-registers the trashcan's `kora_target` zone after each pickup purely to refresh its displayed bag count label (labels are fixed at registration time). Listens to `QBCore:Client:OnJobUpdate` to cancel an in-progress route (calls `qb-garbagejob:cancel`, deletes the truck) if the player's job changes away from `garbage`.

### Functions

No callbacks of its own; triggers the server callbacks above.

### Limits and related APIs

A desynced client (for example after a game crash mid-bag-carry) relies on the server's own state, not the client's, to decide what is still valid — but the client does not proactively resync on reconnect beyond what `QBCore:Client:OnPlayerLoaded` draws (the depot blip).

### Related guides

- [Job toggles and boot](./job-toggles.md)
