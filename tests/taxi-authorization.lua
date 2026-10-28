local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'
local coreRoot = os.getenv('QB_CORE_ROOT') or root .. '../kora_core'
local callbacks, events = {}, {}
local payments = 0
local env = {}
for name, value in pairs(_G) do env[name] = value end
env.Config, env.Taxi, env.Globals = nil, nil, {}
env.vector3 = function(x, y, z) return { x = x, y = y, z = z } end
env.vector4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end
env.Core, env.CoreInternal = { util = {}, player = {} }, { player = { COLUMN_FOR = {} } }
env.AddEventHandler, env.CreateThread = function() end, function() end
env.QB = {
    util = { isCallable = function(value) return type(value) == 'function' end,
        vecDistance = function() return 1000 end },
    callback = { register = function(name, fn) callbacks[name] = fn end },
}
assert(loadfile(coreRoot .. '/modules/util/shared.lua', 't', env))()
assert(loadfile(coreRoot .. '/modules/player/server.lua', 't', env))()
env.exports = { kora_core = {
    getPlayer = function(_, src) return env.Core.player.getPlayer(src) end,
    addMoney = function() payments = payments + 1 end,
} }
env.RegisterNetEvent = function(name, fn) events[name] = fn end
assert(loadfile(root .. 'jobs/taxi/shared.lua', 't', env))()
assert(loadfile(root .. 'jobs/taxi/server.lua', 't', env))()
local request = assert(callbacks['qb-taxi:getPickupLocation'])
assert(request(1) == nil, 'missing player is rejected')
local player = { PlayerData = {} }
env.CoreInternal.player.bySource[1] = player
assert(request(1) == nil, 'missing job is rejected')
player.PlayerData.job = { name = 'unemployed' }
assert(request(1) == nil, 'wrong job is rejected')
player.PlayerData.job = { name = env.Taxi.jobRequired }
local snapshot = env.Core.player.getPlayer(1)
assert(snapshot.job and not snapshot.PlayerData, 'test uses the actual modern flat snapshot')
local route = request(1)
assert(route and route.pickup and route.dropoff, 'authorized flat snapshot can request a trip')
player.PlayerData.job.name = 'unemployed'
assert(request(1) == nil, 'job changes are read afresh')
env.source = 1
events['qb-taxi:pickup']()
events['qb-taxi:dropOff']()
assert(payments == 0, 'wrong job cannot advance or redeem the trip')
print('taxi authorization: actual core snapshots, missing players/jobs and job changes passed')
