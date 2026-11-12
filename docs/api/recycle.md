---
title: "Recycling centre"
sidebar_position: 7
---


# Recycling centre

## Server

No job restriction: clocking in and working the warehouse is open to any player. A per-player pending-pickup authorization stands in for a server-held item while the box is carried; hand-in grants random crafting materials, and a separate sell flow cashes materials back in.

Namespace: `Recycle / kora_businesses:recycle:*` · Source: `jobs/recycle/server.lua, jobs/recycle/shared.lua`

### How it works

`Stock` (per-material cap, 3000 each) only exists when `Recycle.LimitedMaterials` is true; `Sales` (per-material price, 2 each) only exists when `Recycle.SellMaterials` is true. `ownedAmount` sums every inventory stack of an item rather than trusting a single stack, so split stacks are still sellable in one request.

### Functions

One callback (price list, pickup), two net events (get item, sell).

#### `Kora.callback.register('kora_businesses:recycle:getPriceList', fn)`

Returns the current sell price table if the player is near the sell ped.

**Parameters**



**Returns**

- **`Sales` table (`{ [material] = pricePerUnit }`) or `false` if too far or `Recycle.SellMaterials` is off.**

**Example**

```lua
local prices = Kora.callback.trigger('kora_businesses:recycle:getPriceList')
```

**Representative console output**

```text
All eight materials are priced at 2 by default.
```

#### `Kora.callback.register('kora_businesses:recycle:pickupPackage', fn)`

Authorises carrying a box from one of `Recycle.PickupLocations`.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `index` | number | Index into `Recycle.PickupLocations`; must be the player's current highlighted pallet and within 3 m. |

**Returns**

- **`{ networked = boolean }` on success, `false` if the player already has a live (unexpired) pickup, is too far, or the index is invalid.**

**Example**

```lua
local grant = Kora.callback.trigger('kora_businesses:recycle:pickupPackage', packageCoords)
```

**Representative console output**

```text
An authorization expires after `Recycle.PendingPickupTimeout` (600000 ms / 10 min) so a lost/crashed client can pick up again without a stuck server lock. `networked` tells the client whether it may spawn a networked carry prop (refused under `sv_entityLockdown "strict"`).
```

#### `RegisterNetEvent('kora_businesses:recycle:getItem', fn)`

Redeems a carried box for random recyclable materials at a hand-in location.

**Parameters**



**Returns**

- **No return value; items are added directly via `exports.kora_inventory:addItem`.**

**Example**

```lua
TriggerServerEvent('kora_businesses:recycle:getItem')
```

**Representative console output**

```text
Requires an unexpired pickup authorization not already cooling down (`coolDown`, defaults to `Recycle.DeliveryActionDuration`) and proximity to `Recycle.DropLocation`, the configured `HandInZone`, or the sell ped (if `Recycle.HandInAtSellPed`). Grants 1–5 stacks of random materials (1–5 units each) plus a `Recycle.LuckyItemChance`% chance (20% default) of one `cryptostick`. Consumed from the shared stock pool when `Recycle.LimitedMaterials` is true.
```

#### `RegisterNetEvent('kora_businesses:recycle:sellItem', fn)`

Sells owned material to the recycle centre.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `item` | string | Material key, must exist in `Sales`. |
| `amount` | number | Positive integer; clamped or rejected above `Recycle.MaxSellPerRequest` (500) per `Recycle.SellOverAmount`. |

**Returns**

- **No return value; cash and inventory are adjusted directly.**

**Example**

```lua
TriggerServerEvent('kora_businesses:recycle:sellItem', 'metalscrap', 25)
```

**Representative console output**

```text
Requires proximity to `Recycle.SellPed` (5 m) and that the player owns at least 1 of the item across any inventory stack (`exports.kora_core:getItemsByName`, falling back to `getItemByName`). Pays `Sales[item] * amount` as cash and restocks the shared pool if limited.
```

### Limits and related APIs

`pendingPackages` and `lastCollection` are purely in-memory per source; both are cleared on `playerDropped` and `QBCore:Server:OnPlayerUnload`. There is no export reading current stock or sales levels for other resources.

### Related guides

- [Job toggles and boot](./job-toggles.md)

## Client

Warehouse enter/exit fade, duty toggle, the carried-box prop/animation (with a networked-prop fallback for strict entity lockdown servers), pallet highlighting, and a separate NUI app (`sales.lua`) for selling materials at the drop-off ped.

Namespace: `Recycle / kora_businesses:recycle:*` · Source: `jobs/recycle/client.lua, jobs/recycle/sales.lua, jobs/recycle/shared.lua`

### How it works

Carrying a box is interrupted (dropped, authorization cancelled) by death, a ped swap, entering a vehicle, or the resource stopping — handled through `Kora.cache.onChange` listeners rather than a polling loop. `sales.lua` exposes `RecycleClient.canHandIn()`/`handIn()` so the sell ped can also offer "Hand In Package" without duplicating the hand-in logic from `client.lua`.

### Functions

No exports; two net events triggered (`getItem`, `sellItem`) and one callback (`getPriceList`, `pickupPackage`).

### Limits and related APIs

The NUI sell app re-fetches the price list and owned counts after every sale rather than trusting a locally cached total, to stay correct if the inventory sync lags.

### Related guides

- [Job toggles and boot](./job-toggles.md)
