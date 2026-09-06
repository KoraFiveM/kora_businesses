# qbbusinesses module reference

Every module shares a common shape, then adds its own fields. All of it is
plain JSON — no vectors, no functions — because a definition travels from MySQL
to the server to every client.

## Common fields

| Field | Type | Notes |
|---|---|---|
| `moduleType` | string | Required. One of the types below. |
| `label` | string | Shown on the target option. Defaults to the type's own name. |
| `icon` | string | Lucide icon key. |
| `public` | boolean | Drops the job lock on this module's target options. |
| `distance` | number | Interaction distance, 0.5–20. Defaults to 2.0. |
| `blip` | table | `{ enabled, label, sprite, color, scale, display, shortRange, coords? }`. Falls back to the module's own anchor when `coords` is omitted. |

## Anchors

A module is anchored to a **zone** or to **entities**. Which of the two are
allowed depends on the type.

**Zone** — `zoneType` is `sphere`, `box` or `poly`.

| `zoneType` | Fields |
|---|---|
| `sphere` | `coords`, `radius` (0.1–100, default 1.5) |
| `box` | `coords`, `size` `{x,y,z}`, `rotation` (degrees, default 0) |
| `poly` | `points` (3–64 `{x,y,z}`), `thickness` (default 4.0), `coords` (anchor for blips/distance) |

**Entity** — `model = { model, modelType, existing?, anim?, freeze? }` plus
`coords`, which is an array (one module may place a row of the same prop, up to
32). `modelType` is `ped`, `object` or `vehicle`. `existing = true` adopts a
prop the mapper already placed within 1.5m instead of spawning one. `anim` is
`{ dict, clip, flag }` and applies to peds.

## Types

### `Zone` — the perimeter
Zone anchor only. `controlDuty` (default `true`) clocks staff on when they walk
in and off when they leave. This is the module that makes every other module in
the business lazy: without one, everything is built as soon as the business is
known.

### `Blip` — a map marker
No anchor. `coords`, `sprite`, `color`, `scale`, `display`, `shortRange`.

### `StaticEntity` — decoration
Entity anchor only. No interaction.

### `BossMenu`
Either anchor. Opens `qbbossmenu` for a boss of this job; invisible to everyone
else.

### `POS` — a till
Either anchor.

| Field | Notes |
|---|---|
| `id` | Shop id. Two modules may share one to make a row of registers. |
| `items` | Names of `Config.shopItems` lists. Restricts what may be stocked and fixes prices. Omit to allow any item at employee-set prices. |
| `commission` | 0–100. Percent of committed sale revenue paid to the online employee who stocked that batch. Stocking alone never pays. |
| `tax` | 0–100. Percent of each sale withheld from the business account. |
| `hideWhenStaffed` | Customers cannot self-serve while an employee is inside the business. |
| `panicButton` | Adds a silent alarm option, routed through `qbdispatch`. |
| `currency` | `cash` or `bank`. |
| `shopSlots`, `stockSlots` | Shelf and intake stash sizes. |
| `webhook` | A Discord URL for this till specifically, on top of the business's own. |

A percentage outside 0–100 is **rejected**, not clamped: silently reading a
mistyped tax as 0 would leave a business quietly collecting nothing.

### `Stash`
Either anchor. `id`, `slots`, `weight`. Job-locked unless `public`.
Stash and till inventories are bound server-side to every coordinate carried by
their module (including rows of entity fixtures), and their active lease is
closed if the player moves away.

### `Crafting`
Either anchor. `recipes` — an array of ids from `Config.recipes`. The menu shows
live ingredient counts and greys out what cannot be made. The server re-checks
that the recipe is one this bench offers, that the ingredients are present, and
that the player is within 8m, whatever the client claims.

### `UseableItem`
No anchor — it is bound to an item, not a place.

| Field | Notes |
|---|---|
| `item` | Item name. Bound once globally; a second module binding the same item is refused with a warning. |
| `consume` | Items taken per use (default 1, may be 0). Refunded if the outcome fails. |
| `useType` | `reward` or `recipe`. |
| `rewards` | `reward`: `{ item, amount, chance }` — `chance` is a relative weight. |
| `rolls` | `reward`: how many picks per use (default 1). |
| `recipe` | `recipe`: the `Config.recipes` id to run. |

## Recipes

```lua
Config.recipes['bs_burger'] = {
    label = 'Bleeder burger',
    time = 6000,                     -- progress bar ms; omit for instant
    progressLabel = 'Building a burger',
    completeLabel = 'One Bleeder, ready to go.',
    anim = { dict = '...', clip = '...', flag = 1 },
    ingredients = { { item = 'beef', amount = 1 } },
    give = { { item = 'burger', amount = 1 } },
    levelRequired = { { skill = 'cooking', level = 2 } },  -- Config.skills only
    xpGained = { { skill = 'cooking', xp = 10 } },         -- Config.skills only
}
```

Ingredient removal is all-or-nothing: a failure part-way through puts back
everything already taken.

## Shop item lists

```lua
Config.shopItems['burgershot'] = {
    { item = 'burger', price = 12 },  -- fixed: nobody can reprice it
    { item = 'sprunk' },              -- allowed, priced by whoever stocks it
}
```

## Seeds

A file in `shared/businesses/` appends to `Config.seeds`. Each entry is an
ordinary business definition, plus one seed-only extra:

```lua
Config.seeds[#Config.seeds + 1] = {
    id = 'burgershot', label = 'Burger Shot', job = 'burgershot',
    jobDefinition = {                      -- optional, seed-only
        label = 'Burger Shot', type = 'civ',
        grades = { { name = 'Trainee', payment = 30 }, { name = 'Manager', payment = 85, isboss = true } },
    },
    modules = { ... },
}
```

The **business** is inserted only when no row with that id exists — deleting or
editing it in-game always wins. The **job** is a separate matter: qbcore's job
registry is in-memory and rebuilt from its own seed files each start, so it is
re-checked on every boot and registered whenever the name is absent. A server
that defines its own `burgershot` keeps it.
