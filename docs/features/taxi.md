---
title: Taxi
sidebar_position: 2
---

# Taxi

An NPC taxi job: spawn a cab at the depot, pick up a passenger at a random location, drive them to a random destination and get paid cash.

Files: `jobs/taxi/shared.lua` (config), `jobs/taxi/client.lua`, `jobs/taxi/server.lua`. Enabled by `Config.Taxi`.

## Usage

1. Go to the depot interaction at `Taxi.parkLocation` (a `Kora.interact` box zone) and choose **Spawn Taxi**. A `taxi` vehicle with the plate `TAXI` is created and you are warped into the driver seat.
2. The client asks the server for a fare (`qb-taxi:getPickupLocation`). The server only answers for players whose job is `Taxi.jobRequired`; otherwise you get "You must be on duty as a taxi driver." and the taxi is removed.
3. A random passenger ped from `Taxi.Peds` waits at a random `Taxi.PickUp` location, and a waypoint is set.
4. Drive into the 5 m pickup zone. The passenger gets into a free seat; the server checks that you are within 5 m of the pickup. A waypoint is set to the destination.
5. Drive into the 5 m destination zone. The passenger leaves, and the server (after checking distance and that the pickup was done) pays `floor(distance * 0.2)` in cash, where distance is the straight-line distance between the pickup and the destination.
6. The server immediately starts the next fare.
7. Choose **Return Taxi** at the depot to delete the taxi, the passenger and the zones.

Fares are lost when the player drops or unloads their character.

## Configuration

`Taxi` in `jobs/taxi/shared.lua`.

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `jobRequired` | string | `'taxi'` | Job name required by the server for every fare step. |
| `Management` | boolean | `false` | Unused. Fares are always paid to the driver in cash. |
| `parkLocation` | `vector3` | `vector3(909.5, -177.35, 74.22)` | Depot interaction position and taxi spawn point. |
| `PickUp` | list of `vector4` | 16 locations | Random pickup locations (x, y, z, heading). |
| `DropOffs` | list of `vector4` | 23 locations | Random destinations. The distance to the pickup determines the fare. |
| `Peds` | list of strings | 140 ped models | Random passenger models. |

The taxi file calls `Kora.config.adopt` on `Taxi` itself, adding labels and descriptions for these fields, and the table is adopted again by the resource-wide `init.lua` (see [Configuration](../configuration.md#overrides)).

## Hard-coded values

- Fare: `math.floor(distance * 0.2)` cash, in `jobs/taxi/server.lua`.
- Pickup and destination zone size: 5 m boxes; server distance checks: 5 m.
- Vehicle model `taxi`, plate `TAXI`.

## Known issues

- The config descriptions registered in `jobs/taxi/shared.lua` say `jobRequired` is unused and tell admins to "Restart kora_taxi". In fact the server does check `jobRequired`, and the job lives in `kora_businesses`.
- Duty is not checked, although the rejection message mentions being on duty.
- **Spawn Taxi** has no client-side job check; non-taxi players can briefly spawn a taxi before it is removed.
