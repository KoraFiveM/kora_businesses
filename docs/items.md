---
title: Items
sidebar_position: 8
---

# Items

## Registered by this resource

| Item | Registered by | Details |
| --- | --- | --- |
| `cctv_laptop` | CCTV server, via `Kora.shared.register('items', ...)` if the item does not already exist | Label `CCTV Engineer Laptop`, weight 1500, image `laptop.png`, unique, usable, closes the inventory on use. Using it opens the [engineer laptop](./features/cctv.md#engineer-laptop) for eligible CCTV engineers. The item name comes from `Cctv.laptopItem`. |

If registration fails, `CCTV laptop registration failed` is printed in the server console. Make sure `laptop.png` exists in your inventory images.

## Items given by jobs

These must exist in your shared items (they are in kora_core's default item list).

| Item | Job | How |
| --- | --- | --- |
| `metalscrap`, `plastic`, `copper`, `rubber`, `iron`, `aluminum`, `steel`, `glass` | Recycle | Random rewards for handing in a package; can be sold back to the recycle ped. |
| `cryptostick` | Recycle | 20% chance per handed-in package. |

## Items consumed by jobs

| Item | Job | How |
| --- | --- | --- |
| configurable | Mechanic | `Mechanic.fullRepair.consume`, `Mechanic.roadsideRepair.consume` and `Mechanic.cosmetics.consume` can each be set to `{ item = 'repairkit', amount = 1 }`-style tables. All default to `nil` (no item cost). |
| materials above | Recycle | Removed when selling to the recycle ped. |

See [Mechanic](./features/mechanic.md#configuration) and [Recycle](./features/recycle.md#hard-coded-values).
