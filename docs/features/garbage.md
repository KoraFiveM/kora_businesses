---
title: Garbage
sidebar_position: 3
---

# Garbage

A garbage collection route job: take a truck from the depot, empty a random set of bins, and return the truck to get paid.

Files: `jobs/garbage/shared.lua` (config), `jobs/garbage/client.lua`, `jobs/garbage/server.lua`. Enabled by `Config.Garbage`. Requires the `garbage` job (hard-coded name).

## Usage

1. Players with the `garbage` job see the **Garbage Depot** blip. The blip is added on player load and when the job changes to `garbage`, and removed when the player leaves the job.
2. Talk to the depot ped (`Garbage.Peds`) and choose **Start Garbage Route**. The server builds a route of `MinStops` to `MaxStops` distinct random bins from `Garbage.Locations.trashcan`, each needing `MinBagsPerStop` to `MaxBagsPerStop` bags.
3. A `Garbage.Vehicle` truck (plate `GARBAGE`) spawns at a random `Garbage.Locations.vehicle` point. The server registers it (correct model, within 30 m of the player) and gives `GARBAGE` vehicle keys through kora_vehiclekeys.
4. Drive to the stop marked with a GPS route. Use **Grab Trash (x/y)** on the bin to pick up a bag (server checks you are within 4 m of the bin), then **Throw Trash Bag** on the truck (within 6 m of the truck). Only one bag can be carried at a time.
5. When every bag of the stop has been thrown in, the stop completes and the next stop is set. After the last stop, the depot blip gets a GPS route when `Config.GarbageDepotRoute` is not `false`.
6. Bring the truck within `ReturnDistance` of `Garbage.Locations.main` and use **Return Garbage Truck** on it. The server checks the route is finished, the truck model and that both you and the truck are within `ReturnDistance` of the depot, then pays `number of stops * 50` to your bank and deletes the truck.

Leaving the `garbage` job while on a route cancels it and deletes the truck. The route is also cleared when the player drops or the resource stops.

## Configuration

`Garbage` in `jobs/garbage/shared.lua`.

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `MinStops` | integer | `5` | Minimum stops per route. |
| `MaxStops` | integer | `6` | Maximum stops per route (capped at the number of bins). |
| `MinBagsPerStop` | integer | `1` | Minimum bags per stop. |
| `MaxBagsPerStop` | integer | `4` | Maximum bags per stop. |
| `ReturnDistance` | number | `10.0` | Distance from `Locations.main` within which the truck can be returned. |
| `Vehicle` | string | `'trash2'` | Truck model. |
| `Peds` | list | one `s_m_y_garbage` ped at the depot | Depot peds offering **Start Garbage Route**. Each entry has `model` and `coords` (`vector4`). |
| `BlipData.main` | table | label `Garbage Depot`, sprite 318, colour 5, scale 0.8, display 4 | Depot blip (`label`, `coords`, `sprite`, `color`, `scale`, `display`). |
| `Locations.main` | `vector3` | `vector3(-313.84, -1522.82, 27.56)` | Depot return point. |
| `Locations.vehicle` | list | two spawn points | Truck spawn points (`coords` as `vector4`). |
| `Locations.trashcan` | list | 21 bins | Possible stops (`coords` as `vector4`). |
| `TruckPrice` | integer | `250` | Unused. |
| `GiveCryptoStick` | boolean | `true` | Unused. |
| `CryptoStickChance` | integer | `75` | Unused. |
| `BagUpperWorth` | integer | `100` | Unused. |
| `BagLowerWorth` | integer | `50` | Unused. |
| `Locations.paycheck` | `vector3` | `vector3(-321.45, -1545.86, 31.02)` | Unused. |

Related global option: `Config.GarbageDepotRoute` (see [Configuration](../configuration.md)).

## Hard-coded values

- Pay: `50` per stop, paid to the bank on return (`jobs/garbage/server.lua`). The `Bag*Worth` keys do not affect pay.
- Job name `garbage`, bag prop `hei_prop_heist_binbag`, plate `GARBAGE`.
- No truck deposit is charged and no crypto stick is given, despite the unused config keys.
