-- The damage sampler must not exist while on foot, start on the cache 'vehicle'
-- edge, keep running across vehicle swaps and end itself when the player exits.
local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'
local env = {}
for name, value in pairs(_G) do env[name] = value end
env.Globals = {}
env.vector3 = function(x, y, z) return { x = x, y = y, z = z } end
assert(loadfile(root .. 'jobs/mechanic/shared.lua', 't', env))()

local threads, changeHandlers, cached = {}, {}, false
local samples, resets = 0, 0
env.Kora = {
    cache = {
        vehicle = function() return cached end,
        onChange = function(key, fn) changeHandlers[key] = fn end,
    },
    notify = { send = function() end },
}
env.CreateThread = function(fn) threads[#threads + 1] = coroutine.create(fn) end
env.Wait = function() coroutine.yield() end
env.AddEventHandler = function() end
env.RegisterNetEvent = function() end
env.exports = setmetatable({}, { __index = function() return setmetatable({}, { __index = function() return function() end end }) end })
env.GetCurrentResourceName = function() return 'kora_businesses' end
env.PlayerPedId = function() return 1 end
env.GetVehiclePedIsIn = function() samples = samples + 1; return 0 end
env.DoesEntityExist = function() return false end
env.SetVehicleEngineTorqueMultiplier = function() resets = resets + 1 end
assert(loadfile(root .. 'jobs/mechanic/client.lua', 't', env))()

local checks = 0
local function equal(actual, expected, message)
    checks = checks + 1
    if actual ~= expected then error(('%s: expected %s, got %s'):format(message, tostring(expected), tostring(actual)), 2) end
end
local function step()
    for _, thread in ipairs(threads) do
        if coroutine.status(thread) == 'suspended' then assert(coroutine.resume(thread)) end
    end
end
local function alive()
    local count = 0
    for _, thread in ipairs(threads) do if coroutine.status(thread) ~= 'dead' then count = count + 1 end end
    return count
end

equal(#threads, 0, 'no sampler thread is created while on foot')
equal(type(changeHandlers.vehicle), 'function', 'start is driven by the cache vehicle change')

changeHandlers.vehicle(42)
equal(alive(), 1, 'entering a vehicle starts one sampler')
changeHandlers.vehicle(43)
equal(#threads, 1, 'swapping vehicles does not start a second sampler')
step(); step()
equal(samples >= 1, true, 'sampler polls while in a vehicle')

changeHandlers.vehicle(false)
step()
equal(alive(), 0, 'sampler ends itself once the player is on foot')
local before = samples
step(); step()
equal(samples, before, 'no sampling after leaving the vehicle')

changeHandlers.vehicle(44)
equal(alive(), 1, 're-entering a vehicle starts the sampler again')

print('kora_businesses mechanic: ' .. checks .. ' vehicle-edge sampler checks passed')
