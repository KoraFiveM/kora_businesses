# qbbusinesses agent guide

Modular businesses stored in MySQL and edited in-game. See `README.md` for what
it does and `docs/index.md` for the module reference. This file is about how to
change it without breaking it.

## Shape

```
config.lua              policy only -- never business definitions
shared/schema.lua       the ONE validator, both realms
shared/{recipes,shopitems,businesses}/   libraries + first-boot seeds
server/state.lua        registry, persistence funnel, replication
server/{logs,staff,pos,crafting,payment}.lua
server/register.lua     server-side half of each module type
server/admin.lua        creator callbacks + resource exports
server/main.lua         boot sequence (loads last)
client/{state,business,payment,creator,main}.lua
```

Server load order is declared file-by-file in `fxmanifest.lua` and is load
bearing: `state` owns the registry every other file captures at load time, and
`main` runs the boot sequence once the rest have registered. `test/smoke/security.lua`
asserts the ordering, so a reshuffle fails rather than nil-indexing at boot.

## Rules

**One validator.** Everything that can become a live definition — a database
row, a seed, a creator payload — goes through `S.normaliseBusiness`. The server
runs it before any write; the client re-runs it only so one malformed module
skips itself instead of erroring the whole business. Never add a second path
that constructs a module by hand.

**One write path.** `State.persist` validates, writes the row, updates the
mirror, then broadcasts, in that order. A failed write leaves both the database
and the live server untouched. Every mutation applies its change to a *copy* of
the module list first, so a rejected edit changes nothing.

**The client supplies intent, never data.** A craft request is
`(businessId, moduleIndex, recipeId)`; the recipe itself is looked up in shared
config, and only if the bench being used actually offers it. The moment a
callback starts accepting a table of gameplay values, that is a bug.

**Every server callback carries a `rateLimit`.** They all read the database,
open a dialog or move money. `test/smoke/security.lua` counts registrations
against limits and fails if the two ever diverge.

**Shop stock belongs to qbinventory.** This resource owns pricing policy and
who may open what; qbinventory owns the shelf and persists it. Do not add a
stock table here — `test/smoke/contract.lua` fails if one appears.

## Threading

`QB.zones`' tick and qbtarget's target loop are **shared across every resource
on the server**. Both invoke callbacks this resource supplies, and nearly
everything here yields — streaming a prop, opening a dialog, calling the
server. Yielding in one of those callbacks stalls every zone or every target in
the server, not just ours.

So: `Business:enter`/`leave` flip their guard flag synchronously and hand the
work to a `CreateThread`, and `Business:attach` wraps every option's `onSelect`
the same way before registering it. `generation` is bumped on both, and the
build thread checks it before finishing so a player who walks straight back out
does not leave orphaned props and target registrations behind.

There is no `cache` and no `lib` global here — those are ox_lib. Use
`PlayerPedId()` / `GetVehiclePedIsIn` and `QB.*`. `test/smoke/client.lua` greps
for both.

## Replication

A sync is a full replacement, not a diff, and the client rebuilds a business
only when its `rev` changes. `rev` is an FNV-1a fingerprint computed **server
side** in `State.persist`/`State.load` — comparing encoded tables client-side
would not work, because `json.encode` gives no key-order guarantee and two
encodes of the same table can differ.

## Adding a module type

1. Add a descriptor to `S.moduleTypes` (`interaction`, and `startup` if it must
   exist before the player arrives) and a `payloads.<Type>` validator.
2. Add a `builders.<Type>` to `client/business.lua` returning target options, or
   `nil` if it has no interaction.
3. Add a `handlers.<Type>` to `server/register.lua` if it needs a server-side
   registration (an inventory, a use handler).
4. Add a `fieldsFor.<Type>` to `client/creator.lua` so it can be built in-game.
5. Extend `test/smoke/schema.lua`.

Steps 1 and 4 are the ones people forget. A type with no `fieldsFor` entry
errors when an admin picks it out of the module menu.

## Coordinates

Definitions are JSON: `{ x, y, z, w? }` tables, never vectors, never functions.
They are converted with `Client.vec3`/`Client.vec4` at the point of use. A
module's `coords` is a single table for a zone and an **array** for entities —
`S.coords` wraps a lone coordinate so the client never has to branch on which
form arrived.

## Tests

`test/run.sh` (plain Lua 5.4, no FiveM, no database). The schema and the shipped
seeds are exercised for real. `security.lua`, `contract.lua` and `client.lua`
read the source and assert the invariants above are actually written down —
that is the only way to check "never yields on the target thread" without a
running server. Update them in the same change as the code.

## Sibling-resource additions this build needed

* `qbinventory`: `shopGet`/`shopSet` (`GetShopItems`/`SetShopItems`). Shop stock
  could be seeded at registration and never changed afterwards — `RegisterShop`
  only seeds a shop that was not restored, and the transfer path refuses shop
  inventories outright.
* `qbbossmenu`: `removeBusinessMoney`, the mirror of `addBusinessMoney`, so a
  commission can be paid out of the company account.
* `qbbossmenu`: its `openStash` callback called `exports.qbinventory:openInventory`,
  which is a **client-realm** export — the server realm has `OpenInventory` and
  `stashOpen`. Fixed to `stashOpen`.
