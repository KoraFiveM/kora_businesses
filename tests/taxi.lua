local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'
local coreRoot = os.getenv('QB_CORE_ROOT') or root .. '../kora_core'
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
env.Kora = {
    util = { isCallable = function(value) return type(value) == 'function' end, vecDistance = distance },
    callback = { register = function(name, fn) callbacks[name] = fn end },
    distance = { player = function(src, coords, range) return distance(positions[src], coords) <= range end },
}
assert(loadfile(coreRoot .. '/modules/util/shared.lua', 't', env))()
assert(loadfile(coreRoot .. '/modules/player/server.lua', 't', env))()
players = env.CoreInternal.player.bySource
env.exports = { kora_core = {
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

do
    local clientEvents, zones, pending, threads, created, removed, alive, left = {}, {}, {}, {}, {}, {}, {}, {}
    local actions, nextEntity = nil, 100
    local client = {}
    for name, value in pairs(env) do client[name] = value end
    client.RegisterNetEvent = function(name, fn) clientEvents[name] = fn end
    client.TriggerServerEvent = function(name, ...)
        assert(select('#', ...) == 0, 'taxi completion event arguments must remain unchanged')
        pending[#pending + 1] = name
    end
    client.CreateThread = function(fn) threads[#threads + 1] = coroutine.create(fn) end
    client.Wait = coroutine.yield
    client.PlayerPedId = function() return 1 end
    client.GetVehicleMaxNumberOfPassengers = function() return 2 end
    client.IsVehicleSeatFree = function() return true end
    client.TaskLeaveVehicle = function(ped, vehicle, flag) left[#left + 1] = { ped, vehicle, flag } end
    for _, name in ipairs({ 'SetNewWaypoint', 'TaskStartScenarioInPlace', 'SetEntityAsMissionEntity',
        'FreezeEntityPosition', 'ClearPedTasksImmediately', 'TaskEnterVehicle', 'TaskWarpPedIntoVehicle',
        'SetVehicleNumberPlateText' }) do client[name] = function() end end
    client.Kora = {
        callback = { trigger = function(name) return callbacks[name](1) end },
        notify = { send = function() end },
        interact = { addBoxZone = function(_, _, _, options) actions = options end },
        zones = { box = function(zone)
            zone.remove = function() zone.removed = true end
            zones[#zones + 1] = zone
            return zone
        end },
        entities = {
            create = function(model, coords, options)
                nextEntity = nextEntity + 1
                created[#created + 1] = { entity = nextEntity, model = model, coords = coords, options = options }
                alive[nextEntity] = true
                return nextEntity
            end,
            remove = function(entity)
                assert(type(entity) == 'number', 'cleanup must retain its departing passenger handle')
                removed[#removed + 1] = entity
                alive[entity] = nil
                return true
            end,
        },
    }
    local originalSpawn = env.TriggerClientEvent
    env.TriggerClientEvent = function(name, src)
        originalSpawn(name, src)
        client.source = 65535
        clientEvents[name]()
    end
    local function deliver()
        local queued = pending
        pending = {}
        for _, name in ipairs(queued) do fire(name, 1) end
    end
    local function cleanup(thread)
        local ok, delay = coroutine.resume(thread)
        assert(ok and delay == 5000, 'departing cleanup must preserve the five-second delay')
        ok, delay = coroutine.resume(thread)
        assert(ok, delay)
        assert(coroutine.status(thread) == 'dead')
    end
    assert(loadfile(arg[1] or root .. 'jobs/taxi/client.lua', 't', client))()
    local beforePay = #payments
    actions[1].action()
    local vehicle, firstPassenger = created[1].entity, created[2].entity
    positions[1] = zones[1].coords
    zones[1].onEnter(); deliver()
    positions[1] = zones[2].coords
    zones[2].onEnter()
    assert(left[1][1] == firstPassenger and left[1][2] == vehicle and left[1][3] == 0)
    assert(#removed == 0 and #threads == 1, 'departing passenger stays during the existing delay')
    deliver()
    local secondPassenger = created[3].entity
    assert(#payments == beforePay + 1 and alive[firstPassenger] and alive[secondPassenger],
        'the actual server must pay and start the next fare before cleanup')
    cleanup(threads[1]) -- Start after the next fare, matching a deferred client thread.
    assert(removed[1] == firstPassenger and not alive[firstPassenger] and alive[secondPassenger],
        'the first completed passenger must be removed while the next passenger remains')
    positions[1] = zones[3].coords
    zones[3].onEnter(); deliver()
    positions[1] = zones[4].coords
    zones[4].onEnter(); deliver()
    local thirdPassenger = created[4].entity
    assert(#payments == beforePay + 2 and left[2][1] == secondPassenger and alive[thirdPassenger])
    actions[2].action() -- Returning the taxi clears mutable npc before the pending cleanup starts.
    assert(not alive[thirdPassenger] and not alive[vehicle] and alive[secondPassenger])
    cleanup(threads[2])
    assert(removed[#removed] == secondPassenger and not alive[secondPassenger],
        'returning the taxi must not discard a completed passenger cleanup handle')
    env.TriggerClientEvent = originalSpawn
end

print('taxi server: replacement requires a new pickup; fare, isolation, lifecycle and departing passenger cleanup checks passed')
