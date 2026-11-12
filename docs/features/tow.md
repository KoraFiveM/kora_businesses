---
title: Tow
sidebar_position: 5
---

# Tow

A tow job: take a flatbed from the tow yard, collect marked vehicles and bring them back, then store the flatbed to get paid.

Files: `jobs/tow/shared.lua` (config), `jobs/tow/client.lua`, `jobs/tow/server.lua`. Enabled by `Config.Tow`. Requires the `tow` job (hard-coded name).

## Usage

1. Players with the `tow` job see a **Tow Yard** blip at `Tow.Locations.vehicle.coords`.
2. At the tow yard interaction (`Kora.interact` box zone), choose **Pull Out Vehicle**. The server checks you are within 10 m of the yard, have the `tow` job and have no flatbed out, then gives `TOW` vehicle keys. A `Tow.Vehicles` flatbed (plate `TOW`, full fuel) spawns with you inside.
3. A random vehicle from `Tow.Locations.towspots` spawns at its spot with a **Tow Pickup** blip and a waypoint.
4. At the vehicle, use the **Tow Vehicle** target option. The server checks you are within 10 m of the spot, and the vehicle is attached to the flatbed.
5. Drive back to the yard and use **Place Vehicle** on the towed vehicle. It is detached and placed using a raycast, and the server counts the delivery (you must be within 10 m of the yard). The delivered vehicle is deleted after about 15 seconds and a new pickup is marked.
6. Choose **Store Vehicle** at the yard. The server pays `deliveries * Tow.payPerVehicle` to your bank, removes the `TOW` keys and the client deletes the flatbed.

## Configuration

`Tow` in `jobs/tow/shared.lua`.

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `Vehicles` | string | `'flatbed'` | Flatbed model. |
| `payPerVehicle` | integer | `100` | Bank pay per delivered vehicle. |
| `Locations.vehicle.coords` | `vector3` | `vector3(489.65, -1331.82, 29.33)` | Tow yard interaction, blip and delivery point. |
| `Locations.vehicle.spawncoords` | `vector3` | `vector3(489.65, -1331.82, 29.33)` | Flatbed spawn position. |
| `Locations.towspots` | list | 40 spots | Each entry has `model` (vehicle to tow) and `coords` (`vector3`). |

## Hard-coded values

- Job name `tow`, plate `TOW`, keys group `TOW`.
- Server distance checks: 10 m for the yard and the tow spot.
- The flatbed heading is taken from `Locations.vehicle.coords.h`, which a `vector3` does not have, so it always falls back to 180 degrees.

## Known issues

- **Detach Vehicle** at the yard triggers the callback `qb-tow:server:CheckDistance`, which the server never registers, so this option does not work. Use **Place Vehicle** on the towed vehicle instead.
- **Place Vehicle** detaches the vehicle and schedules its deletion before asking the server to count the delivery. If you use it away from the yard, the server rejects the drop-off, the vehicle is lost without credit and no new pickup is marked.
- Duty is not checked.
