---
title: Mechanic
sidebar_position: 1
---

# Mechanic

The mechanic job adds four vehicle services, offered as `kora_target` options on every vehicle, and a passive damage system that runs on the driver's client.

Files: `jobs/mechanic/shared.lua` (config), `jobs/mechanic/client.lua`, `jobs/mechanic/server.lua`. Enabled by `Config.Mechanic`.

## Usage

Target any vehicle (within `Mechanic.interaction.distance`) to see the options your job allows:

| Option | Action | Who | Where | Duration | Result |
| --- | --- | --- | --- | --- | --- |
| Full garage repair | `fullRepair` | `mechanic` job or `automotive` job type, not a roadside job | vehicle within `garageRadius` of a configured garage bay (when `requireGarage` is set) | 18 s | Fixes the vehicle and deformation, sets engine, body and petrol tank health to 1000 and makes it driveable. |
| Roadside stabilisation | `roadsideRepair` | `mechanic` job or `automotive` job type | anywhere | 9 s | Raises engine health to at least 650 and body health to at least 500, fixes one burst tyre (if `repairOneTyre`) and makes it driveable. Never a full repair. |
| Respray vehicle | `paint` | `bodyshop` job name or type | inside a garage bay when `requireShopZone` is set | 12 s | Opens an input dialog for primary and secondary GTA paint indices (0-160), then applies them. |
| Customise bumpers | `bumpers` | `bodyshop` job name or type | inside a garage bay when `requireShopZone` is set | 12 s | Opens an input dialog for front and rear bumper variations (`-1` = stock, up to `bumperModMax`), clamped to the variations the model supports. |

All services require the player to be on duty when `Mechanic.roles.requireOnDuty` is `true`. See [Jobs and permissions](../jobs.md) for the role rules.

### Service flow

1. The client collects the input (dialogs for paint and bumpers) and asks the server for a permit with the `kora_businesses:mechanic:permit` callback.
2. The server resolves the vehicle by network ID within `interaction.distance`, checks the player's role, duty and location, and returns a single-use permit valid for `permitLifetime` ms.
3. The client runs a cancellable progress bar with the `WORLD_HUMAN_VEHICLE_MECHANIC` scenario.
4. The client sends `kora_businesses:server:serviceCompleted` with the permit and payload. The server consumes the permit, re-checks the vehicle, role and location, validates the payload ranges and removes the configured item, if any.
5. The server sends `kora_businesses:client:serviceApplied` back to the same player, whose client takes network control of the vehicle and applies the change.

## Passive vehicle damage

While the player drives an eligible vehicle (driver seat, class not in `excludedClasses`), a client worker runs every `damage.interval` ms. It starts when kora_lib's cached `seat` or `vehicle` changes and stops when the player is no longer driving.

- Distance wear (off by default): lowers engine and body health per kilometre driven above `minSpeed`.
- Collision wear: when the vehicle lost at least `minSpeedLoss` m/s since the last sample and native engine or body health also dropped by more than `minNativeHealthLoss`, extra damage proportional to the speed loss is applied, capped by `maxEngineDamage` and `maxBodyDamage`. Braking alone never counts.
- Tyre bursts: at most once per `checkInterval`, a vehicle driven above `minSpeed` whose engine health is at or below `minEngineHealth` has a `chance` probability to burst a random tyre.
- Limp mode: at or below `engineHealthThreshold` engine health, the engine torque multiplier is set to `torqueMultiplier`, and above `stallMinSpeed` the engine may stall with `stallChance` each interval.

Excluded classes by default: 8 (motorcycles), 13 (cycles), 14 (boats), 15 (helicopters), 16 (planes).

## Configuration

`Mechanic` in `jobs/mechanic/shared.lua`.

### `Mechanic.roles`

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `requireOnDuty` | boolean | `true` | Staff must be on duty to use any service. |
| `fullRepairJob` | string | `'mechanic'` | Job name that counts as automotive staff. |
| `automotiveType` | string | `'automotive'` | Job type that counts as automotive staff. |
| `roadsideJobs` | table | `{ roadside = true }` | Job names that cannot perform full repairs. |
| `bodyshopJobs` | table | `{ bodyshop = true }` | Job names allowed to do cosmetic work. |
| `bodyshopTypes` | table | `{ bodyshop = true }` | Job types allowed to do cosmetic work. |

### `Mechanic.interaction`

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `distance` | number | `3.0` | Maximum player-to-vehicle distance, checked server-side; also the target distance. |
| `permitLifetime` | number (ms) | `45000` | Time allowed between permit and completion. |
| `permitRateLimit` | table | `{ max = 8, window = 10000 }` | Rate limit for the permit callback. |
| `requireShopZone` | boolean | `true` | Respray and bumper options only show and are only accepted within `garageRadius` of a `fullRepair.garages` bay. `false` allows them anywhere. |

### `Mechanic.fullRepair`

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `label` | string | `'Perform full repair'` | Progress bar label. |
| `duration` | number (ms) | `18000` | Progress bar duration. |
| `requireGarage` | boolean | `true` | Full repairs only within `garageRadius` of a bay. |
| `garages` | list of `vector3` | LS Customs Burton, LS Customs La Mesa, Route 68 | Garage bay positions. Also used as shop zones for cosmetics. |
| `garageRadius` | number | `12.0` | Bay radius in metres (vehicle position). |
| `consume` | table or `nil` | `nil` | Item cost, for example `{ item = 'repairkit', amount = 1 }`. |

### `Mechanic.roadsideRepair`

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `label` | string | `'Stabilise vehicle'` | Progress bar label. |
| `duration` | number (ms) | `9000` | Progress bar duration. |
| `engineHealthFloor` | number | `650.0` | Minimum engine health after stabilisation. |
| `bodyHealthFloor` | number | `500.0` | Minimum body health after stabilisation. |
| `repairOneTyre` | boolean | `true` | Fix the first burst tyre found. |
| `consume` | table or `nil` | `nil` | Item cost, for example `{ item = 'roadsidekit', amount = 1 }`. |

### `Mechanic.cosmetics`

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `duration` | number (ms) | `12000` | Progress bar duration for respray and bumpers. |
| `paintColourMin` | integer | `0` | Lowest accepted paint index. |
| `paintColourMax` | integer | `160` | Highest accepted paint index. |
| `bumperModMax` | integer | `50` | Highest accepted bumper variation; the client also clamps to the model's mod count. |
| `consume` | table or `nil` | `nil` | Item cost shared by respray and bumpers, for example `{ item = 'spraycan', amount = 1 }`. |

### `Mechanic.damage`

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `enabled` | boolean | `true` | Master switch for passive damage. |
| `interval` | number (ms) | `1500` | Sample interval while driving. |
| `excludedClasses` | table | `{ [8] = true, [13] = true, [14] = true, [15] = true, [16] = true }` | Vehicle classes ignored. |
| `distanceWear.enabled` | boolean | `false` | Opt-in wear without collisions. |
| `distanceWear.enginePerKm` | number | `0.65` | Engine health lost per km. |
| `distanceWear.bodyPerKm` | number | `0.18` | Body health lost per km. |
| `distanceWear.minSpeed` | number (m/s) | `4.0` | No wear below this speed. |
| `collision.enabled` | boolean | `true` | Extra collision wear. |
| `collision.minSpeedLoss` | number (m/s) | `7.0` | Speed lost between samples before extra wear applies. |
| `collision.minNativeHealthLoss` | number | `1.0` | Native health loss needed to count as a collision. |
| `collision.engineDamagePerSpeedLoss` | number | `4.0` | Engine damage per m/s lost. |
| `collision.bodyDamagePerSpeedLoss` | number | `7.0` | Body damage per m/s lost. |
| `collision.maxEngineDamage` | number | `140.0` | Cap per collision. |
| `collision.maxBodyDamage` | number | `190.0` | Cap per collision. |
| `tyres.enabled` | boolean | `true` | Random tyre bursts. |
| `tyres.checkInterval` | number (ms) | `30000` | One roll per vehicle per interval. |
| `tyres.chance` | number | `0.003` | Burst probability per roll (0.3%). |
| `tyres.minSpeed` | number (m/s) | `22.0` | Minimum speed for a roll. |
| `tyres.minEngineHealth` | number | `250.0` | Rolls only happen at or below this engine health. |
| `tyres.burstOnRims` | boolean | `false` | Passed to `SetVehicleTyreBurst`. |
| `limpMode.enabled` | boolean | `true` | Limp mode on low engine health. |
| `limpMode.engineHealthThreshold` | number | `300.0` | Engine health at which limp mode starts. |
| `limpMode.torqueMultiplier` | number | `0.58` | Torque multiplier in limp mode. |
| `limpMode.stallChance` | number | `0.08` | Stall probability per interval. |
| `limpMode.stallMinSpeed` | number (m/s) | `2.0` | No stalling below this speed. |

Note that `tyres.minEngineHealth` is an upper limit: the code skips the roll when engine health is above it, so healthy vehicles never burst tyres randomly.

## Known issues

- The server rejection message for a full repair outside a bay reads "Mechanicured garage bay" (typo).
- The client shows "Full garage repair" whenever the role allows it; the garage-bay check happens only on the server, so outside a bay the option is shown and then rejected.
