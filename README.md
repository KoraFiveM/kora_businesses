# qbbusinesses

Modular, database-backed businesses for the qblib framework. A business is a
job, a perimeter, and a stack of **modules** — a till, a stash, a crafting
bench, a boss desk, a prop — and every one of them is built in-game and stored
in MySQL. There is no config file to edit, no snippet to paste, and no restart:
what you build appears for every player on the server as you build it.

Inspired by [`jay-businesses`](https://github.com/Jay60Dev/jay-businesses),
rewritten from scratch on qblib / qbcore / qbsql / qbinventory / qbtarget.

---

## Install

1. Drop `qbbusinesses` into your resources folder.
2. Start it **after** `qblib`, `qbsql`, `qbcore`, `qbinventory` and `qbtarget`:

```cfg
ensure qbbusinesses
```

The migration runs itself on first boot. `qbbossmenu` (business bank account)
and `qbdispatch` (panic button) are optional — the resource starts and runs
without either, and says so when you try to use a feature that needs one.

A demo **Burger Shot** is seeded on first boot so there is something to look at,
along with the `burgershot` job it needs — registered only if your server does
not already define one. Delete the business in-game and it stays deleted; seeds
never come back.

---

## Building a business

`/business` — admins see everything, a boss sees their own business.

```
Businesses
  + Create a business          -> name + job, then straight into modules
  Burger Shot                  -> Modules / Activity / Balance / Rename / Delete
```

Adding a module asks three things: **what** it is, **where** it is, and whether
it wants a map blip. "Where" is never typed in:

| Anchor | Tool |
|---|---|
| Sphere / box / poly zone | qblib's in-world zone creator — fly, aim, place, scroll to size |
| Prop / ped / vehicle | qblib's placement tool — position it, then confirm |
| An object already there | Look at it and press `E`; a box zone is fitted to its model |

Saving pushes the row to MySQL and the new definition to every connected
client. The till exists for everyone about two frames later.

---

## Modules

| Module | What it does |
|---|---|
| **Zone** | The business perimeter. Entering builds everything below and clocks staff on; leaving tears it down and clocks them off. |
| **Blip** | A map marker. |
| **StaticEntity** | Decorative props, peds or vehicles with no interaction. |
| **BossMenu** | Opens `qbbossmenu` for a boss of this job. |
| **POS** | A customer-facing till, an employee-facing intake stash, prices, tax, sold-stock commission and an optional panic button. |
| **Stash** | Job-locked storage. |
| **Crafting** | A bench offering recipes from the shared recipe library, with live ingredient counts and optional skill gates. |
| **UseableItem** | Binds an item to a weighted reward roll or to a recipe — mystery boxes, ingredient packs. |

Every module with a world anchor may be a **zone** or an **entity**, may carry
its own blip, and may be marked `public` to drop its job lock.

### How a till works

Stock is **not** stored by this resource — qbinventory already owns a shop
inventory and persists it, and a second copy of the same shelf is exactly the
bug worth avoiding. What this resource owns is the policy around it.

```
employee                          customer
   |                                  |
   v                                  v
[intake stash] --close--> [shelf] --buy--> money
                            ^                |
                     price policy      minus tax -> business account
```

* An employee drops goods in the **intake stash**. Closing it moves everything
  onto the shelf in one go — one price prompt per item type, not one per drag.
* A price comes from the till's `Config.shopItems` list if that list fixes one,
  otherwise from what the till was last told, otherwise the employee is asked.
  What they answer is remembered for next time.
* A **sold-stock commission** (`%` of committed sale revenue) is attributed to
  the employee who stocked that batch. Merely stocking or naming a price pays
  nothing. When a customer actually buys it, the business receives the sale and
  the online stocker is paid from that revenue.
* A sale credits the business account with the price minus **tax**, and is
  credited from qbinventory's committed purchase record — never from a
  pre-commit hook, which would pay out for sales that then fail.
* `hideWhenStaffed` stops customers self-serving while an employee is inside.
  Staff presence means an on-duty employee whose live server position remains
  inside the configured business perimeter.

### The card machine

Anyone carrying `Config.payment.item` (default `cardmachine`) can target a
player and bill them. The employee names the amount, the customer approves it,
the customer's bank is debited, the employee keeps a commission and the rest
goes to the business account. The distance between the two is re-checked
**after** both dialogs — walking away mid-transaction cancels it — and if the
business account turns out to be unreachable the customer is refunded rather
than the money vanishing.

---

## Configuration

`config.lua` holds policy: permissions, defaults, rates, webhooks, and the
optional skill adapter. Business *definitions* are not configured there.

* `shared/recipes/*.lua` — the recipe library. Written once, referenced by id
  from any number of benches.
* `shared/shopitems/*.lua` — named item lists a till may reference. An entry
  with a `price` is fixed at that price; one without is employee-priced.
* `shared/businesses/*.lua` — first-boot seeds. Inserted only when no business
  with that id exists, so in-game edits and deletions always win. A seed may
  also carry a `jobDefinition`, registered at boot when no job of that name
  exists yet — qbcore's job registry is in-memory, so this is re-checked every
  start, and a server that defines its own version of the job always wins.

### Skills

Off by default. `Config.skills.enabled = true` turns on the `levelRequired` and
`xpGained` fields on recipes, using `getLevel`/`addXp` adapters that default to
qbcore metadata. Point them at your own skill resource if you have one.

### Discord

`Config.webhooks.default` receives every business event; a `[jobname]` key
receives that job's as well, and a POS module may name a third URL of its own.
All of it also lands in `qbbusinesses_logs` and in qblib's own event log
regardless of whether any webhook is configured.

---

## Exports

```lua
-- server
exports.qbbusinesses:getBusinesses()             -- every definition
exports.qbbusinesses:getBusiness(id)
exports.qbbusinesses:getBusinessesByJob(job)     -- ids
exports.qbbusinesses:getStaffCounts()            -- businessId -> staff inside
exports.qbbusinesses:recordBusinessLog(id, category, message, amount)

-- client
exports.qbbusinesses:getBusinesses()
exports.qbbusinesses:openBusinessMenu()
```

---

## Tables

| Table | Holds |
|---|---|
| `qbbusinesses` | One row per business: label, job, and its modules as JSON. |
| `qbbusinesses_prices` | Employee-set prices, remembered per till and item. |
| `qbbusinesses_logs` | Sales, restocks, payments, crafts and admin edits. |

Shop stock and stash contents live in qbinventory's own tables.

---

## Tests

```sh
test/run.sh          # LUA=lua5.4 test/run.sh to pick an interpreter
```

Plain Lua, no FiveM and no database. The schema is exercised for real; the
server and client files are checked against the invariants that matter —
authorisation, rate limits, rollbacks, and the threading rules around qblib's
shared zone tick and qbtarget's shared target loop.
