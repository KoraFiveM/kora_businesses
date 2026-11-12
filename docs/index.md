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

See [Installation](./installation.md#requirements) for the declared dependencies and the runtime-only ones (`kora_target`, `kora_vehiclekeys`, optional `kora_voice`).

## Documentation map

- [Installation](./installation.md) - dependencies, `server.cfg` order, job toggles, how jobs load, hotdog status, local config overrides, file layout.
- [How to use](./how-to-use.md) - the gameplay loop of every job.
- [Commands and keybinds](./commands.md) - `/cctvhack`, `/cctvrepair`, `/removestand`, the hotdog keybind and where interactions are listed.
- [API reference](./api/index.md) - per-module callbacks, events and functions:
  - [Job toggles and boot](./api/job-toggles.md)
  - [CCTV engineer](./api/cctv.md)
  - [Garbage collector](./api/garbage.md)
  - [Hotdog vendor](./api/hotdog.md)
  - [Mechanic / bodyshop](./api/mechanic.md)
  - [Recycling centre](./api/recycle.md)
  - [Tow truck driver](./api/tow.md)
  - [Taxi driver](./api/taxi.md)
- [Configuration](./configuration.md) - job toggles, override file, and where each job's settings live.
- [Jobs and permissions](./jobs.md) - which job names, job types, duty and grades each feature checks.
- [Exports](./exports.md) - the `getCctvCallouts` server export.
- [Events and callbacks](./events.md) - code-derived list of events and callbacks.
- [Database](./database.md) - CCTV tables.
- [Items](./items.md) - items used and registered.
- Features: [Mechanic](./features/mechanic.md), [Taxi](./features/taxi.md), [Garbage](./features/garbage.md), [Recycle](./features/recycle.md), [Tow](./features/tow.md), [CCTV](./features/cctv.md), [Hotdog](./features/hotdog.md)

