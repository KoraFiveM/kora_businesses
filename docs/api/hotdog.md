---
title: "Hotdog vendor (inactive by default)"
sidebar_position: 5
---


# Hotdog vendor (inactive by default)

## Server

A deposit-gated vendor stand loop: pay a deposit to start, prepare stock via a minigame, sell to NPCs, refund the deposit on stop. Not loaded in a stock install — see Installation for why.

Namespace: `Hotdog / qb-hotdogjob:*` · Source: `jobs/hotdog/server.lua, jobs/hotdog/config.lua`

### How it works

Stock levels, prices and prepare/sale XP are all per-quality (`common`/`rare`/`exotic`) and per-skill-level (`cooking`, via `exports.kora_skills`). `Hotdog.batchSize(level, rarity)` returns 1–4 hot dogs per successful prepare depending on level and rarity thresholds (level 90+ always 4; exotic needs level 70+ for 3; rare/common need level 30+/15+ for 2).

### Functions

Four callbacks (start/stop working, begin/finish preparing, sell).

#### `Kora.callback.register('qb-hotdogjob:startWorking', fn)`

Pays/refunds the stand deposit and marks the character as currently working a stand (`Working[cid]`).

**Parameters**



**Returns**

- **`true`/`false, message`.**

**Example**

```lua
local ok = Kora.callback.trigger('qb-hotdogjob:startWorking')
```

**Representative console output**

```text
`startWorking` requires job `hotdog` and charges `Hotdog.StandDeposit` (250) from the bank. `stopWorking` refunds the same amount and clears `Working[cid]`.
```

#### `Kora.callback.register('qb-hotdogjob:beginPreparing', fn)`

Server-authorised key-mash minigame (`Kora.minigames.authorizeProof(src, 'keys', { amount = Hotdog.PrepareMinigameKeys })`, 10 presses) that grants hot dogs on success.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `proof, authorization` | string, any | From the client's completed minigame, passed to `finishPreparing`. |

**Returns**

- **`beginPreparing`: `true, authorization` or `false, message`.**
- **`finishPreparing`: `{ quality, amount, label, full }` or `false, message`.**

**Example**

```lua
local reward = Kora.callback.trigger('qb-hotdogjob:finishPreparing', proof, authorization)
```

**Representative console output**

```text
Quality rolled from `Hotdog.PrepareRewards` (common 70% / rare 25% / exotic 5%); amount from `Hotdog.batchSize(level, quality)`, capped at that quality/level's stock max; grants `cooking` skill XP equal to `Hotdog.PrepareXp[quality] * granted`.
```

#### `Kora.callback.register('qb-hotdogjob:sell', fn)`

Sells carried hot dog stock to an NPC customer within `Hotdog.SaleDistance` (4.0 m).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `netId` | number | Network id of the customer ped/entity. |
| `quality` | string | `common`/`rare`/`exotic`. |
| `amount` | number | Units to sell, must not exceed current stock of that quality. |

**Returns**

- **`{ total, ... }`-shaped success payload (exact fields per `jobs/hotdog/server.lua`) or `false, message`.**

**Example**

```lua
local result = Kora.callback.trigger('qb-hotdogjob:sell', netId, quality, amount)
```

**Representative console output**

```text
Pays cash via `exports.kora_core:addMoney`, priced randomly within `Hotdog.Stock[quality].Price[level]`'s min/max, and grants `cooking` XP (`Hotdog.SaleXp[quality] * amount`).
```

### Limits and related APIs

Because `jobs/hotdog/config.lua` is never required by `config.lua`'s boot loop, the global `Hotdog` table (and `Globals.Hotdog`) does not exist at runtime unless you add the job to `Config.enable` yourself. Every behavior described here is read from source, not observed running.

### Related guides

- [Job toggles and boot](./job-toggles.md)

## Client

Stand placement/pickup (`grab`/`drop` stall), the prepare and sell interactions, and the stock HUD app (`qb-hotdogjob:stock`). Also inactive by default (see server side note).

Namespace: `Hotdog / qb-hotdogjob:*` · Source: `jobs/hotdog/client.lua`

### How it works

Listens for `qb-hotdogjob:client:UpdateReputation` (cooking skill sync), `qb-hotdogjob:client:ToggleSell` (server-driven sell-mode toggle) and `qb-hotdogjob:staff:DeletStand` (admin stand removal via `/removestand`).

### Functions

Net events only; no exports.

### Limits and related APIs

Not loaded by default — see Installation.

### Related guides

- [Job toggles and boot](./job-toggles.md)
