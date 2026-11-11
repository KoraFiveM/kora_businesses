---
title: Recycle
sidebar_position: 4
---

# Recycle

A recycling warehouse open to every player: clock in, carry packages from pallets to the drop point for random materials, and sell materials to a ped.

Files: `jobs/recycle/shared.lua` (config), `jobs/recycle/client.lua`, `jobs/recycle/sales.lua` (client sell ped and UI), `jobs/recycle/server.lua`. Enabled by `Config.Recycle`. Strings come from `locales/en.lua` (`recycle.*`).

## Usage

1. A **Recycle Center** blip marks `OutsideLocation`. Use **Enter Warehouse** there to fade-teleport to `InsideLocation`; **Exit Warehouse** inside takes you back (and clocks you out).
2. Use **Toggle Duty** at `DutyLocation`. This is a client-side clock-in for the warehouse only; it is not the kora_core job duty and no job is required.
3. While clocked in, one random pallet is outlined (when `DrawPackageLocationBlip` is set). Use **Get Package** on it. The server authorises the pickup if you are within 3 m of that pallet and do not already hold a live authorisation. After the pickup progress bar, a box (`PickupBoxModel`) is attached to your hands in a carry pose.
4. Use **Hand In Package** at the drop zone (`HandInZone`, defaulting to `DropLocation`) or, when `HandInAtSellPed` is set, on the sell ped. After the hand-in progress bar, the server pays out if you are within `HandInDistance` of the drop location, the hand-in zone or the sell ped, and at least `DeliveryActionDuration` ms have passed since the pickup and the previous hand-in.
5. Each hand-in gives 1 to 5 random draws from the material list, each draw giving 1 to 5 of one material, plus a 20% chance of one `cryptostick`. A new pallet is then outlined.

The carried box is dropped and the authorisation released if you die, change ped, enter a vehicle, clock out, leave the warehouse or the resource stops. A pickup authorisation that is never redeemed expires after `PendingPickupTimeout` ms.

### Selling materials

When `SellMaterials` is `true`, a `s_m_m_dockwork_01` ped stands at `SellPed` with a **Sell Materials** option. It opens a compact kora_lib AppShell app listing materials with what you own and the price. Each material with stock has a sell form with an amount field (1 to `min(owned, MaxSellPerRequest)`, default `SellDefaultAmount`). The server checks you are within 5 m of the ped, applies `MaxSellPerRequest` and `SellOverAmount`, removes the items and pays cash.

## Configuration

`Recycle` in `jobs/recycle/shared.lua`.

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `OutsideLocation` | `vector4` | `vector4(55.55, 6472.18, 31.43, 44.0)` | Entrance zone and blip; exit destination. |
| `InsideLocation` | `vector4` | `vector4(1073.0, -3102.49, -39.0, 266.61)` | Exit zone; entrance destination. |
| `DutyLocation` | `vector4` | `vector4(1048.7, -3100.62, -38.2, 88.02)` | Toggle Duty zone. |
| `DropLocation` | `vector4` | `vector4(1048.224, -3097.071, -38.999, 274.810)` | Default hand-in point. |
| `SellMaterials` | boolean | `true` | Spawn the sell ped and allow selling. |
| `SellHideEmpty` | boolean | `true` | Hide materials you own none of; `false` lists them as "You have: 0" without a form. |
| `SellDefaultAmount` | integer | `1` | Pre-filled amount, clamped to 1..owned. |
| `MaxSellPerRequest` | integer | `500` | Maximum per sale, enforced by the server and used as the form maximum. |
| `SellOverAmount` | string | `'clamp'` | When the amount exceeds what is owned or the cap: `'clamp'` sells what is allowed, `'reject'` sells nothing. |
| `LimitedMaterials` | boolean | `true` | Track a server-wide material stock (see below). |
| `SellPed` | `vector4` | `vector4(1049.84, -3094.08, -40.0, 178.84)` | Sell ped position. |
| `DrawPackageLocationBlip` | boolean | `true` | Outline the current pallet. |
| `PickupActionDuration` | number (ms) | `math.random(4000, 6000)` | Pickup progress bar. Evaluated once at load, not per pickup. |
| `DeliveryActionDuration` | number (ms) | `5000` | Hand-in progress bar; also the server cooldown between pickup and hand-in. |
| `PickupAnim` | table or `false` | `{ dict = 'mini@repair', clip = 'fixing_a_ped', flag = 1 }` | Animation during pickup (`Kora.progressbar.start` anim fields). |
| `HandInAnim` | table or `false` | `false` | Optional animation during hand-in. |
| `PickupBoxModel` | string | `'hei_prop_heist_box'` | Carried prop. |
| `CarryPropNetworked` | boolean | `false` | Network the box so others see it. Ignored when `sv_entityLockdown` is `strict`. |
| `CarryPropVerifyDelay` | number (ms) | `1000` | After a networked pickup, check the box still exists and fall back to a local box. |
| `CarryBone` | integer | `60309` | Ped bone (left hand). |
| `CarryOffset` | `vector3` | `vector3(0.025, 0.08, 0.255)` | Attach offset. |
| `CarryRotation` | `vector3` | `vector3(-145.0, 290.0, 0.0)` | Attach rotation. |
| `CarryAnim` | table | `{ dict = 'anim@heists@box_carry@', clip = 'idle', flag = 49 }` | Carry pose; restored after jumps or ragdolls. |
| `HandInZone` | table | `{ coords = nil, size = vector3(4.0, 4.0, 3.0), rotation = 0.0 }` | Hand-in target zone; `coords = nil` uses `DropLocation`. |
| `HandInAtSellPed` | boolean | `true` | Also offer Hand In Package on the sell ped. |
| `HandInDistance` | number | `6.0` | Server distance for a valid hand-in. |
| `PendingPickupTimeout` | number (ms) | `600000` | Expiry of an unredeemed pickup authorisation. |
| `PickupLocations` | list | 21 pallets | Each entry has `model` (index into `WarehouseObjects`, random by default) and `loc` (`vector4`). |
| `WarehouseObjects` | list of strings | 7 `prop_boxpile_*` models | Pallet props. |

## Hard-coded values

Defined in `jobs/recycle/server.lua`:

- Reward materials: `metalscrap`, `plastic`, `copper`, `rubber`, `iron`, `aluminum`, `steel`, `glass`, each 1 to 5 per draw; 1 to 5 draws per package.
- Lucky item: `cryptostick`, 20% chance per package.
- Sell price: `2` cash per unit for every material.
- Stock (when `LimitedMaterials` is set): each material starts at 3000 units server-wide. Handing in removes the rewarded amount from stock; if stock is too low that draw gives nothing. Selling adds the sold amount back. Stock resets on restart.
- Distance checks: 3 m to a pallet for pickup, 5 m to the sell ped for prices and sales.
