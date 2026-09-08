-- Business/module schema, shared by both realms.
--
-- Definitions are user data: they arrive from the database, from a seed file,
-- or from an admin building one in-game, and they are replicated to every
-- client. So there is exactly ONE validator, it lives here, and the server runs
-- it before anything is written or broadcast. The client re-runs it on receipt
-- purely so a malformed row skips one module instead of erroring the whole
-- business setup.
--
-- Everything in a definition is plain JSON-safe data: no vectors, no functions.
-- Coordinates are `{ x, y, z, w? }` tables and are converted to vectors at the
-- point of use on the client.

QbBusinesses = QbBusinesses or {}

local S = {}
QbBusinesses.schema = S

local MAX_POLY_POINTS = 64
local MAX_ENTITY_COORDS = 32
local BLIP_CATEGORY_IDS = QB.blips.getCategoryIds()

---@param value any
---@param maxLength? integer
---@return string|nil
local function str(value, maxLength)
    if type(value) ~= 'string' then return nil end
    local trimmed = value:gsub('^%s+', ''):gsub('%s+$', '')
    if trimmed == '' then return nil end
    return trimmed:sub(1, maxLength or 128)
end

---@param value any
---@param min? number
---@param max? number
---@return number|nil
local function num(value, min, max)
    local n = tonumber(value)
    if not n or n ~= n then return nil end
    if min and n < min then return nil end
    if max and n > max then return nil end
    return n + 0.0
end

local function int(value, min, max)
    local n = num(value, min, max)
    return n and math.floor(n) or nil
end

local function bool(value) return value == true end

---@param value any
---@return string|nil
local function blipCategory(value)
    local name = str(value, 64) or 'Business'
    return BLIP_CATEGORY_IDS[name] and name or nil
end

S.str, S.num, S.int, S.bool = str, num, int, bool

---Lowercase, punctuation-free identifier derived from a label.
---@param text string
---@return string|nil
function S.slug(text)
    local base = str(text, 64)
    if not base then return nil end
    local slug = base:lower():gsub('[^%w]+', '_'):gsub('^_+', ''):gsub('_+$', '')
    if slug == '' then return nil end
    return slug:sub(1, 64)
end

---Accepts `{x=,y=,z=,w=}`, `{x,y,z,w}` or a serialised vector3/vector4.
---@param value any
---@return table|nil
function S.coords(value)
    if type(value) ~= 'table' then return nil end
    local x, y, z = num(value.x or value[1]), num(value.y or value[2]), num(value.z or value[3])
    if not x or not y or not z then return nil end
    local w = num(value.w or value.heading or value[4]) or 0.0
    return { x = x, y = y, z = z, w = w % 360.0 }
end

-- ---------------------------------------------------------------------------
-- Module types
-- ---------------------------------------------------------------------------

---`interaction` says what kinds of world anchor a module accepts:
---  `none`  -- it has no in-world interaction at all
---  `zone`  -- a trigger volume only (never a target option)
---  `model` -- a spawned or existing entity only
---  `any`   -- a target zone or a target entity, the builder picks
---
---`startup` modules are created as soon as a business is known. Everything else
---is created lazily when the player enters the business's Zone, and torn down
---again on exit -- a server with fifty businesses should not hold fifty tills'
---worth of targets and props in memory at once. A business with no Zone module
---has nothing to trigger that, so all of its modules are treated as startup.
S.moduleTypes = {
    { type = 'Zone',         label = 'Zone (business perimeter)', interaction = 'zone',  startup = true },
    { type = 'Blip',         label = 'Map blip',                  interaction = 'none',  startup = true },
    { type = 'StaticEntity', label = 'Static prop / ped',         interaction = 'model' },
    { type = 'BossMenu',     label = 'Boss menu',                 interaction = 'any' },
    { type = 'POS',          label = 'Point of sale (till)',      interaction = 'any' },
    { type = 'Stash',        label = 'Stash',                     interaction = 'any' },
    { type = 'Crafting',     label = 'Crafting bench',            interaction = 'any' },
    { type = 'UseableItem',  label = 'Useable item',              interaction = 'none',  serverOnly = true },
}

S.moduleType = {}
for _, entry in ipairs(S.moduleTypes) do S.moduleType[entry.type] = entry end

-- ---------------------------------------------------------------------------
-- Interaction anchors
-- ---------------------------------------------------------------------------

local zoneValidators = {
    sphere = function(mod, out)
        out.radius = num(mod.radius, 0.1, 100.0) or 1.5
        return true
    end,
    box = function(mod, out)
        local size = type(mod.size) == 'table' and mod.size or nil
        local x = size and num(size.x or size[1], 0.05, 200.0)
        local y = size and num(size.y or size[2], 0.05, 200.0)
        local z = size and num(size.z or size[3], 0.05, 200.0)
        if not x or not y or not z then return false, 'box modules need a size' end
        out.size = { x = x, y = y, z = z }
        out.rotation = num(mod.rotation) or 0.0
        return true
    end,
    poly = function(mod, out)
        if type(mod.points) ~= 'table' then return false, 'poly modules need points' end
        local points = {}
        for _, raw in ipairs(mod.points) do
            local point = S.coords(raw)
            if not point then return false, 'a poly point is malformed' end
            points[#points + 1] = { x = point.x, y = point.y, z = point.z }
            if #points > MAX_POLY_POINTS then return false, 'too many poly points' end
        end
        if #points < 3 then return false, 'poly modules need at least 3 points' end
        out.points = points
        out.thickness = num(mod.thickness, 0.1, 100.0) or 4.0
        return true
    end,
}

local modelTypes = { ped = true, object = true, vehicle = true }

---@return table|nil model, string|nil err
local function normaliseModel(raw)
    if type(raw) ~= 'table' then return nil end
    local name = str(raw.model, 64)
    if not name then return nil, 'a model anchor needs a model name' end
    local kind = str(raw.modelType, 16)
    kind = kind and kind:lower() or 'object'
    if not modelTypes[kind] then return nil, 'modelType must be ped, object or vehicle' end
    local model = { model = name, modelType = kind, existing = bool(raw.existing) }
    if type(raw.anim) == 'table' then
        local dict, clip = str(raw.anim.dict, 96), str(raw.anim.clip, 96)
        if dict and clip then model.anim = { dict = dict, clip = clip, flag = int(raw.anim.flag, 0) or 1 } end
    end
    if raw.freeze ~= nil then model.freeze = bool(raw.freeze) end
    return model
end

---Validates whatever world anchor a module carries and copies it onto `out`.
---@return boolean ok, string|nil err
local function normaliseAnchor(mod, out, allowed)
    if allowed == 'none' then return true end

    local zoneType = str(mod.zoneType, 16)
    zoneType = zoneType and zoneType:lower() or nil

    if zoneType and allowed == 'model' then return false, 'this module type only accepts an entity anchor' end
    if mod.model and allowed == 'zone' then return false, 'this module type only accepts a zone anchor' end

    if zoneType then
        local validator = zoneValidators[zoneType]
        if not validator then return false, 'zoneType must be sphere, box or poly' end
        local coords = S.coords(mod.coords)
        if not coords then return false, 'this module needs coords' end
        out.zoneType, out.coords = zoneType, coords
        local ok, err = validator(mod, out)
        if not ok then return false, err end
        return true
    end

    local model, modelErr = normaliseModel(mod.model)
    if modelErr then return false, modelErr end
    if model then
        -- One module may place the same prop at several spots (a row of tills).
        local list = mod.coords
        if type(list) ~= 'table' then return false, 'this module needs coords' end
        -- A single coordinate is accepted unwrapped, whether it arrived as
        -- `{x=,y=,z=}` or as a bare `{x, y, z}` array.
        if list.x ~= nil or (list[1] ~= nil and type(list[1]) ~= 'table') then list = { list } end
        local coords = {}
        for _, raw in ipairs(list) do
            local point = S.coords(raw)
            if not point then return false, 'a model coordinate is malformed' end
            coords[#coords + 1] = point
            if #coords > MAX_ENTITY_COORDS then return false, 'too many model coordinates' end
        end
        if #coords == 0 then return false, 'this module needs coords' end
        out.model, out.coords = model, coords
        return true
    end

    if allowed == 'zone' then return false, 'this module needs a zone anchor' end
    if allowed == 'model' then return false, 'this module needs an entity anchor' end
    return false, 'this module needs a zone or entity anchor'
end

---@param raw any
---@return table|nil
local function normaliseBlip(raw)
    if type(raw) ~= 'table' or raw.enabled == false then return nil end
    local category = blipCategory(raw.category)
    if not category then return nil end
    return {
        enabled = true,
        sprite = int(raw.sprite, 0, 900) or 1,
        color = int(raw.color, 0, 90) or 1,
        scale = num(raw.scale, 0.1, 3.0) or 0.7,
        display = int(raw.display, 0, 11) or 4,
        category = category,
        -- `label` is the pre-category/name field used by persisted definitions
        -- from before qblib composed display labels itself.
        name = str(raw.name, 64) or str(raw.label, 64),
        shortRange = raw.shortRange ~= false,
        coords = S.coords(raw.coords),
    }
end

-- ---------------------------------------------------------------------------
-- Per-type payloads
-- ---------------------------------------------------------------------------

---@type table<string, fun(mod: table, out: table): boolean, string|nil>
local payloads = {}

payloads.Zone = function(mod, out)
    -- `controlDuty` defaults ON: a perimeter that does not clock you in is the
    -- unusual case, not the common one.
    out.controlDuty = mod.controlDuty ~= false
    return true
end

payloads.Blip = function(mod, out)
    local coords = S.coords(mod.coords)
    if not coords then return false, 'a blip needs coords' end
    out.coords = coords
    out.sprite = int(mod.sprite, 0, 900) or 1
    out.color = int(mod.color, 0, 90) or 1
    out.scale = num(mod.scale, 0.1, 3.0) or 0.7
    out.display = int(mod.display, 0, 11) or 4
    out.shortRange = mod.shortRange ~= false
    out.category = blipCategory(mod.category)
    if not out.category then return false, 'unknown blip category' end
    out.name = str(mod.name, 64) or str(mod.label, 64)
    return true
end

payloads.StaticEntity = function() return true end
payloads.BossMenu = function() return true end

payloads.Stash = function(mod, out)
    local id = S.slug(mod.id)
    if not id then return false, 'a stash needs an id' end
    out.id = id
    out.slots = int(mod.slots, 1, 500) or (Config and Config.stash and Config.stash.slots) or 50
    out.weight = int(mod.weight, 1000, 100000000) or (Config and Config.stash and Config.stash.weight) or 1000000
    return true
end

payloads.POS = function(mod, out)
    local id = S.slug(mod.id)
    if not id then return false, 'a till needs an id' end
    out.id = id

    -- `items` names entries in Config.shopItems. A list restricts what may be
    -- stocked AND fixes the price. No list at all means "anything, employee
    -- sets the price" -- deliberately opt-in, since it is the looser policy.
    out.items = {}
    if mod.items ~= nil then
        if type(mod.items) ~= 'table' then return false, 'till items must be a list of shop-item list names' end
        for _, entry in ipairs(mod.items) do
            local name = str(entry, 64)
            if not name then return false, 'a till item list name is malformed' end
            out.items[#out.items + 1] = name
        end
    end

    -- A percentage outside 0-100 is a typo, and silently reading it as 0 would
    -- hide a business quietly collecting no tax. Reject it and say so.
    out.commission = mod.commission == nil and 0.0 or num(mod.commission, 0, 100)
    if not out.commission then return false, 'commission must be between 0 and 100' end
    out.tax = mod.tax == nil and 0.0 or num(mod.tax, 0, 100)
    if not out.tax then return false, 'tax must be between 0 and 100' end
    out.panicButton = bool(mod.panicButton)
    -- Customers cannot open the till themselves while an employee is standing
    -- in the business -- serve them, do not let them self-checkout past you.
    out.hideWhenStaffed = bool(mod.hideWhenStaffed)
    out.currency = (str(mod.currency, 16) or (Config and Config.pos and Config.pos.currency) or 'cash'):lower()
    if out.currency ~= 'cash' and out.currency ~= 'bank' then return false, 'till currency must be cash or bank' end
    out.shopSlots = int(mod.shopSlots, 1, 500) or (Config and Config.pos and Config.pos.shopSlots) or 50
    out.stockSlots = int(mod.stockSlots, 1, 500) or (Config and Config.pos and Config.pos.stockSlots) or 50
    out.webhook = str(mod.webhook, 512)
    return true
end

payloads.Crafting = function(mod, out)
    if type(mod.recipes) ~= 'table' then return false, 'a crafting bench needs recipes' end
    out.recipes = {}
    for _, entry in ipairs(mod.recipes) do
        local name = str(entry, 64)
        if not name then return false, 'a recipe reference is malformed' end
        out.recipes[#out.recipes + 1] = name
    end
    if #out.recipes == 0 then return false, 'a crafting bench needs at least one recipe' end
    return true
end

local useTypes = { reward = true, recipe = true }

payloads.UseableItem = function(mod, out)
    local item = str(mod.item, 64)
    if not item then return false, 'a useable item needs an item name' end
    out.item = item:lower()
    out.consume = int(mod.consume, 0, 100) or 1
    out.useType = (str(mod.useType, 16) or 'reward'):lower()
    if not useTypes[out.useType] then return false, 'useType must be reward or recipe' end

    if out.useType == 'recipe' then
        local recipe = str(mod.recipe, 64)
        if not recipe then return false, 'a recipe useable needs a recipe id' end
        out.recipe = recipe
        return true
    end

    if type(mod.rewards) ~= 'table' then return false, 'a reward useable needs a rewards pool' end
    out.rewards = {}
    for _, raw in ipairs(mod.rewards) do
        local name = type(raw) == 'table' and str(raw.item or raw.name, 64) or nil
        local amount = type(raw) == 'table' and int(raw.amount or raw.count, 1, 1000) or nil
        local chance = type(raw) == 'table' and num(raw.chance, 0.0001, 1000000) or nil
        if not name then return false, 'a reward entry needs an item' end
        out.rewards[#out.rewards + 1] = { item = name:lower(), amount = amount or 1, chance = chance or 1.0 }
    end
    if #out.rewards == 0 then return false, 'a reward useable needs at least one reward' end
    out.rolls = int(mod.rolls, 1, 20) or 1
    return true
end

-- ---------------------------------------------------------------------------
-- Public entry points
-- ---------------------------------------------------------------------------

---@param raw any
---@return table|nil module, string|nil err
function S.normaliseModule(raw)
    if type(raw) ~= 'table' then return nil, 'a module must be a table' end
    local kind = str(raw.moduleType, 32)
    local descriptor = kind and S.moduleType[kind]
    if not descriptor then return nil, ('unknown module type: %s'):format(tostring(raw.moduleType)) end

    local out = {
        moduleType = kind,
        label = str(raw.label, 64) or (kind == 'Blip' and str(raw.name, 64)) or descriptor.label,
        icon = str(raw.icon, 48),
        public = bool(raw.public),
        distance = num(raw.distance, 0.5, 20.0) or 2.0,
    }

    local ok, err = normaliseAnchor(raw, out, descriptor.interaction)
    if not ok then return nil, err end

    local blip = normaliseBlip(raw.blip)
    if blip then
        -- A module's blip falls back to the module's own anchor when the
        -- builder did not place one separately.
        if not blip.coords then
            blip.coords = out.zoneType and out.coords or (out.coords and out.coords[1])
        end
        if blip.coords then
            blip.name = blip.name or out.label
            out.blip = blip
        end
    end

    ok, err = payloads[kind](raw, out)
    if not ok then return nil, err end
    return out
end

---@param raw any
---@return table|nil business, string|nil err
function S.normaliseBusiness(raw)
    if type(raw) ~= 'table' then return nil, 'a business must be a table' end
    local id = S.slug(raw.id or raw.label)
    if not id then return nil, 'a business needs an id' end
    local label = str(raw.label, 64) or id
    local job = str(raw.job, 64)
    if not job then return nil, 'a business needs a job' end

    local business = { id = id, label = label, job = job:lower(), modules = {}, rejected = {} }
    if type(raw.modules) == 'table' then
        for index, rawModule in ipairs(raw.modules) do
            local module, err = S.normaliseModule(rawModule)
            if module then
                business.modules[#business.modules + 1] = module
            else
                business.rejected[#business.rejected + 1] = { index = index, err = err }
            end
        end
    end
    return business
end

---Modules created eagerly, before the player has entered the business.
---@param business table
---@return boolean
function S.hasPerimeter(business)
    for _, module in ipairs(business.modules or {}) do
        if module.moduleType == 'Zone' then return true end
    end
    return false
end

---@param business table
---@param module table
---@return boolean
function S.isStartupModule(business, module)
    if not S.hasPerimeter(business) then return true end
    local descriptor = S.moduleType[module.moduleType]
    return descriptor ~= nil and descriptor.startup == true
end

return S
