---
title: kora_businesses
sidebar_position: 1
---

# kora_businesses

`kora_businesses` bundles several small civilian jobs for a Kora FiveM server into one resource: a mechanic service system with passive vehicle wear, a taxi job, a garbage route job, a recycling warehouse, a tow job, and a CCTV engineer job with call-outs, hacking and repair checks. Each job lives in its own folder under `jobs/` and can be switched on or off in `config.lua`. A hotdog stand job is also present in the source tree but is not loaded by the default configuration.

## Features

| Feature | Summary | Page |
| --- | --- | --- |
| Mechanic | Server-authorised full repairs (garage bays only), roadside stabilisation, resprays and bumper changes via `kora_target` vehicle options; client-side passive vehicle wear, extra collision damage, random tyre bursts and limp mode. | [Mechanic](./features/mechanic.md) |
| Taxi | Spawn a taxi at the depot, collect an NPC passenger at a random pickup, drive them to a random destination and get paid cash by distance. | [Taxi](./features/taxi.md) |
| Garbage | Start a route at the depot NPC, collect bags from random bins, throw them in the truck and return the truck for a bank payment. | [Garbage](./features/garbage.md) |
| Recycle | Enter the recycling warehouse, clock in, carry packages to the drop point for random materials, and sell materials to a ped. | [Recycle](./features/recycle.md) |
| Tow | Take a flatbed from the tow yard, tow marked vehicles back to the yard and get paid per vehicle. | [Tow](./features/tow.md) |
| CCTV | Engineer laptop (AppShell) listing installed systems and call-outs, paid emergency call-outs for businesses and homeowners, skill-check based hacking and repair checks. | [CCTV](./features/cctv.md) |
| Hotdog (not loaded) | Hotdog stand job with deposit, preparation minigame, skill-based stock and ped sales. Present in `jobs/hotdog/` but not wired into `Config.enable`. | [Hotdog](./features/hotdog.md) |

## Requirements

Declared in `fxmanifest.lua`:

- [kora_lib](https://github.com/KoraFiveM/kora_lib) - callbacks, notifications, blips, zones, interactions, progress bars, minigames, NUI AppShell, configuration adoption.
- [kora_sql](https://github.com/KoraFiveM/kora_sql) - CCTV schema (`Kora.sql.ensureTables`) and queries.
- [kora_core](https://github.com/KoraFiveM/kora_core) - player data, jobs, money, items, the `removestand` command helper.
- [kora_inventory](https://github.com/KoraFiveM/kora_inventory) - item rewards, item removal and the usable CCTV laptop.
- [kora_banking](https://github.com/KoraFiveM/kora_banking) - CCTV society account charges and payouts.
- [kora_skills](https://github.com/KoraFiveM/kora_skills) - skill levels for the CCTV hack and the hotdog job.

Used at runtime but not declared as dependencies:

- [kora_target](https://github.com/KoraFiveM/kora_target) - target options for the mechanic, garbage, recycle and tow jobs.
- [kora_vehiclekeys](https://github.com/KoraFiveM/kora_vehiclekeys) - keys for the garbage truck (`GARBAGE`) and the tow flatbed (`TOW`).
- `kora_voice` (optional) - the CCTV hack fires the local server event `kora_voice:server:bucketChanged` when it moves a player between routing buckets.

## Installation

1. Place the resource in your resources folder (for example inside `[kora]`).
2. Ensure it after its dependencies in `server.cfg`:

   ```cfg
   ensure kora_lib
   ensure kora_sql
   ensure kora_core
   ensure kora_inventory
   ensure kora_banking
   ensure kora_skills
   ensure kora_target
   ensure kora_vehiclekeys
   ensure kora_businesses
   ```

3. Database: no manual SQL import is needed. The CCTV tables are created or updated at startup with `Kora.sql.ensureTables`. See [Database](./database.md).
4. Items: the `cctv_laptop` item is registered automatically. The recycling rewards must exist in your shared items. See [Items](./items.md).
5. Jobs: the jobs referenced by each feature must exist in your job configuration (for example `cctv`, which is not created by this resource). See [Jobs and permissions](./jobs.md).
6. Optionally disable jobs you do not want in `config.lua`. See [Configuration](./configuration.md).

## Documentation pages

- [Configuration](./configuration.md) - job toggles, override file, and where each job's settings live.
- [Jobs and permissions](./jobs.md) - which job names, job types, duty and grades each feature checks.
- [Commands and keybinds](./commands.md)
- [Exports](./exports.md)
- [Events and callbacks](./events.md)
- [Database](./database.md)
- [Items](./items.md)
- Features: [Mechanic](./features/mechanic.md), [Taxi](./features/taxi.md), [Garbage](./features/garbage.md), [Recycle](./features/recycle.md), [Tow](./features/tow.md), [CCTV](./features/cctv.md), [Hotdog](./features/hotdog.md)

## File layout

```text
fxmanifest.lua              resource manifest
config.lua                  job toggles (Config.enable) and job loader
init.lua                    registers job config tables with Kora.config.adopt
businesses.config.local.lua saved configuration overrides
jobs/<job>/shared.lua       per-job configuration (hotdog uses config.lua)
jobs/<job>/client.lua       client logic
jobs/<job>/server.lua       server logic (never sent to clients)
locales/en.lua              recycle and hotdog strings
tests/                      offline Lua tests and kora_qa checklist scenarios
```
