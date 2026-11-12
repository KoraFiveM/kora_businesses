---
title: "Installation"
sidebar_position: 2
---


# Installation

Kora Businesses bundles several independent gig-style player jobs on one resource: CCTV engineer, garbage collector, hotdog vendor, mechanic/bodyshop, recycling centre, tow truck driver and taxi driver. Each job is its own `jobs/<name>/` folder with its own shared config, server logic and client logic; `config.lua` decides at boot which of them actually load.

## Install Kora Businesses

1. **Add the folder** — Place `kora_businesses` in your resources directory (on the Kora recipe it is `resources/[kora]/kora_businesses`).

2. **Have the dependencies running** — The manifest declares `kora_lib`, `kora_sql`, `kora_core`, `kora_inventory`, `kora_banking` and `kora_skills` as dependencies. `kora_banking` is used by the CCTV job (`exports.kora_banking:AddMoney/RemoveMoney` against business accounts); `kora_skills` is used by CCTV and hotdog (`exports.kora_skills:getRep/addRep`); `kora_inventory` registers the CCTV laptop as a usable item. `kora_target` and `kora_vehiclekeys` are called through exports (`kora_target`: garbage, mechanic, recycle, tow; `kora_vehiclekeys`: garbage, tow; neither is referenced by `jobs/cctv/`) but are not declared as `dependency` entries in the manifest — start them before `kora_businesses` anyway.

3. **Start it after its dependencies** — Add it to `server.cfg` after the six declared dependencies and after `kora_target`/`kora_vehiclekeys` if you run them.

   ```bash title="server.cfg"
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

4. **Pick which jobs run** — Open `config.lua`. Six boolean flags (`Config.Mechanic`, `Config.Taxi`, `Config.Garbage`, `Config.Recycle`, `Config.Tow`, `Config.Cctv`, all `true` by default) each gate one entry of `Config.enable`, a list of `{ name, enabled, filepaths = { server, client, shared } }` tables.

   ```lua title="config.lua" {8}
   -- config.lua
   Config.Mechanic = true
   Config.Taxi = true
   Config.Garbage = true
   Config.Recycle = true
   Config.Tow = true
   Config.Cctv = true
   Config.enable = {
       { name = 'mechanic', enabled = Config.Mechanic, filepaths = {
           server = { 'jobs/mechanic/server.lua' },
           client = { 'jobs/mechanic/client.lua' },
           shared = { 'jobs/mechanic/shared.lua' },
       } },
       -- taxi, garbage, recycle, tow, cctv follow the same shape.
       -- hotdog has no entry here: see "The hotdog job is not wired up" below.
   }
   ```

5. **How a job actually loads** — At the bottom of `config.lua`, a loop walks `Config.enable`: for every entry whose `enabled` is true it calls `Kora.require.current(path)` (kora_lib's loader) on the entry's `shared` paths, then on `server` paths on the server or `client` paths on the client. A disabled entry just prints `[jobs] <name> is disabled, skipping` and nothing under `jobs/<name>/` is loaded at all — no globals, no callbacks, no database schema.

6. **Client file exposure** — The manifest's `files` block lists each `jobs/<job>/client.lua` and `jobs/<job>/shared.lua` explicitly (FiveM globs do not expand `*` in a directory segment; `fxmanifest.lua:34-35`), plus `jobs/recycle/sales.lua`, for client download, plus `locales/**.lua`, `docs/**.md` and `init.lua`. `jobs/*/server.lua` is deliberately left out of `files`: the server only reads it from disk through `Kora.require.current`, and it is never shipped to clients.

## The hotdog job is not wired up

`jobs/hotdog/` has a full client, server and `config.lua` (the `Hotdog` table), but `Config.enable` in `config.lua` has no entry for it and there is no `Config.Hotdog` flag. Nothing in the resource's boot path requires `jobs/hotdog/config.lua`, `jobs/hotdog/server.lua` or `jobs/hotdog/client.lua`.

- As shipped, the hotdog vendor job is inactive: the `Hotdog` global is never populated, its callbacks (`qb-hotdogjob:*`) are never registered, and its locale strings and `/removestand` command never run.
- To enable it yourself you would need to add an entry to `Config.enable` (name `hotdog`, its own `filepaths.server/client/shared`) and require `jobs/hotdog/config.lua` as a shared script — this is not done anywhere in the source read for this page, so treat enabling it as unverified: test it before relying on it.
- The rest of this page documents the hotdog job's code as written, but flags every section of it as currently unreachable in a stock install.

## Local config overrides

`init.lua` collects every table value currently in the shared global `Globals` (populated as `Globals.Config`, `Globals.Cctv`, `Globals.Garbage`, `Globals.Mechanic`, `Globals.Recycle`, `Globals.Tow`, `Globals.Taxi` — and `Globals.Hotdog` only if that job were wired up) and, when kora_lib's config system is present (`Kora.config.adopt`), passes all of them to `Kora.config.adopt(businesses, { fileName = 'businesses.config.local.lua' })` in one call.

```lua title="businesses.config.local.lua"
-- businesses.config.local.lua (checked in as a worked example)
return {
    ["Config"] = {
        ["Taxi"] = true,
    },
}
```

- This file is checked into the resource as a worked example, not a template you must copy: it currently only reinstates the already-true default `Config.Taxi = true`.
- It is how kora_lib's config editor persists any value you change in-game back to disk, keyed by the top-level global name (`Config`, `Mechanic`, `Garbage`, `Recycle`, `Tow`, `Cctv`) and, for taxi, by the fields `taxi/shared.lua` itself registers on `Taxi` (see the Taxi section below).
- Only `Config` (job on/off flags) and `Taxi` register individual fields with kora_lib's typed config editor in this resource's source. `Cctv`, `Garbage`, `Mechanic`, `Recycle` and `Tow` are plain Lua tables with no `config.*` calls of their own — the generic `Kora.config.adopt` call in `init.lua` can still read overrides for them from `businesses.config.local.lua` by table name, but there is no in-editor UI generated for their individual fields; edit `jobs/<name>/shared.lua` directly for those, or hand-write the override file.

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

## After installing

- Database: no manual SQL import is needed. The CCTV tables are created or updated at startup with `Kora.sql.ensureTables`. See [Database](./database.md).
- Items: the `cctv_laptop` item is registered automatically. The recycling rewards must exist in your shared items. See [Items](./items.md).
- Jobs: the jobs referenced by each feature must exist in your job configuration (for example `cctv`, which is not created by this resource). See [Jobs and permissions](./jobs.md).
- Configuration: see [Configuration](./configuration.md). `config.lua` also has `Config.GarbageDepotRoute` (default `true`), which sets a GPS route to the depot blip once every garbage stop is done.

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
