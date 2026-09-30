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
    local state = { zones = 0, truckTargets = 0, keys = 0, deleted = 0, errors = 0 }
    local function record(name) calls[#calls + 1] = name end
    local env = setmetatable({
        Globals = {}, vector3 = vector, vector4 = vector, joaat = function(value) return value end,
        GetCurrentResourceName = function() return 'qbbusinesses' end,
        AddEventHandler = noop, CreateThread = noop,
        GetPlayerPed = function() return 1 end,
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
                record('truckTarget')
            end
        end,
        addBoxZone = function()
            state.zones = state.zones + 1
            record('stopZone')
        end,
        removeZone = noop,
    }
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
print('qbbusinesses garbage: truck registration, default spawn range, bag deposit and failure cleanup passed')
