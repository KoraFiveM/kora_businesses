-- Legacy qb-mechanicjob:server:SaveVehicleProps (jobs/mechanic/props.lua) against the real mechanic
-- permit flow (jobs/mechanic/server.lua): F#336 (an on-duty mechanic can no longer push arbitrary
-- tuning; only the respray/bumper result of a service they just completed is persisted), F#339 (an
-- owner can never save healthier wear than the stored values) and X11 (the "Mechanicured" typo).
local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'
local checks = 0
local function equal(actual, expected, message)
    checks = checks + 1
    if actual ~= expected then error(('%s: expected %s, got %s'):format(message, tostring(expected), tostring(actual)), 2) end
end

local vec = {}
vec.__index = vec
vec.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vec) end
vec.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
local function v3(x, y, z) return setmetatable({ x = x, y = y, z = z }, vec) end

local function encode(value)
    if type(value) ~= 'table' then return tostring(value) end
    local parts = {}
    for k, item in pairs(value) do parts[#parts + 1] = tostring(k) .. '=' .. encode(item) end
    table.sort(parts)
    return '{' .. table.concat(parts, ',') .. '}'
end

local env = {}
for name, value in pairs(_G) do env[name] = value end
env.Globals, env.vector3, env.json = {}, v3, { encode = encode }
assert(loadfile(root .. 'jobs/mechanic/shared.lua', 't', env))()

local bay = env.Mechanic.fullRepair.garages[1]
local handlers, callbacks, saved, notices, clientEvents = {}, {}, {}, {}, {}
local now, job = 100000, { name = 'mechanic', type = 'automotive', onduty = true }
local citizen = 'STRANGER'
local rows = {
    ABC123 = { plate = 'ABC123', citizenid = 'OWNER', mods = { modSpoilers = 2 } },
    FLEET1 = { plate = 'FLEET1', job = 'police', mods = {} },
}
local playerPos = v3(bay.x, bay.y, bay.z)
local vehicles = {
    [10] = { plate = ' abc123 ', pos = v3(bay.x + 2, bay.y, bay.z) },
    [11] = { plate = 'FLEET1', pos = v3(500, 0, 0) },
}

env.Config = { jobs = { mechanic = { persistCosmetics = true } } }
env.source = 7
env.GetGameTimer = function() return now end
env.GetPlayerPed = function() return 1 end
env.GetEntityCoords = function(e) return e == 1 and playerPos or vehicles[e].pos end
env.GetAllVehicles = function() return { 10, 11 } end
env.GetVehicleNumberPlateText = function(e) return vehicles[e].plate end
env.GetVehicleEngineHealth = function() return 640.5 end
env.GetVehicleBodyHealth = function() return 5000 end
env.RegisterNetEvent = function(name, fn) handlers[name] = fn end
env.AddEventHandler = function() end
env.TriggerClientEvent = function(name, _, ...) clientEvents[#clientEvents + 1] = { name = name, ... } end
env.CreateThread = function() end
env.Wait = function() end
env.print = function() end
env.Kora = {
    callback = { register = function(name, fn) callbacks[name] = fn end },
    notify = { send = function(_, data) notices[#notices + 1] = data.message end },
    world = { resolveNetworkEntity = function(_, netId) return netId end },
}
env.exports = { kora_core = {
    getJob = function() return job end,
    getPlayerData = function() return citizen end,
    getByPlate = function(_, plate) return rows[plate] end,
    removeItem = function() return true end,
    saveVehicleProperties = function(_, plate, props) saved[#saved + 1] = { plate = plate, props = props } return true end,
} }

assert(loadfile(root .. 'jobs/mechanic/server.lua', 't', env))()
assert(loadfile(root .. 'jobs/mechanic/props.lua', 't', env))()

local save = handlers['qb-mechanicjob:server:SaveVehicleProps']
local complete = handlers['qbbusinesses:server:serviceCompleted']
local permit = callbacks['qbbusinesses:mechanic:permit']
equal(type(save), 'function', 'the legacy SaveVehicleProps event is still registered')

local function reset() for i = #saved, 1, -1 do saved[i] = nil end end
local function call(props)
    now = now + 5000
    save(props)
    return saved[#saved]
end
local function setJob(name, type, onduty) job = { name = name, type = type, onduty = onduty } end

-- A finished service for the car in vehicle slot 10 (the permit flow grants the matching save). Cosmetic
-- work needs a bodyshop job, so the player is one while it is done and has `after` as a job afterwards.
local function service(action, payload, after)
    local before = job
    setJob('bodyshop', 'bodyshop', true)
    local allowed, id = permit(env.source, action, 10)
    equal(allowed, true, action .. ' permit is granted in the bay')
    complete(id, payload)
    job = after or before
end

-- 1. Owner: wear only; tuning and unknown fields are dropped, stored mods are kept, health is read from the car.
setJob('unemployed', 'none', false); citizen = 'OWNER'
local out = call({ plate = 'ABC123', dirtLevel = 7, doorStatus = { ['0'] = true }, modSpoilers = 9, color1 = 3, fakeField = 1 })
equal(out ~= nil, true, 'owner wear save is stored')
equal(out.props.dirtLevel, 7, 'dirt is accepted')
equal(out.props.modSpoilers, 2, 'stored mods are kept')
equal(out.props.color1, nil, 'owner cannot save tuning')
equal(out.props.fakeField, nil, 'unknown fields are dropped')
equal(out.props.engineHealth, 640.5, 'engine health comes from the live vehicle')
equal(out.props.bodyHealth, 1000, 'body health is clamped to the live vehicle')

-- 2. F#339: an owner can only keep or worsen stored wear.
reset()
rows.ABC123.mods = {
    tankHealth = 400, tireHealth = { ['0'] = 300 }, tireBurstState = { ['1'] = true },
    windowStatus = { ['2'] = false }, doorStatus = { ['3'] = true },
}
out = call({
    plate = 'ABC123', tankHealth = 1000, tireHealth = { ['0'] = 1000, ['1'] = 800 },
    tireBurstState = { ['1'] = false, ['2'] = true }, windowStatus = { ['2'] = true, ['4'] = false },
    doorStatus = { ['3'] = false, ['5'] = true }, dirtLevel = 0,
})
equal(out ~= nil, true, 'a legacy saver sending healthy values still saves')
equal(out.props.tankHealth, 400, 'tank health cannot be restored')
equal(out.props.tireHealth['0'], 300, 'a damaged tyre cannot be repaired')
equal(out.props.tireHealth['1'], 800, 'new tyre damage is stored')
equal(out.props.tireBurstState['1'], true, 'a burst tyre cannot be un-burst')
equal(out.props.tireBurstState['2'], true, 'a new burst is stored')
equal(out.props.windowStatus['2'], false, 'a broken window cannot be restored')
equal(out.props.windowStatus['4'], false, 'a new broken window is stored')
equal(out.props.doorStatus['3'], true, 'a damaged door cannot be repaired')
equal(out.props.doorStatus['5'], true, 'new door damage is stored')
equal(out.props.dirtLevel, 0, 'dirt is not damage and may be cleaned')
rows.ABC123.mods = { modSpoilers = 2 }
reset()
out = call({ plate = 'ABC123', tankHealth = 700, windowStatus = { ['0'] = true } })
equal(out.props.tankHealth, 700, 'worse than the healthy default is stored')
equal(out.props.windowStatus['0'], true, 'an intact window with no stored damage stays intact')

-- 3. Strangers with no mechanic job are refused.
reset(); citizen = 'STRANGER'
equal(call({ plate = 'ABC123', dirtLevel = 1 }), nil, 'non-owner without a mechanic job is refused')

-- 4. F#336: an on-duty mechanic gets no free tuning.
reset(); setJob('mechanic', 'automotive', true)
equal(call({ plate = 'ABC123', modSpoilers = 5, color1 = { r = 1, g = 2, b = 3 }, modEngine = 3, modLivery = 9 }), nil,
    'arbitrary tuning with no service is refused')
out = call({ plate = 'ABC123', modEngine = 3, modTurbo = true, dirtLevel = 4 })
equal(out ~= nil and out.props.dirtLevel, 4, 'wear still saves for a mechanic')
equal(out.props.modEngine, nil, 'tuning is dropped, not persisted')
equal(out.props.modTurbo, nil, 'turbo is dropped')
equal(out.props.modSpoilers, 2, 'stored mods are untouched')

-- 5. A finished respray unlocks exactly that colour pair, once.
reset(); notices = {}
service('paint', { primary = 12, secondary = 34 })
equal(#clientEvents, 1, 'the service is still applied on the client')
out = call({ plate = 'ABC123', color1 = 99, color2 = 34, modEngine = 3 })
equal(out ~= nil, true, 'save with a granted key is stored')
equal(out.props.color1, nil, 'a colour that differs from the service is dropped')
equal(out.props.color2, 34, 'the serviced secondary colour is stored')
equal(out.props.modEngine, nil, 'tuning next to a granted key is still dropped')
reset()
out = call({ plate = 'ABC123', color1 = 12, color2 = 34 })
equal(out.props.color1, 12, 'the serviced primary colour is stored')
equal(out.props.color2, nil, 'the secondary grant was consumed by the first save')
reset()
equal(call({ plate = 'ABC123', color1 = 12, color2 = 34 }), nil, 'the grant is single-use')

-- 6. Bumper service, and the grant window / plate / player.
reset()
service('bumpers', { front = 3, rear = -1 })
out = call({ plate = 'ABC123', modFrontBumper = 3, modRearBumper = -1, modSpoilers = 8 })
equal(out.props.modFrontBumper, 3, 'serviced front bumper is stored')
equal(out.props.modRearBumper, -1, 'serviced rear bumper is stored')
equal(out.props.modSpoilers, 2, 'other mods cannot ride along')

reset()
service('paint', { primary = 5, secondary = 6 })
now = now + env.Mechanic.propsSave.grantLifetime + 1
equal(call({ plate = 'ABC123', color1 = 5, color2 = 6 }), nil, 'an expired grant unlocks nothing')

reset()
service('paint', { primary = 5, secondary = 6 })
env.source = 8
equal(call({ plate = 'ABC123', color1 = 5, color2 = 6 }), nil, 'another mechanic cannot use the grant')
env.source = 7
vehicles[11].pos = v3(bay.x + 3, bay.y, bay.z)
equal(call({ plate = 'FLEET1', color1 = 5, color2 = 6 }), nil, 'the grant only covers the serviced plate')
vehicles[11].pos = v3(500, 0, 0)
out = call({ plate = 'ABC123', color1 = 5, color2 = 6 })
equal(out ~= nil and out.props.color1, 5, 'the owner of the grant can still save it')

-- 7. persistCosmetics = false stops cosmetics being persisted.
reset()
env.Config.jobs.mechanic.persistCosmetics = false
service('paint', { primary = 7, secondary = 8 })
equal(call({ plate = 'ABC123', color1 = 7, color2 = 8 }), nil, 'persistCosmetics=false persists no cosmetics')
env.Config.jobs.mechanic.persistCosmetics = true
equal(call({ plate = 'ABC123', color1 = 7, color2 = 8 }), nil, 'a service done while disabled left no grant behind')

-- 8. No service, no grant: roadside and off-duty staff cannot start cosmetic work, so there is nothing to save.
reset()
setJob('roadside', 'automotive', true)
equal(select(1, permit(env.source, 'paint', 10)), false, 'roadside staff get no paint permit')
setJob('bodyshop', 'bodyshop', false)
equal(select(1, permit(env.source, 'paint', 10)), false, 'off-duty bodyshop staff get no paint permit')
equal(call({ plate = 'ABC123', color1 = 9, color2 = 10 }), nil, 'so nothing cosmetic can be saved')

-- 9. Vehicle proximity, bad input and rate limiting (unchanged behaviour).
reset(); setJob('mechanic', 'automotive', true)
equal(call({ plate = 'FLEET1', dirtLevel = 1 }), nil, 'the vehicle must be near the caller')
vehicles[11].pos = v3(bay.x + 3, bay.y, bay.z)
equal(call({ plate = 'FLEET1', dirtLevel = 1 }) ~= nil, true, 'a nearby vehicle is accepted')
vehicles[11].pos = v3(500, 0, 0)
reset()
equal(call({ plate = 'ABC123', dirtLevel = 99 }), nil, 'out-of-range wear is refused')
equal(call({ plate = 'ABC123', tireHealth = { ['99'] = 1 } }), nil, 'out-of-range tyre index is refused')
equal(call({ plate = ('X'):rep(40), dirtLevel = 1 }), nil, 'oversized plate is refused')
equal(call({ plate = 'NOPE00', dirtLevel = 1 }), nil, 'unknown plate is refused')
equal(call({ dirtLevel = 1 }), nil, 'missing plate is refused')
equal(call('x'), nil, 'non-table payload is refused')
equal(#saved, 0, 'nothing was stored by the refusals')
call({ plate = 'ABC123', dirtLevel = 1 })
save({ plate = 'ABC123', dirtLevel = 2 })
equal(#saved, 1, 'saves are rate limited per player')

-- 10. X11: the full repair message is not corrupted.
local file = assert(io.open(root .. 'jobs/mechanic/server.lua', 'rb'))
local source = file:read('a')
file:close()
equal(source:find('Mechanicured', 1, true), nil, 'no Mechanicured typo')
equal(source:find('configured garage bay', 1, true) ~= nil, true, 'full repair message reads "configured garage bay"')

print(('kora_businesses mechanic props: %d checks passed'):format(checks))
