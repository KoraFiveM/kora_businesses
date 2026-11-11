---
title: Configuration
sidebar_position: 2
---

# Configuration

Configuration is split into a global file (`config.lua`) that decides which jobs load, and one configuration table per job. Each job page documents its own options in full; this page covers the global options and how overrides work.

## Global options (`config.lua`)

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `Config.Mechanic` | boolean | `true` | Load the mechanic job (`jobs/mechanic`). |
| `Config.Taxi` | boolean | `true` | Load the taxi job (`jobs/taxi`). |
| `Config.Garbage` | boolean | `true` | Load the garbage job (`jobs/garbage`). |
| `Config.Recycle` | boolean | `true` | Load the recycle job (`jobs/recycle`, including `sales.lua`). |
| `Config.Tow` | boolean | `true` | Load the tow job (`jobs/tow`). |
| `Config.Cctv` | boolean | `true` | Load the CCTV job (`jobs/cctv`). |
| `Config.GarbageDepotRoute` | boolean | `true` | Garbage job: set a GPS route to the depot blip once every stop is done. |
| `Config.enable` | list | see below | Loader table. Each entry has `name`, `enabled` and `filepaths` with `server`, `client` and `shared` file lists. |

`Config.enable` is evaluated when `config.lua` runs: for every enabled entry the shared files are loaded, then the server files on the server and the client files on clients (via `Kora.require.current`). Disabled jobs print `[jobs] <name> is disabled, skipping` to the console.

```lua
Config.enable = {
    {
        name = 'mechanic',
        enabled = Config.Mechanic,
        filepaths = {
            server = { 'jobs/mechanic/server.lua' },
            client = { 'jobs/mechanic/client.lua' },
            shared = { 'jobs/mechanic/shared.lua' },
        },
    },
    -- taxi, garbage, recycle, tow, cctv ...
}
```

There is no hotdog entry in `Config.enable`, so the hotdog job is never loaded. See [Hotdog](./features/hotdog.md).

Client files must also be listed under `files` in `fxmanifest.lua`, because clients can only load files that are shipped to them. Server files must never be listed there.

## Per-job configuration

| Job | Table | File | Page |
| --- | --- | --- | --- |
| Mechanic | `Mechanic` | `jobs/mechanic/shared.lua` | [Mechanic configuration](./features/mechanic.md#configuration) |
| Taxi | `Taxi` | `jobs/taxi/shared.lua` | [Taxi configuration](./features/taxi.md#configuration) |
| Garbage | `Garbage` | `jobs/garbage/shared.lua` | [Garbage configuration](./features/garbage.md#configuration) |
| Recycle | `Recycle` | `jobs/recycle/shared.lua` | [Recycle configuration](./features/recycle.md#configuration) |
| Tow | `Tow` | `jobs/tow/shared.lua` | [Tow configuration](./features/tow.md#configuration) |
| CCTV | `Cctv` | `jobs/cctv/shared.lua` | [CCTV configuration](./features/cctv.md#configuration) |
| Hotdog | `Hotdog` | `jobs/hotdog/config.lua` | [Hotdog configuration](./features/hotdog.md#configuration) |

Some values are hard-coded in server files rather than configurable (for example garbage pay per stop, taxi fare rate, recycle rewards and sell prices). Each job page lists these under "Hard-coded values".

## Overrides

Each loaded job stores its table in the global `Globals` table (`Globals.Config`, `Globals.Mechanic`, `Globals.Taxi`, `Globals.Garbage`, `Globals.Recycle`, `Globals.Tow`, `Globals.Cctv`). After all jobs have loaded, `init.lua` passes every table in `Globals` to `Kora.config.adopt` with `fileName = 'businesses.config.local.lua'`. This registers the values with the kora_lib configuration system, which reads overrides from that file on the server and writes to it when settings are saved.

The override file returns a table keyed by the same names:

```lua
return {
    ["Config"] = {
        ["Taxi"] = true,
    },
    ["Garbage"] = {
        ["MinStops"] = 3,
    },
}
```

Notes:

- Adoption mutates the job tables in place, so overrides of job values (for example `Garbage.MinStops`) are seen by code that reads them at runtime.
- The job toggles (`Config.Mechanic`, `Config.Taxi`, ...) are copied into `Config.enable` and the jobs are loaded before `init.lua` runs. Changing a toggle through the override file therefore does not change which jobs were loaded; edit `config.lua` to enable or disable a job.
- The taxi job also calls `Kora.config.adopt` on its own `Taxi` table (with field labels and descriptions) before the resource-wide adoption runs. See [Taxi](./features/taxi.md#configuration).

## Locales

`locales/en.lua` holds strings for the recycle and hotdog jobs, read with `Kora.lang('recycle.text.sell')`-style keys. Mechanic, garbage, taxi, tow and CCTV messages are written directly in their Lua files.
