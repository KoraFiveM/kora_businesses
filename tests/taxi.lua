local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'
local coreRoot = os.getenv('QB_CORE_ROOT') or root .. '../qbcore'
local callbacks, events, positions, players, payments, spawned = {}, {}, {}, {}, {}, {}
local choice = 1
local env = {}
for name, value in pairs(_G) do env[name] = value end
env.Config, env.Taxi, env.Globals = nil, nil, {}
env.vector3 = function(x, y, z) return { x = x, y = y, z = z } end
env.vector4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end
local function distance(a, b)
    return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2 + (a.z - b.z)^2)
end
env.Core, env.CoreInternal = { util = {}, player = {} }, { player = { COLUMN_FOR = {} } }
env.AddEventHandler, env.CreateThread = function() end, function() end
env.QB = {
    util = { isCallable = function(value) return type(value) == 'function' end, vecDistance = distance },
    callback = { register = function(name, fn) callbacks[name] = fn end },
    distance = { player = function(src, coords, range) return distance(positions[src], coords) <= range end },
}
assert(loadfile(coreRoot .. '/modules/util/shared.lua', 't', env))()
assert(loadfile(coreRoot .. '/modules/player/server.lua', 't', env))()
players = env.CoreInternal.player.bySource
env.exports = { qbcore = {
    getPlayer = function(_, src) return env.Core.player.getPlayer(src) end,
    addMoney = function(_, src, account, amount)
        payments[#payments + 1] = { source = src, account = account, amount = amount }
        return true
    end,
} }
env.RegisterNetEvent = function(name, fn) events[name] = fn end
env.AddEventHandler = function(name, fn) events[name] = fn end
env.TriggerClientEvent = function(name, src)
    assert(name == 'qb-taxi:client:spawnPickup')
    spawned[#spawned + 1] = src
end
env.math = {}
for name, value in pairs(math) do env.math[name] = value end
env.math.random = function(a, b) assert(choice >= a and choice <= b); return choice end
assert(loadfile(root .. 'jobs/taxi/shared.lua', 't', env))()
assert(loadfile(root .. 'jobs/taxi/server.lua', 't', env))()
local config = env.Taxi
local request = assert(callbacks['qb-taxi:getPickupLocation'])
local function fire(name, src)
    env.source = src
    return events[name]()
end
local function reject(name, src, reason)
    local count = #payments
    local ok, err = pcall(fire, name, src)
    assert(not ok and tostring(err):find(reason, 1, true), 'expected rejection: ' .. reason)
    assert(#payments == count and #spawned == count, 'rejection must not pay or start another trip')
end
assert(request(3) == nil, 'missing player cannot request a route')
players[3] = { PlayerData = { job = { name = 'unemployed' } } }
assert(request(3) == nil, 'wrong job cannot request a route')
players[1] = { PlayerData = { job = { name = config.jobRequired } } }
players[2] = { PlayerData = { job = { name = config.jobRequired } } }
local first, other = request(1), request(2)
assert(first.pickup == config.PickUp[1] and first.dropoff == config.DropOffs[1])
positions[1], positions[2] = first.pickup, other.pickup
fire('qb-taxi:pickup', 1)
fire('qb-taxi:pickup', 2)
choice = 2
local replacement = request(1)
assert(replacement.pickup == config.PickUp[2] and replacement.dropoff == config.DropOffs[2])
positions[1] = replacement.dropoff
reject('qb-taxi:dropOff', 1, 'Pickup has not been completed yet')
reject('qb-taxi:pickup', 1, 'Player is too far from the pickup location')
positions[1] = replacement.pickup
fire('qb-taxi:pickup', 1)
positions[1] = replacement.dropoff
fire('qb-taxi:dropOff', 1)
assert(#payments == 1 and spawned[1] == 1)
assert(payments[1].source == 1 and payments[1].account == 'cash')
assert(payments[1].amount == math.floor(distance(replacement.pickup, replacement.dropoff) * 0.2))
reject('qb-taxi:dropOff', 1, 'No current taxi found for this source')
positions[2] = other.dropoff
fire('qb-taxi:dropOff', 2)
assert(#payments == 2 and payments[2].source == 2, 'replacement does not reset another driver')
local fresh = request(1)
positions[1] = fresh.dropoff
reject('qb-taxi:dropOff', 1, 'Pickup has not been completed yet')
positions[1] = fresh.pickup
fire('qb-taxi:pickup', 1)
events['QBCore:Server:OnPlayerUnload'](1)
positions[1] = fresh.dropoff
reject('qb-taxi:dropOff', 1, 'No current taxi found for this source')
fresh = request(2)
positions[2] = fresh.pickup
fire('qb-taxi:pickup', 2)
fire('playerDropped', 2)
positions[2] = fresh.dropoff
reject('qb-taxi:dropOff', 2, 'No current taxi found for this source')
print('taxi server: replacement requires a new pickup; fare, isolation and lifecycle checks passed')
