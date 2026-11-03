local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'
local callbacks, events, hooks = {}, {}, {}
local now, additions, zone = 0, 0, 'drop'
local reentered = false
local lockdown, networkedConfig = 'strict', true
local function granted(result) return type(result) == 'table' end
local env
env = setmetatable({
    source = 1,
    Recycle = setmetatable({ DropLocation = 'drop', DeliveryActionDuration = 5000, PickupLocations = { { loc = 'pickup' } } },
        { __index = function(_, key) if key == 'CarryPropNetworked' then return networkedConfig end end }),
    GetConvar = function(name, default) if name == 'sv_entityLockdown' then return lockdown end return default end,
    Kora = {
        callback = { register = function(name, fn) callbacks[name] = fn end },
        distance = { player = function(_, coords) return zone == coords end },
    },
    exports = {
        kora_inventory = { addItem = function() additions = additions + 1; return true end },
    },
    RegisterNetEvent = function(name, fn) events[name] = fn end,
    AddEventHandler = function(name, fn) hooks[name] = fn end,
    GetGameTimer = function() return now end,
    Wait = function()
        if not reentered then
            reentered = true
            events['kora_businesses:recycle:getItem']()
        end
    end,
    math = setmetatable({ random = function(low) return low end }, { __index = math }),
}, { __index = _G })
assert(loadfile(root .. 'jobs/recycle/server.lua', 't', env))()
local redeem = events['kora_businesses:recycle:getItem']
redeem()
now = 10000
redeem()
assert(additions == 0, 'standing at hand-in must not authorize rewards, even after the cooldown')

local pickup = assert(callbacks['kora_businesses:recycle:pickupPackage'])
assert(pickup(1, 1) == false, 'pickup requires a visit to the configured package location')
zone = 'pickup'
assert(pickup(1, '1') == false and pickup(1, 1.5) == false and pickup(1, 2) == false)
local first = pickup(1, 1)
assert(granted(first) and pickup(1, 1) == false, 'only one package can be pending')
assert(first.networked == false, 'strict entity lockdown never asks the client for a networked carry box')
now = now + 600001
assert(granted(pickup(1, 1)), 'a stale authorization is replaced')
zone = 'drop'
redeem()
assert(additions == 0, 'an immediate hand-in cannot bypass the server interval')
now = now + 5000
zone = 'pickup'
redeem()
assert(additions == 0, 'a pending pickup still requires hand-in proximity')
zone = 'drop'
redeem()
assert(additions > 0 and reentered, 'a valid authorized hand-in grants rewards')
local received = additions
redeem()
now = now + 5000
redeem()
assert(additions == received, 'consumed authorization rejects reentrant calls and later replays')

for _, clear in ipairs({
    function() events['kora_businesses:recycle:cancelPickup']() end,
    function() hooks.playerDropped() end,
    function() hooks['QBCore:Server:OnPlayerUnload'](1) end,
}) do
    zone = 'pickup'
    assert(granted(pickup(1, 1)))
    clear()
    now, zone = now + 5000, 'drop'
    redeem()
    assert(additions == received, 'cancel, disconnect and character logout clear pickup authority')
end
-- The drop-off ped (SellPed) is an accepted hand-in spot too.
env.Recycle.SellPed = 'sellped'
zone = 'pickup'
assert(granted(pickup(1, 1)))
now, zone = now + 5000, 'sellped'
redeem()
assert(additions > received, 'hand-in at the drop-off ped pays out')
env.Recycle.HandInAtSellPed = false
received = additions
zone = 'pickup'
assert(granted(pickup(1, 1)))
now, zone = now + 5000, 'sellped'
redeem()
assert(additions == received, 'ped hand-in can be switched off')
-- Selling: amount validation and clamping stay server-authoritative.
local owned, removed, paid, nearSeller = { { amount = 4 }, { amount = 3 } }, 0, 0, true
local sellEvents, sellCallbacks = {}, {}
local sellEnv = setmetatable({
    source = 1,
    Recycle = { SellMaterials = true, SellPed = 'sell', DropLocation = 'drop', DeliveryActionDuration = 5000, MaxSellPerRequest = 500, PickupLocations = {} },
    Kora = {
        callback = { register = function(name, fn) sellCallbacks[name] = fn end },
        distance = { player = function(_, coords) return nearSeller and coords == 'sell' end },
    },
    exports = {
        kora_inventory = { addItem = function() return true end, removeItem = function(_, _, _, value) removed = removed + value; return true end },
        kora_core = {
            getItemsByName = function() return owned end,
            getItemByName = function() return owned[1] end,
            addMoney = function(_, _, _, value) paid = paid + value end,
        },
    },
    RegisterNetEvent = function(name, fn) sellEvents[name] = fn end,
    AddEventHandler = function() end,
    GetGameTimer = function() return 0 end,
    Wait = function() end,
}, { __index = _G })
assert(loadfile(root .. 'jobs/recycle/server.lua', 't', sellEnv))()
local sell = sellEvents['kora_businesses:recycle:sellItem']
local function trySell(item, amount) removed, paid = 0, 0; sell(item, amount); return removed end
assert(sellCallbacks['kora_businesses:recycle:getPriceList'](1) ~= false, 'price list available at the sell ped')
assert(trySell('metalscrap', 5) == 5 and paid == 10, 'sells across every owned stack at the listed price')
assert(trySell('metalscrap', 7) == 7 and trySell('metalscrap', 8) == 7, 'amount above owned is clamped to owned (default)')
assert(trySell('metalscrap', 0) == 0 and trySell('metalscrap', -3) == 0 and trySell('metalscrap', 1.5) == 0, 'zero, negative and fractional amounts are rejected')
assert(trySell('metalscrap', 'abc') == 0 and trySell('metalscrap', nil) == 0 and trySell('metalscrap', 0 / 0) == 0, 'non-numeric amounts are rejected')
assert(trySell('metalscrap', math.huge) == 7, 'infinite amount is clamped, never overspends')
assert(trySell('notamaterial', 1) == 0, 'unknown materials are rejected')
sellEnv.Recycle.SellOverAmount = 'reject'
assert(trySell('metalscrap', 8) == 0 and trySell('metalscrap', 7) == 7, 'reject mode refuses amounts above owned')
sellEnv.Recycle.SellOverAmount = 'clamp'
owned = { { amount = 900 } }
assert(trySell('metalscrap', 900) == 500, 'per-request cap applies')
sellEnv.Recycle.MaxSellPerRequest = 10
assert(trySell('metalscrap', 900) == 10, 'cap is read from config at use time')
owned = {}
assert(trySell('metalscrap', 1) == 0, 'cannot sell materials the player does not own')
owned, nearSeller = { { amount = 5 } }, false
assert(trySell('metalscrap', 1) == 0, 'selling requires proximity to the sell ped')

-- Networked carry box: only when configured and the server lockdown mode lets clients create script entities.
local function grantFor(mode, configured)
    lockdown, networkedConfig = mode, configured
    zone = 'pickup'
    events['kora_businesses:recycle:cancelPickup']()
    local result = pickup(1, 1)
    events['kora_businesses:recycle:cancelPickup']()
    return result
end
assert(grantFor('relaxed', true).networked == true, 'relaxed lockdown allows a networked box')
assert(grantFor('inactive', true).networked == true, 'no lockdown allows a networked box')
assert(grantFor('strict', true).networked == false, 'strict lockdown forces a local box')
assert(grantFor('relaxed', false).networked == false, 'networked box is opt-in')

print('qbbusinesses recycling: pickup authority, timing, proximity, replay, lifecycle and sell amount regression passed')
