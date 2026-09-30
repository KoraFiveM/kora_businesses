local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'
local function noop() end
local vectorMeta = {}
local function vector(x, y, z, w)
    return setmetatable({ x = x, y = y, z = z, w = w }, vectorMeta)
end
vectorMeta.__sub = function(a, b) return vector(a.x - b.x, a.y - b.y, a.z - b.z) end
vectorMeta.__len = function(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end

local function loadResource(path, env)
    local file = assert(io.open(root .. path))
    local code = file:read('*a')
    file:close()
    -- Stock Lua needs disposable translations of FiveM's hashes and compound assignments.
    code = code:gsub('`([^`]+)`', function(name) return ('joaat(%q)'):format(name) end)
    code = code:gsub('([%w_.]+)%s*%+=%s*([^\n]+)', '%1 = %1 + %2')
    code = code:gsub('([%w_.]+)%s*%-=%s*([^\n]+)', '%1 = %1 - %2')
    assert(load(code, '@' .. root .. path, 't', env))()
end

local function setup(spawnIndex, rejectRegistration)
    local callbacks, entities, calls = {}, {}, {}
    local state = { zones = 0, truckTargets = 0, keys = 0, deleted = 0, errors = 0,
        activeZones = {}, removedZones = {}, events = {} }
    local function record(name) calls[#calls + 1] = name end
    local env = setmetatable({
        Globals = {}, vector3 = vector, vector4 = vector, joaat = function(value) return value end,
        GetCurrentResourceName = function() return 'qbbusinesses' end,
        AddEventHandler = function(name, fn)
            state.events[name] = state.events[name] or {}
            table.insert(state.events[name], fn)
        end,
        CreateThread = noop,
        GetPlayerPed = function() return 1 end,
        PlayerPedId = function() return 1 end,
        ClearPedSecondaryTask = noop, TaskPlayAnim = noop, AttachEntityToEntity = noop,
        GetPedBoneIndex = function(_, bone) return bone end,
        NetworkGetEntityFromNetworkId = function(net)
            return entities[net - 1000] and net - 1000 or 0
        end,
        DoesEntityExist = function(entity) return entities[entity] ~= nil end,
        GetEntityModel = function(entity) return entities[entity].model end,
        GetEntityCoords = function(entity) return entities[entity].coords end,
        DeleteEntity = function(entity) entities[entity] = nil end,
        QB = {
            callback = { register = function(name, fn) callbacks[name] = fn end },
            distance = { player = function(_, coords, distance)
                return #(entities[1].coords - coords) <= distance
            end },
        },
        exports = { qbcore = { getPlayerData = function() return { job = { name = 'garbage' } } end } },
    }, { __index = _G })
    loadResource('jobs/garbage/shared.lua', env)
    entities[1] = { coords = env.Garbage.Peds[1].coords }
    loadResource('jobs/garbage/server.lua', env)

    env.QB.callback.trigger = function(name, ...)
        record(name)
        if name == 'qb-garbagejob:setTruck' then
            assert(select(1, ...) == state.truck + 1000, 'register the created network ID')
            if rejectRegistration then return false end
        end
        local result = callbacks[name](1, ...)
        if name == 'qb-garbagejob:spawnTruck' then state.route = result end
        return result
    end
    env.QB.stream = { loadModel = function() return true end }
    env.QB.entities = { create = function() return 2 end }
    env.QB.blips = {
        create = function(_, options)
            if options.route then record('stopBlip') end
            return 1
        end,
        remove = noop,
    }
    env.QB.notify = { send = function(message)
        if message.type == 'error' then state.errors = state.errors + 1 end
    end }
    env.exports.qbtarget = {
        addEntity = function(_, entity, options)
            if entity == 2 then
                state.start = options[1]
            else
                state.truckTargets = state.truckTargets + 1
                state.truckOptions = options
                record('truckTarget')
            end
        end,
        addBoxZone = function(_, options)
            state.zones = state.zones + 1
            state.lastZone = 1000 + state.zones
            state.activeZones[state.lastZone] = options
            record('stopZone')
            return state.lastZone
        end,
        removeZone = function(_, id)
            if not state.activeZones[id] then return false end
            state.activeZones[id] = nil
            table.insert(state.removedZones, id)
            return true
        end,
    }
    env.CreateObject = function(model, x, y, z)
        state.object = (state.object or 99) + 1
        entities[state.object] = { model = model, coords = vector(x, y, z) }
        return state.object
    end
    env.CreateVehicle = function(model, x, y, z)
        state.truck = (state.truck or 9) + 1
        entities[state.truck] = { model = model, coords = vector(x, y, z) }
        return state.truck
    end
    env.VehToNet = function(entity) return entity + 1000 end
    env.SetVehicleNumberPlateText, env.SetVehicleOnGroundProperly = noop, noop
    env.SetEntityAsMissionEntity, env.SetModelAsNoLongerNeeded = noop, noop
    env.TriggerEvent = function(name)
        assert(name == 'qb-vehiclekeys:client:AddKeys')
        state.keys = state.keys + 1
        record('keys')
    end
    env.DeleteVehicle = function(entity)
        state.deleted = state.deleted + 1
        entities[entity] = nil
    end
    env.math = setmetatable({ random = function(a, b)
        if a == 1 and b == #env.Garbage.Locations.vehicle then return spawnIndex end
        if b then return math.random(a, b) end
        return math.random(a)
    end }, { __index = math })
    env.CreateThread = function(fn) fn() end
    loadResource('jobs/garbage/client.lua', env)
    return env, callbacks, entities, calls, state, function(value) rejectRegistration = value end
end

for spawnIndex = 1, 2 do
    local env, callbacks, entities, calls, state = setup(spawnIndex, false)
    local separation = #(env.Garbage.Peds[1].coords - env.Garbage.Locations.vehicle[spawnIndex].coords)
    assert(separation > 15 and separation < 30, 'cover both shipped depot-to-truck distances')
    state.start.onSelect()
    assert(calls[1] == 'qb-garbagejob:spawnTruck' and calls[2] == 'qb-garbagejob:setTruck')
    assert(calls[3] == 'keys' and calls[4] == 'stopBlip' and calls[5] == 'stopZone')
    assert(calls[6] == 'truckTarget' and state.zones == 1 and state.truckTargets == 1)
    assert(state.errors == 0 and not state.start.canInteract())
    local stop = state.route[1].stop
    entities[1].coords = env.Garbage.Locations.trashcan[stop].coords
    assert(callbacks['qb-garbagejob:collectBag'](1, stop) == true)
    entities[1].coords = entities[state.truck].coords
    assert(callbacks['qb-garbagejob:depositBag'](1, stop) == true, 'registered truck accepts a collected bag')
    assert(callbacks['qb-garbagejob:depositBag'](1, stop) == false, 'reject depositing the same bag twice')
end

local env, callbacks, entities, calls, state, setRejected = setup(1, true)
state.start.onSelect()
assert(calls[3] == 'qb-garbagejob:cancel' and #calls == 3)
assert(state.deleted == 1 and not entities[state.truck] and state.errors == 1)
assert(state.zones == 0 and state.truckTargets == 0 and state.keys == 0)
assert(state.start.canInteract(), 'failed registration clears the client truck')
setRejected(false)
state.start.onSelect()
assert(state.zones == 1 and state.truckTargets == 1, 'cancel clears the server route so retry succeeds')

env, callbacks, entities = setup(1, false)
local register = callbacks['qb-garbagejob:setTruck']
assert(register(1, 1010) == false, 'reject registration without an active route')
assert(callbacks['qb-garbagejob:spawnTruck'](1))
assert(register(1, '1010') == false and register(1, 0) == false)
assert(register(1, 99999) == false, 'reject missing entities')
entities[10] = { model = 'wrong-model', coords = entities[1].coords }
assert(register(1, 1010) == false, 'reject a different vehicle model')
entities[10] = { model = env.Garbage.Vehicle, coords = vector(0, 0, 0) }
assert(register(1, 1010) == false, 'reject distant trucks')
entities[10].coords = env.Garbage.Locations.vehicle[1].coords
assert(register(1, 1010) == true)
assert(register(1, 1010) == false, 'a route truck is registered once')

local function emit(state, name, ...)
    for _, handler in ipairs(state.events[name] or {}) do handler(...) end
end

env, callbacks, entities, calls, state = setup(1, false)
env.Garbage.MinStops, env.Garbage.MaxStops = 2, 2
env.Garbage.MinBagsPerStop, env.Garbage.MaxBagsPerStop = 1, 1
state.start.onSelect()
for index, stop in ipairs(state.route) do
    local zoneId = state.lastZone
    local zone = assert(state.activeZones[zoneId])
    assert(type(zoneId) == 'number' and zone.options[1].canInteract())
    entities[1].coords = env.Garbage.Locations.trashcan[stop.stop].coords
    zone.options[1].onSelect()
    entities[1].coords = entities[state.truck].coords
    state.truckOptions[1].onSelect()
    assert(state.activeZones[zoneId] == nil, 'completing a stop removes its returned target ID')
    assert(state.removedZones[#state.removedZones] == zoneId)
    if index < #state.route then
        assert(next(state.activeZones) == state.lastZone and next(state.activeZones, state.lastZone) == nil,
            'advancing leaves only the current stop target')
    else
        assert(next(state.activeZones) == nil, 'finishing the route removes the final stop target')
    end
end

env, callbacks, entities, calls, state = setup(1, false)
for _ = 1, 2 do
    entities[1].coords = env.Garbage.Peds[1].coords
    state.start.onSelect()
    local zoneId = state.lastZone
    assert(state.activeZones[zoneId])
    emit(state, 'QBCore:Client:OnJobUpdate', { name = 'unemployed' })
    assert(next(state.activeZones) == nil, 'job cancellation removes the current stop target')
    assert(state.removedZones[#state.removedZones] == zoneId)
    local removed = #state.removedZones
    emit(state, 'QBCore:Client:OnJobUpdate', { name = 'unemployed' })
    assert(#state.removedZones == removed, 'repeated cleanup does not remove a target twice')
end
state.start.onSelect()
local zoneId = state.lastZone
state.activeZones[99] = { unrelated = true }
emit(state, 'onResourceStop', 'another-resource')
assert(state.activeZones[zoneId], 'another resource stopping does not remove the active stop')
-- An externally deleted truck still needs its stop zone cleaned up.
entities[state.truck] = nil
emit(state, 'onResourceStop', 'qbbusinesses')
assert(state.activeZones[zoneId] == nil, 'resource stop removes the active stop target')
assert(state.activeZones[99] and #state.removedZones == 3, 'cleanup preserves unrelated zones')
print('qbbusinesses garbage: truck registration, bag deposits, failure cleanup and stop zone lifecycle passed')
