local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'
local coreRoot = os.getenv('QB_CORE_ROOT') or root .. '../kora_core'
local callbacks, events, positions, players, payments, spawned = {}, {}, {}, {}, {}, {}
local warnings, vehicles, alive, deleted, spawnedTaxis = {}, {}, {}, {}, {}
local choice = 1
local now = 0
local env = {}
for name, value in pairs(_G) do env[name] = value end
env.Config, env.Taxi, env.Globals = nil, nil, {}
env.vector3 = function(x, y, z) return { x = x, y = y, z = z } end
env.vector4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end
local function distance(a, b)
    return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2 + (a.z - b.z)^2)
end
env.Core, env.CoreInternal = { util = {}, player = {} }, { player = { COLUMN_FOR = {} } }
env.AddEventHandler, env.CreateThread = function(name, fn) events[name] = fn end, function() end
env.Config = { jobs = { taxi = { requireOnDuty = true, minSpeedMps = 45.0, farePerMeter = 0.2 } } }
env.joaat = function(name) return name end
env.GetGameTimer = function() return now end
env.GetCurrentResourceName = function() return 'kora_businesses' end
env.GetPlayerPed = function(src) return src end
env.GetVehiclePedIsIn = function(ped) return vehicles[ped] or 0 end
env.GetEntityModel = function(vehicle) return alive[vehicle] and 'taxi' or 'other' end
env.DoesEntityExist = function(entity) return alive[entity] == true end
env.DeleteEntity = function(entity) deleted[#deleted + 1] = entity; alive[entity] = nil end
env.SetEntityRoutingBucket = function() end
env.GetPlayerRoutingBucket = function() return 0 end
env.NetworkGetEntityFromNetworkId = function(netId) return netId + 1000 end
env.Kora = {
    util = { isCallable = function(value) return type(value) == 'function' end, vecDistance = distance },
    callback = { register = function(name, fn) callbacks[name] = fn end },
    distance = { player = function(src, coords, range) return distance(positions[src], coords) <= range end },
    print = { warn = function(message) warnings[#warnings + 1] = message end },
    entities = { createVehicle = function(model, coords, vehicleType)
        assert(model == 'taxi' and vehicleType == 'automobile' and coords.w == 0.0)
        spawnedTaxis[#spawnedTaxis + 1] = coords
        local netId = 500 + #spawnedTaxis
        alive[netId + 1000] = true
        return netId
    end },
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
-- Invalid or stray events are ignored quietly (a warning, never a Lua error) and never pay.
local function reject(name, src, reason)
    local paid, started, warned = #payments, #spawned, #warnings
    local ok, err = pcall(fire, name, src)
    assert(ok, 'invalid requests must not raise: ' .. tostring(err))
    assert(#payments == paid and #spawned == started, 'rejection must not pay or start another trip')
    if reason then
        assert(#warnings == warned + 1 and warnings[#warnings]:find(reason, 1, true),
            'expected warning: ' .. reason .. ' got ' .. tostring(warnings[#warnings]))
    end
end
local function setTaxi(src, inTaxi)
    local vehicle = 200 + src
    alive[vehicle] = inTaxi or nil
    vehicles[src] = inTaxi and vehicle or nil
end

assert(request(3) == nil, 'missing player cannot request a route')
players[3] = { PlayerData = { job = { name = 'unemployed' } } }
assert(request(3) == nil, 'wrong job cannot request a route')
players[4] = { PlayerData = { job = { name = config.jobRequired, onduty = false } } }
assert(request(4) == nil, 'off-duty taxi driver cannot request a route')
env.Config.jobs.taxi.requireOnDuty = false
assert(request(4) ~= nil, 'requireOnDuty = false lets off-duty drivers work')
env.Config.jobs.taxi.requireOnDuty = true
players[4].PlayerData.job.onduty = true
assert(request(4) ~= nil, 'on-duty taxi driver can request a route')
fire('playerDropped', 4)
players[1] = { PlayerData = { job = { name = config.jobRequired } } }
players[2] = { PlayerData = { job = { name = config.jobRequired } } }
setTaxi(1, true); setTaxi(2, true)
local first, other = request(1), request(2)
assert(first.pickup == config.PickUp[1] and first.dropoff == config.DropOffs[1])
positions[1], positions[2] = first.pickup, other.pickup
fire('qb-taxi:pickup', 1)
fire('qb-taxi:pickup', 2)
choice = 2
local replacement = request(1)
assert(replacement.pickup == config.PickUp[2] and replacement.dropoff == config.DropOffs[2])
local tripMeters = distance(replacement.pickup, replacement.dropoff)
now = 10 * 3600 * 1000
positions[1] = replacement.dropoff
reject('qb-taxi:dropOff', 1, 'before the pickup')
reject('qb-taxi:pickup', 1, 'too far from the pickup')
positions[1] = replacement.pickup
fire('qb-taxi:pickup', 1)
positions[1] = replacement.dropoff
now = now + 3600 * 1000
fire('qb-taxi:dropOff', 1)
assert(#payments == 1 and spawned[1] == 1)
assert(payments[1].source == 1 and payments[1].account == 'cash')
assert(payments[1].amount == math.floor(tripMeters * 0.2))
reject('qb-taxi:dropOff', 1, 'no taxi trip')
positions[2] = other.dropoff
now = now + 3600 * 1000
fire('qb-taxi:dropOff', 2)
assert(#payments == 2 and payments[2].source == 2, 'replacement does not reset another driver')

-- The fare rate is configuration, not a constant.
env.Config.jobs.taxi.farePerMeter = 0.5
local priced = request(1)
positions[1] = priced.pickup; fire('qb-taxi:pickup', 1)
positions[1] = priced.dropoff; now = now + 3600 * 1000
fire('qb-taxi:dropOff', 1)
assert(payments[3].amount == math.floor(distance(priced.pickup, priced.dropoff) * 0.5), 'fare follows farePerMeter')
env.Config.jobs.taxi.farePerMeter = 0.2

-- Teleporting between the pickup and the drop-off is not paid; a trip at a believable speed is.
local teleport = request(1)
local meters = distance(teleport.pickup, teleport.dropoff)
positions[1] = teleport.pickup; fire('qb-taxi:pickup', 1)
positions[1] = teleport.dropoff
local paid = #payments
reject('qb-taxi:dropOff', 1, 'not paid')
reject('qb-taxi:dropOff', 1, 'no taxi trip')
local near = request(1)
meters = distance(near.pickup, near.dropoff)
positions[1] = near.pickup; fire('qb-taxi:pickup', 1)
positions[1] = near.dropoff
now = now + math.floor(meters / 45.0 * 1000) - 5
reject('qb-taxi:dropOff', 1, 'not paid')
local honest = request(1)
meters = distance(honest.pickup, honest.dropoff)
positions[1] = honest.pickup; fire('qb-taxi:pickup', 1)
positions[1] = honest.dropoff
now = now + math.ceil(meters / 45.0 * 1000) + 5
fire('qb-taxi:dropOff', 1)
assert(#payments == paid + 1, 'a trip at a believable speed is paid')
env.Config.jobs.taxi.minSpeedMps = 10.0
local slow = request(1)
meters = distance(slow.pickup, slow.dropoff)
positions[1] = slow.pickup; fire('qb-taxi:pickup', 1)
positions[1] = slow.dropoff
now = now + math.ceil(meters / 45.0 * 1000)
reject('qb-taxi:dropOff', 1, 'not paid')
env.Config.jobs.taxi.minSpeedMps = 45.0
paid = #payments

-- Pay needs the driver to be in a taxi when the trip ends.
local onFoot = request(1)
positions[1] = onFoot.pickup; fire('qb-taxi:pickup', 1)
positions[1] = onFoot.dropoff
now = now + 3600 * 1000
setTaxi(1, false)
reject('qb-taxi:dropOff', 1, 'outside a taxi')
setTaxi(1, true)
assert(#payments == paid)

local fresh = request(1)
positions[1] = fresh.dropoff
reject('qb-taxi:dropOff', 1, 'before the pickup')
positions[1] = fresh.pickup
fire('qb-taxi:pickup', 1)
events['QBCore:Server:OnPlayerUnload'](1)
positions[1] = fresh.dropoff
reject('qb-taxi:dropOff', 1, 'no taxi trip')
fresh = request(2)
positions[2] = fresh.pickup
fire('qb-taxi:pickup', 2)
fire('playerDropped', 2)
positions[2] = fresh.dropoff
reject('qb-taxi:dropOff', 2, 'no taxi trip')

-- The depot taxi is a server-spawned networked vehicle with a server-tracked owner.
do
    local spawn = assert(callbacks['qb-taxi:spawnTaxi'])
    positions[1] = { x = config.parkLocation.x + 100, y = config.parkLocation.y, z = config.parkLocation.z }
    assert(spawn(1) == nil and #spawnedTaxis == 0, 'must be at the depot')
    positions[1] = config.parkLocation
    assert(spawn(3) == nil and #spawnedTaxis == 0, 'wrong job cannot spawn a taxi')
    local netId = spawn(1)
    assert(netId and #spawnedTaxis == 1 and alive[netId + 1000], 'taxi driver gets a networked depot taxi')
    assert(spawnedTaxis[1].x == config.parkLocation.x and spawnedTaxis[1].z == config.parkLocation.z)
    local again = spawn(1)
    assert(again ~= netId and not alive[netId + 1000] and alive[again + 1000], 'a second spawn replaces the first taxi')
    fire('qb-taxi:returnTaxi', 2)
    assert(alive[again + 1000], "another player's return does not delete my taxi")
    fire('qb-taxi:returnTaxi', 1)
    assert(not alive[again + 1000], 'returning the taxi deletes it on the server')
    fire('qb-taxi:returnTaxi', 1)
    local third = spawn(1)
    fire('playerDropped', 1)
    assert(not alive[third + 1000], 'a disconnect deletes the depot taxi')
    local fourth = spawn(1)
    events['QBCore:Server:OnPlayerUnload'](1)
    assert(not alive[fourth + 1000], 'unloading the character deletes the depot taxi')
    local fifth = spawn(1)
    events['onResourceStop']('another_resource')
    assert(alive[fifth + 1000], 'other resources stopping is ignored')
    events['onResourceStop']('kora_businesses')
    assert(not alive[fifth + 1000], 'stopping the resource removes its taxis')
    players[1].PlayerData.job.onduty = false
    assert(spawn(1) == nil, 'off-duty drivers cannot spawn a taxi')
    players[1].PlayerData.job.onduty = nil
end

do
    local clientEvents, zones, pending, threads, created, removed, left = {}, {}, {}, {}, {}, {}, {}
    local notified = {}
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
    local hooks = {}
    client.TriggerEvent = function(name, ...) hooks[#hooks + 1] = { name = name, ... } end
    client.Config = { jobs = { taxi = { npcFromOwnTaxi = true } } }
    client.NetworkDoesNetworkIdExist = function() return true end
    client.NetToVeh = function(netId) return netId + 1000 end
    client.GetVehiclePedIsIn = function() return 0 end
    client.GetPedInVehicleSeat = function() return 0 end
    client.GetEntityModel = function() return 'taxi' end
    client.GetVehicleMaxNumberOfPassengers = function() return 2 end
    client.IsVehicleSeatFree = function() return true end
    client.TaskLeaveVehicle = function(ped, vehicle, flag) left[#left + 1] = { ped, vehicle, flag } end
    client.TaskWarpPedIntoVehicle = function(ped, vehicle) vehicles[ped] = vehicle end
    for _, name in ipairs({ 'SetNewWaypoint', 'TaskStartScenarioInPlace', 'SetEntityAsMissionEntity',
        'FreezeEntityPosition', 'ClearPedTasksImmediately', 'TaskEnterVehicle',
        'SetVehicleNumberPlateText' }) do client[name] = function() end end
    client.Kora = {
        callback = { trigger = function(name) return callbacks[name](1) end },
        notify = { send = function(options) notified[#notified + 1] = options.message end },
        interact = { addBoxZone = function(_, _, _, options) actions = options end },
        zones = { box = function(zone)
            zone.remove = function() zone.removed = true end
            zones[#zones + 1] = zone
            return zone
        end },
        entities = {
            requestControl = function() return true end,
            create = function(model, coords, options)
                assert(model ~= 'taxi', 'the depot taxi must be a server-spawned networked vehicle, not a local entity')
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
        for _, name in ipairs(queued) do
            if name == 'qb-taxi:dropOff' then now = now + 3600 * 1000 end
            fire(name, 1)
        end
    end
    local function cleanup(thread)
        local ok, delay = coroutine.resume(thread)
        assert(ok and delay == 5000, 'departing cleanup must preserve the five-second delay')
        ok, delay = coroutine.resume(thread)
        assert(ok, delay)
        assert(coroutine.status(thread) == 'dead')
    end
    setTaxi(1, false)
    assert(loadfile(arg[1] or root .. 'jobs/taxi/client.lua', 't', client))()
    local beforePay = #payments
    positions[1] = config.parkLocation

    -- Off duty: the server refuses the taxi and nothing is spawned.
    players[1].PlayerData.job.onduty = false
    local taxisBefore = #spawnedTaxis
    actions[1].action()
    assert(#spawnedTaxis == taxisBefore and #created == 0 and notified[#notified]:find('on duty', 1, true),
        'an off-duty driver is told to go on duty and no taxi is spawned')
    players[1].PlayerData.job.onduty = nil

    actions[1].action()
    local vehicle, firstPassenger = vehicles[1], created[1].entity
    assert(vehicle and alive[vehicle] and #spawnedTaxis == taxisBefore + 1, 'the taxi is the server-spawned networked vehicle')
    assert(created[1].model ~= 'taxi', 'only passengers are local entities')
    positions[1] = zones[1].coords
    zones[1].onEnter(); deliver()
    positions[1] = zones[2].coords
    zones[2].onEnter()
    assert(left[1][1] == firstPassenger and left[1][2] == vehicle and left[1][3] == 0)
    assert(#removed == 0 and #threads == 1, 'departing passenger stays during the existing delay')
    deliver()
    local secondPassenger = created[2].entity
    assert(#payments == beforePay + 1 and alive[firstPassenger] and alive[secondPassenger],
        'the actual server must pay and start the next fare before cleanup')
    cleanup(threads[1]) -- Start after the next fare, matching a deferred client thread.
    assert(removed[1] == firstPassenger and not alive[firstPassenger] and alive[secondPassenger],
        'the first completed passenger must be removed while the next passenger remains')
    positions[1] = zones[3].coords
    zones[3].onEnter(); deliver()
    positions[1] = zones[4].coords
    zones[4].onEnter(); deliver()
    local thirdPassenger = created[3].entity
    assert(#payments == beforePay + 2 and left[2][1] == secondPassenger and alive[thirdPassenger])
    actions[2].action() -- Returning the taxi clears mutable npc before the pending cleanup starts.
    deliver()
    assert(not alive[thirdPassenger] and not alive[vehicle] and alive[secondPassenger],
        'Return Taxi deletes the job taxi (on the server) and the pending passenger')
    cleanup(threads[2])
    assert(removed[#removed] == secondPassenger and not alive[secondPassenger],
        'returning the taxi must not discard a completed passenger cleanup handle')

    local started, finished = 0, 0
    for _, hook in ipairs(hooks) do
        if hook.name == 'qbtaxi:client:meterTrip' then started = started + 1 end
        if hook.name == 'qbtaxi:client:meterTripFinished' then finished = finished + 1 end
    end
    assert(started == 2 and finished == 3, 'the fare meter follows every pickup, drop-off and taxi return')

    -- A trip can start from any taxi's driver seat; Return Taxi then leaves that vehicle alone.
    local doTaxiNpc = clientEvents['qb-taxi:client:DoTaxiNpc']
    local ownTaxi = 900
    alive[ownTaxi] = true
    client.GetVehiclePedIsIn = function() return ownTaxi end
    client.GetPedInVehicleSeat = function() return 1 end
    local createdBefore = #created
    client.Config.jobs.taxi.npcFromOwnTaxi = false
    doTaxiNpc()
    assert(#created == createdBefore, 'npcFromOwnTaxi = false ignores the radial request')
    client.Config.jobs.taxi.npcFromOwnTaxi = true
    client.GetEntityModel = function() return 'adder' end
    doTaxiNpc()
    assert(#created == createdBefore, 'only a taxi model can start a trip')
    client.GetEntityModel = function() return 'taxi' end
    client.GetPedInVehicleSeat = function() return 2 end
    doTaxiNpc()
    assert(#created == createdBefore, 'only the driver seat can start a trip')
    client.GetPedInVehicleSeat = function() return 1 end
    doTaxiNpc()
    assert(#created == createdBefore + 1 and alive[created[#created].entity], 'driver of a taxi starts a trip')
    local radialPassenger = created[#created].entity
    doTaxiNpc()
    assert(#created == createdBefore + 1, 'a second request waits for the current trip')
    actions[2].action()
    deliver()
    assert(alive[ownTaxi] and not alive[radialPassenger], 'Return Taxi only deletes a taxi this job spawned')
    env.TriggerClientEvent = originalSpawn
end

print('taxi server: networked depot taxi, on-duty and anti-teleport checks, quiet rejections, fare, isolation, lifecycle and departing passenger cleanup checks passed')
