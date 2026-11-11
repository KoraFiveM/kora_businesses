---
title: Hotdog (not loaded)
sidebar_position: 7
---

# Hotdog (not loaded)

The source tree contains a hotdog stand job in `jobs/hotdog/` (`config.lua`, `client.lua`, `server.lua`), but it is **not loaded**: there is no hotdog entry in `Config.enable` in the resource's `config.lua`, and the hotdog files are not listed under `files` in `fxmanifest.lua`. Nothing on this page is active on a server running the resource as shipped, including the `/removestand` command and the `G` keybind.

Enabling it would require code changes (a `Config.enable` entry loading `jobs/hotdog/config.lua` as shared, plus the server and client files, and adding the client and config files to the manifest `files`). This page describes what the code does so that the work can be judged.

## What the code does

- **Stand**: players with the `hotdog` job see a **Hotdog Stand** blip and a **Start Working** interaction at `Hotdog.Locations.take`. Starting takes a `Hotdog.StandDeposit` deposit from the bank and spawns a `prop_hotdogstand_01` at `Hotdog.Locations.spawn`. **Stop Working** refunds the deposit and removes the stand.
- **Pushing**: **Grab Stall** on the stand lets the player push it; the `letgostand` keybind (default `G`) releases it.
- **Preparing**: **Prepare Hotdog** plays a server-authorised `keys` minigame with `Hotdog.PrepareMinigameKeys` keys. On success the server rolls a quality from `Hotdog.PrepareRewards` (common 70, rare 25, exotic 5), adds `Hotdog.batchSize(level, quality)` units up to the stock cap, and awards `cooking` XP through kora_skills (`PrepareXp` per unit). kora_skills must be started.
- **Selling**: **Toggle Selling** makes nearby non-player peds (within 15 m of the stand) walk up and offer to buy 1 to 3 hotdogs of a random quality in stock. Accepting sells them if the ped is within `Hotdog.SaleDistance`; the server picks a unit price in the configured range, pays cash and awards `SaleXp` per unit. The player must stay near the stand.
- **Check stock**: a small AppShell app shows stock per quality, level and cooking XP.
- **Admin**: `/removestand` (kora_core permission `admin`) deletes the nearest stand within 5 m of the admin.

Stock and the deposit state are held in memory per citizen and cleared when the player drops.

## Configuration

`Hotdog` in `jobs/hotdog/config.lua`.

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `StandDeposit` | integer | `250` | Bank deposit taken on start and refunded on stop. |
| `Skill` | string | `'cooking'` | kora_skills skill for levels and XP. |
| `SaleDistance` | number | `4.0` | Maximum distance between the player and the buying ped (server check). |
| `PrepareXp` | table | `{ common = 1, rare = 2, exotic = 3 }` | XP per prepared unit by quality. |
| `SaleXp` | table | `{ common = 1, rare = 2, exotic = 3 }` | XP per sold unit by quality. |
| `batchSize` | function | see below | Units produced per successful preparation. |
| `PrepareMinigameKeys` | integer | `10` | Keys in the preparation minigame. |
| `PrepareRewards` | list | common 70, rare 25, exotic 5 | Weighted quality roll (`Kora.rewards.generate`). |
| `Locations.take` | `vector4` | `vector4(39.31, -1005.54, 29.48, 240.57)` | Start/stop interaction and blip. |
| `Locations.spawn` | `vector4` | `vector4(38.15, -1001.65, 29.44, 342.5)` | Stand spawn point. |
| `Stock.<quality>.Max` | table | `15, 30, 45, 60` for tiers 1 to 4 | Stock cap per tier. |
| `Stock.<quality>.Label` | string | locale `hotdog.info.label_a`, `label_b`, `label_c` | Display label. |
| `Stock.<quality>.Price` | table | per tier `min`/`max`; exotic 8-12 to 11-15, rare 6-9 to 9-12, common 4-6 to 7-9 | Unit price range per tier. |

`batchSize(level, rarity)` returns 4 at level 90 or above, 3 for exotic at level 70 or above, 2 for rare at level 30 or above, 2 for common at level 15 or above, otherwise 1.

The stock and price tier is `min(skill level, 4)`, so every player at skill level 4 or higher uses tier 4.

## Known issues

- Not loaded by default (see above).
- The event `qb-hotdogjob:staff:DeletStand` and the callback names keep their legacy `qb-` prefix and spelling.
