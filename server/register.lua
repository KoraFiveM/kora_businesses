-- Server-side registration of a business's modules.
--
-- Only modules with a server half appear here: a stash to create, a shop and
-- its intake stash, a useable item to bind. Everything visual (zones, blips,
-- targets, props) is created by the client from the replicated definition.
--
-- Registration is idempotent by design, because it re-runs on every edit: a
-- business is re-registered whole rather than diffed, and qbinventory returns
-- the existing inventory for an id it already knows rather than resetting it.

QbBusinesses = QbBusinesses or {}

local State = QbBusinesses.state
local Pos = QbBusinesses.pos
local Crafting = QbBusinesses.crafting

local Register = {}
QbBusinesses.register = Register

---@type table<string, true> item names already bound to a use handler
local useables = {}

---@type table<string, table> stash id -> { businessId, module }
local stashes = {}

local handlers = {}

handlers.Stash = function(business, module)
    stashes[module.id] = { businessId = business.id, module = module }
    exports.qbinventory:RegisterStash(module.id, module.label or business.label, module.slots, module.weight,
        false, module.public and nil or { [business.job] = 0 })
end

handlers.POS = function(business, module)
    Pos.register(business, module)
end

handlers.UseableItem = function(business, module)
    -- A use handler is global to an item name, so binding the same item twice
    -- would leave the second registration shadowing the first with no warning.
    if useables[module.item] then
        print(('^3[qbbusinesses]^7 item "%s" already has a use handler; %s will not rebind it'):format(module.item, business.id))
        return
    end
    useables[module.item] = true
    Crafting.registerUseable(business, module)
end

---@param business table
function Register.business(business)
    for _, module in ipairs(business.modules) do
        local handler = handlers[module.moduleType]
        if handler then
            local ok, err = pcall(handler, business, module)
            if not ok then
                print(('^1[qbbusinesses]^7 could not register %s module of %s: %s'):format(module.moduleType, business.id, tostring(err)))
            end
        end
    end
end

---qbinventory already gates the stash on its own `groups`, so this is not the
---security boundary -- it exists so a player who cannot open a stash is told
---why instead of watching nothing happen.
QB.callback.register('qbbusinesses:server:openStash', function(src, stashId)
    local record = type(stashId) == 'string' and stashes[stashId] or nil
    if not record then return false, 'Unknown stash.' end
    local business = State.get(record.businessId)
    if not business then return false, 'Unknown business.' end
    if not record.module.public and not State.worksFor(src, business.job) then
        return false, 'You do not work here.'
    end
    return exports.qbinventory:stashOpen(src, stashId)
end, { rateLimit = { max = 10, window = 10000 } })
