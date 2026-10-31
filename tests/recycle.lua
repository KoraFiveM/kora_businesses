local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'
local callbacks, events, hooks = {}, {}, {}
local now, additions, zone = 0, 0, 'drop'
local reentered = false
local env
env = setmetatable({
    source = 1,
    Recycle = { DropLocation = 'drop', DeliveryActionDuration = 5000, PickupLocations = { { loc = 'pickup' } } },
    QB = {
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
            events['qb-recyclejob:server:getItem']()
        end
    end,
    math = setmetatable({ random = function(low) return low end }, { __index = math }),
}, { __index = _G })
assert(loadfile(root .. 'jobs/recycle/server.lua', 't', env))()
local redeem = events['qb-recyclejob:server:getItem']
redeem()
now = 10000
redeem()
assert(additions == 0, 'standing at hand-in must not authorize rewards, even after the cooldown')

local pickup = assert(callbacks['qb-recyclejob:server:pickupPackage'])
assert(pickup(1, 1) == false, 'pickup requires a visit to the configured package location')
zone = 'pickup'
assert(pickup(1, '1') == false and pickup(1, 1.5) == false and pickup(1, 2) == false)
assert(pickup(1, 1) == true and pickup(1, 1) == false, 'only one package can be pending')
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
    function() events['qb-recyclejob:server:cancelPickup']() end,
    function() hooks.playerDropped() end,
    function() hooks['QBCore:Server:OnPlayerUnload'](1) end,
}) do
    zone = 'pickup'
    assert(pickup(1, 1) == true)
    clear()
    now, zone = now + 5000, 'drop'
    redeem()
    assert(additions == received, 'cancel, disconnect and character logout clear pickup authority')
end
-- Selling: amount validation and clamping stay server-authoritative.
local owned, removed, paid, nearSeller = { { amount = 4 }, { amount = 3 } }, 0, 0, true
local sellEvents, sellCallbacks = {}, {}
local sellEnv = setmetatable({
    source = 1,
    Recycle = { SellMaterials = true, SellPed = 'sell', DropLocation = 'drop', DeliveryActionDuration = 5000, MaxSellPerRequest = 500, PickupLocations = {} },
    QB = {
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
local sell = sellEvents['qb-recyclejob:server:sellItem']
local function trySell(item, amount) removed, paid = 0, 0; sell(item, amount); return removed end
assert(sellCallbacks['qb-recyclejob:server:getPriceList'](1) ~= false, 'price list available at the sell ped')
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
print('qbbusinesses recycling: pickup authority, timing, proximity, replay, lifecycle and sell amount regression passed')
