---
title: "Job toggles and boot"
sidebar_position: 2
---


# Job toggles and boot

`config.lua` is the only shared script the manifest lists directly; it both holds the six job on/off flags and is responsible for `Kora.require.current`-loading every enabled job's shared/server/client files, then finally `init.lua` (which wires up the local config-override file).

Namespace: `Config / Globals` · Source: `config.lua, init.lua, fxmanifest.lua`

## Config.enable entries

Each row of `Config.enable` in `config.lua`.

| Job | Flag | Default | Files required when enabled |
| --- | --- | --- | --- |
| mechanic | Config.Mechanic | true | jobs/mechanic/&#123;server,client,shared&#125;.lua |
| taxi | Config.Taxi | true | jobs/taxi/&#123;server,client,shared&#125;.lua |
| garbage | Config.Garbage | true | jobs/garbage/&#123;server,client,shared&#125;.lua |
| recycle | Config.Recycle | true | jobs/recycle/&#123;server,client,shared&#125;.lua, jobs/recycle/sales.lua (client) |
| tow | Config.Tow | true | jobs/tow/&#123;server,client,shared&#125;.lua |
| cctv | Config.Cctv | true | jobs/cctv/&#123;server,client,shared&#125;.lua |
| hotdog | (none — no Config.Hotdog flag, no Config.enable entry) | n/a | jobs/hotdog/&#123;server,client,config&#125;.lua — present on disk, never required by config.lua |

## How it works

The boot loop in `config.lua` runs once at resource start, in the order `Config.enable` lists its entries (mechanic, taxi, garbage, recycle, tow, cctv). For each enabled entry it requires the job's shared file(s) first, then server files on the server or client files on the client (`IsDuplicityVersion()` decides which). A disabled job prints `[jobs] <name> is disabled, skipping` and none of its code, globals, callbacks or database schema exist for that boot.

## Options

Pass an options table as the final argument to a play function. Omit the table or any field to use its default.

| Option | Type | Description |
| --- | --- | --- |
| `Config.GarbageDepotRoute` | boolean | Default true. When true, the garbage client draws a GPS route to the depot blip once every stop on the current route is complete. Purely cosmetic; does not affect payout. |

## businesses.config.local.lua

`init.lua` runs after the per-job boot loop. It gathers every table currently held in the shared `Globals` table (`Globals.Config`, and one entry per job whose shared file ran — `Cctv`, `Garbage`, `Mechanic`, `Recycle`, `Tow`, `Taxi`; `Hotdog` is absent unless you wire that job up yourself) and, only if `Kora.config.adopt` exists (kora_lib's config system is present), passes all of them in one call to `Kora.config.adopt(businesses, { fileName = 'businesses.config.local.lua' })`. This is the same mechanism other Kora resources use to persist in-editor config changes to disk.

## Disabled job state

Disabling a job does not just hide its UI: the job's shared table (for example `Mechanic` or `Recycle`) is never created, so any other resource reading `Mechanic`/`exports.kora_businesses` style globals for a disabled job will get nil, not a disabled placeholder.

## Functions

Not an export — this is the resource's own internal bootstrap, documented because every job's availability depends on it.

## Limits and related APIs

Shared only in the sense that `config.lua` itself runs on both sides; the per-job tables it loads are each scoped to server or client as listed above. There is no single export that reports which jobs are currently enabled — read `Config.Mechanic`/`Config.Taxi`/etc. directly if another resource needs to know.

## Related guides

- [CCTV engineer](./cctv.md)
- [Garbage collector](./garbage.md)
- [Hotdog vendor](./hotdog.md)
- [Mechanic / bodyshop](./mechanic.md)
- [Recycling centre](./recycle.md)
- [Tow truck driver](./tow.md)
- [Taxi driver](./taxi.md)
