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
print('qbbusinesses recycling: pickup authority, timing, proximity, replay and lifecycle regression passed')
