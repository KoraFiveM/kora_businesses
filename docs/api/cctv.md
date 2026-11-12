---
title: "CCTV engineer"
sidebar_position: 3
---


# CCTV engineer

## Server

Emergency CCTV call-outs for residential and business customers, serviced by on-duty `cctv` engineers, plus two server-authorised minigames (hacking and repair checks) and the schema for two MySQL tables.

Namespace: `Cctv / kora_businesses:cctv:*` · Source: `jobs/cctv/server.lua, jobs/cctv/shared.lua`

### How it works

`playerJob(src)` is the gate for every engineer-only action: job name must equal `Cctv.job` (`cctv`), on-duty when `Cctv.requireOnDuty`, and grade at least `Cctv.minimumEngineerGrade`. Call-outs live only in memory (`callouts` table, `nextCalloutId` counter) — they do not survive a restart. `kora_businesses_cctv_callouts` and `kora_businesses_cctv_systems` are created with `Kora.sql.ensureTables` once `Kora.sql.ready(60000)` resolves; CCTV persistence is skipped with a console warning if SQL is never ready.

### Call-out lifecycle

1. **Customer requests** — `requestCallout` verifies the customer, checks an engineer is online if required, and charges the call-out fee up front.
2. **Engineer accepts** — `acceptCallout` assigns the call-out to the accepting engineer (status `open`/`pending` → `accepted`).
3. **Engineer completes** — `completeCallout` charges the repair price and pays the engineer's company, refunding the customer if the company credit fails.
4. **Or declines** — `declineCallout` returns an accepted call-out to `open` with no engineer, available for another to accept.

### Terms used on this page

| Term | Meaning |
| --- | --- |
| Customer account | Either `{ type = 'residential', citizenid }` (billed from the player's own bank) or `{ type = 'business', business }` (billed from that job's `kora_banking` account). |
| System security | `systemSecurity(targetId)` reads `security_level + intrusion_level` from `kora_businesses_cctv_systems`, clamped 1–10, and feeds both minigames' difficulty. |

### Functions

Callbacks (all `Kora.callback.register`) plus one export.

#### `Kora.callback.register('kora_businesses:cctv:requestCallout', fn, { rateLimit = { max = 3, window = 60000 } })`

A customer (residential or business) requests an emergency CCTV call-out.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `data.issue` | string | Required: `camera` or `nvr`. |
| `data.customerType` | string | `residential` (own home, verified by citizen ID) or `business` (own job's business, verified by job name). |
| `data.cameraId / data.nvrId / data.coords` | string / string / table | Passed straight into the stored call-out; not otherwise validated. |

**Returns**

- **`true, callout` on success.**
- **`false, message` when call-outs are disabled, the issue is invalid, the customer cannot be verified, no engineer is online (when `Cctv.callouts.requireEngineerOnline`), the charge amount is invalid, or the customer cannot afford it.**

**Example**

```lua
local ok, result = Kora.callback.trigger('kora_businesses:cctv:requestCallout', { issue = 'camera', customerType = 'business' })
```

**Representative console output**

```text
Debits the customer (player bank for residential, the named job's bank account via `exports.kora_banking:RemoveMoney` for business) before the call-out is created. Rate limited to 3 requests per 60 seconds per player.
```

#### `Kora.callback.register('kora_businesses:cctv:acceptCallout', fn) (and the completeCallout/declineCallout siblings)`

On-duty CCTV engineer actions on an open call-out.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | string | The call-out id (e.g. `cctv-<unixtime>-<counter>`). |

**Returns**

- **`true, callout` on success.**
- **`false, message` when the caller is not an eligible on-duty engineer, or the call-out is not in the expected status.**

**Example**

```lua
local ok = Kora.callback.trigger('kora_businesses:cctv:acceptCallout', calloutId)
```

**Representative console output**

```text
`completeCallout` charges the repair price to the original customer and credits `charge + repairPrice` to the `cctv` job's bank account (`exports.kora_banking:AddMoney`); a failed company credit refunds the customer's repair charge.
```

#### `Kora.callback.register('kora_businesses:cctv:laptopData', fn)`

Reads for the engineer laptop app: all call-outs, plus installed systems for the engineer's own company (`kora_businesses_cctv_systems` where `installer_business = Cctv.job`).

**Parameters**



**Returns**

- **`{ systems, callouts, company }` for an eligible on-duty engineer.**
- **`nil, message` otherwise.**

**Example**

```lua
local data, err = Kora.callback.trigger('kora_businesses:cctv:laptopData')
```

**Representative console output**

```text
Used to populate the NUI app's two tabs (installed systems, call-outs).
```

#### `Kora.callback.register('kora_businesses:cctv:beginHack', fn)`

Server-authorised minigame pair for `/cctvhack`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `data.targetId` | string | CCTV system id, max 80 characters. |

**Returns**

- **`beginHack`: `true, { authorization, bucket }` or `false, message`.**
- **`finishHack`: `true, { targetId }` or `false, message` (expired session or failed proof).**

**Example**

```lua
local started, data = Kora.callback.trigger('kora_businesses:cctv:beginHack', { targetId = id })
```

**Representative console output**

```text
Moves the player to a private routing bucket (`Cctv.hacking.privateBucketBase + src`) for the duration of the hack, restoring the previous bucket on finish, timeout (10 s poll) or `playerDropped`. A successful hack raises `intrusion_level` on the target system row.
```

#### `Kora.callback.register('kora_businesses:cctv:beginRepairCheck', fn)`

Server-authorised minigame pair for `/cctvrepair`, restricted to an eligible on-duty engineer.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `data.targetId` | string | CCTV system id. |

**Returns**

- **`beginRepairCheck`: `true, { authorization }` or `false, message`.**
- **`finishRepairCheck`: `true, { targetId }` or `false, message`.**

**Example**

```lua
local started, data = Kora.callback.trigger('kora_businesses:cctv:beginRepairCheck', { targetId = id })
```

**Representative console output**

```text
Unlike `beginHack`, this does not move the player to a private bucket.
```

#### `exports.kora_businesses:getCctvCallouts()`

Export: returns the live in-memory call-out table.

**Parameters**



**Returns**

- **`table`** — keyed by call-out id, same shape as the callback results above.

**Example**

```lua
local callouts = exports.kora_businesses:getCctvCallouts()
```

**Representative console output**

```text
In-memory only: call-outs are lost on resource restart. No equivalent export exists to read `kora_businesses_cctv_systems`; query that table directly with `Kora.sql` if you need it from another resource.
```

### Limits and related APIs

No export reaches `kora_businesses_cctv_systems` rows (installing a system, i.e. inserting into that table, is not implemented in this resource — some other business/installer feature is expected to do it). Call-out state is not persisted across a restart even though the table exists for it.

### Related guides

- [Job toggles and boot](./job-toggles.md)

## Client

No client-side authority at all: the laptop item event and the two commands only call server callbacks and render a `kora_lib` NUI app or run `Kora.minigames.play`.

Namespace: `Cctv / kora_businesses:cctv:*` · Source: `jobs/cctv/client.lua`

### How it works

`openLaptop` guards re-entry with a local `active` flag while it awaits `laptopData`. The hack/repair commands each spawn their own `CreateThread` so multiple invocations do not block the main thread, but the server itself refuses a second concurrent hack or repair check per player.

### Functions

Net event and commands.

#### `RegisterNetEvent('kora_businesses:cctv:openLaptop', openLaptop)`

Server-triggered net event that opens the engineer laptop NUI app after `exports.kora_inventory:CreateUsableItem(Cctv.laptopItem, ...)` authorises use of the item.

**Parameters**



**Returns**

- **No return value.**

**Example**

```lua
-- Fired server-side when the player uses the cctv_laptop item
```

**Representative console output**

```text
Builds the app's `systems` and `callouts` lists from `kora_businesses:cctv:laptopData` each time it opens; it is not kept live after that.
```

#### `RegisterCommand('cctvhack', fn, false)`

Client commands documented in full on the Commands page.

**Parameters**



**Returns**



### Limits and related APIs

A modified client could call `kora_businesses:cctv:beginHack`/`finishHack` directly, but the server re-validates eligibility, session expiry and the submitted proof every time.

### Related guides

- [Job toggles and boot](./job-toggles.md)
