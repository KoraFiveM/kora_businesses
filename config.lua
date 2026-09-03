-- qbbusinesses configuration.
--
-- Business DEFINITIONS are not configured here -- they live in the database and
-- are built in-game (see `shared/businesses/` for optional first-boot seeds).
-- What lives here is server policy: permissions, defaults, rates, and the
-- reusable recipe / shop-item libraries a business definition refers to by name.

Config = {}

---Draws every zone and target this resource creates.
Config.debug = false

---Permission required to create, edit or delete a business in-game.
---Checked with `exports.qbcore:hasPermission`.
Config.adminPermission = 'admin'

---Chat command that opens the business menu (admin) / the nearest business's
---own management menu (boss).
Config.command = 'business'

Config.notifyTitle = 'Business'

Config.pos = {
    ---Slots/weight of the customer-facing shop inventory.
    shopSlots = 50,
    shopWeight = 1000000,
    ---Slots/weight of the employee-facing intake stash goods are dropped into.
    stockSlots = 50,
    stockWeight = 1000000,
    ---Account customers pay from. `cash` or `bank`.
    currency = 'cash',
    ---Hard cap on any price an employee may set, so a typo cannot create a
    ---multi-million dollar till entry.
    maxPrice = 1000000,
}

Config.stash = {
    slots = 50,
    weight = 1000000,
}

---Portable card machine: an item that lets an employee bill a nearby player.
Config.payment = {
    item = 'cardmachine',
    ---Fraction of every manual payment paid to the employee who took it.
    commission = 0.10,
    ---Both players must be within this many metres of each other.
    distance = 5.0,
    maxAmount = 1000000,
    ---Account the customer is billed from.
    account = 'bank',
}

---Panic button on a POS module.
Config.panic = {
    jobTypes = { 'leo' },
    code = '10-90',
    priority = 1,
    icon = 'Siren',
}

---Automatic on/off duty when entering or leaving a business zone. A module may
---still opt out individually with `controlDuty = false`.
Config.duty = {
    enabled = true,
    ---Skip auto-off-duty when the player leaves in a vehicle whose plate starts
    ---with the job's first three characters -- they are on a call, not clocking off.
    keepDutyInJobVehicle = true,
}

---Discord webhooks. `default` receives everything; a per-job key receives that
---job's business events as well. Empty strings are skipped.
Config.webhooks = {
    default = '',
}

Config.logs = {
    ---Rows kept per business in `qbbusinesses_logs`; older rows are trimmed.
    retain = 500,
}

---Optional skill gating on crafting recipes. Disabled by default so no skill
---resource is required. `getLevel` runs SERVER-side and must return a number.
Config.skills = {
    enabled = false,
    ---@param src integer
    ---@param skill string
    ---@return number
    getLevel = function(src, skill)
        local skills = exports.qbcore:getMetaData(src, 'skills')
        local record = type(skills) == 'table' and skills[skill] or nil
        return type(record) == 'table' and tonumber(record.level) or tonumber(record) or 0
    end,
    ---@param src integer
    ---@param skill string
    ---@param amount number
    addXp = function(src, skill, amount)
        local skills = exports.qbcore:getMetaData(src, 'skills')
        if type(skills) ~= 'table' then skills = {} end
        local record = type(skills[skill]) == 'table' and skills[skill] or { level = 0, xp = 0 }
        record.xp = (tonumber(record.xp) or 0) + amount
        skills[skill] = record
        exports.qbcore:setMetaData(src, 'skills', skills)
    end,
}

---Reusable recipe library, keyed by id. Populated by `shared/recipes/*.lua`.
---A Crafting module refers to these by id, so the same recipe is written once.
Config.recipes = {}

---Reusable shop item lists, keyed by list name. Populated by
---`shared/shopitems/*.lua`. A POS module refers to these by name. An item in a
---list has a FIXED price -- an employee restocking it cannot reprice it.
Config.shopItems = {}

---First-boot seeds, populated by `shared/businesses/*.lua`. A seed is inserted
---only if no row with that id exists yet; it never overwrites in-game edits.
Config.seeds = {}
