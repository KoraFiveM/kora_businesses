-- The damage worker must not exist while on foot, start on the cache 'seat' or
-- 'vehicle' change, never duplicate, end itself when driving stops, and
-- re-register on a kora_lib restart without duplicating on a normal load.
local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'
local env = {}
for name, value in pairs(_G) do env[name] = value end
env.Globals = {}
env.vector3 = function(x, y, z) return { x = x, y = y, z = z } end
assert(loadfile(root .. 'jobs/mechanic/shared.lua', 't', env))()

local threads, handlers, startHandlers = {}, {}, {}
local registrations, driving = 0, false
local samples, resets = 0, 0
env.Kora = {
    cache = {
        onChange = function(key, fn) registrations = registrations + 1; handlers[key] = fn end,
    },
    notify = { send = function() end },
}
env.CreateThread = function(fn) threads[#threads + 1] = coroutine.create(fn) end
env.Wait = function() coroutine.yield() end
env.AddEventHandler = function(name, fn)
    if name == 'onClientResourceStart' then startHandlers[#startHandlers + 1] = fn end
end
env.RegisterNetEvent = function() end
env.exports = setmetatable({}, { __index = function() return setmetatable({}, { __index = function() return function() end end }) end })
env.GetCurrentResourceName = function() return 'kora_businesses' end
env.PlayerPedId = function() return 1 end
env.GetVehiclePedIsIn = function() samples = samples + 1; return driving and 99 or 0 end
env.GetPedInVehicleSeat = function() return 1 end
env.GetVehicleClass = function() return 0 end
env.DoesEntityExist = function() return false end
env.SetVehicleEngineTorqueMultiplier = function() resets = resets + 1 end
env.GetEntityCoords = function() return env.vector3(0, 0, 0) end
env.GetEntitySpeed = function() return 0.0 end
env.GetVehicleEngineHealth = function() return 1000.0 end
env.GetVehicleBodyHealth = function() return 1000.0 end
env.GetGameTimer = function() return 0 end
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

equal(#threads, 0, 'no worker thread is created while on foot')
equal(type(handlers.seat), 'function', 'start is driven by the cache seat change')
equal(type(handlers.vehicle), 'function', 'start is driven by the cache vehicle change')
equal(registrations, 2, 'a normal load registers each listener once')
equal(#startHandlers, 1, 'one kora_lib restart handler is registered')

driving = true
handlers.vehicle(99)
equal(alive(), 1, 'entering a vehicle starts one worker')
handlers.seat(-1)
handlers.vehicle(99)
equal(#threads, 1, 'repeated change events do not start a second worker')
step(); step()
equal(samples >= 1, true, 'worker polls while driving')

driving = false
step()
equal(alive(), 0, 'worker ends itself once driving stops')
local before = samples
step(); step()
equal(samples, before, 'no polling after driving stops')

driving = true
handlers.seat(-1)
equal(alive(), 1, 'driving again starts the worker again')
driving = false
step(); step()
equal(alive(), 0, 'worker ends again')

startHandlers[1]('some_other_resource')
equal(registrations, 2, 'unrelated resource starts do not re-register')
handlers = {}
driving = true
startHandlers[1]('kora_lib')
equal(registrations, 4, 'kora_lib restart re-registers both listeners')
equal(type(handlers.seat) == 'function' and type(handlers.vehicle) == 'function', true, 'restart restores seat and vehicle listeners')
equal(alive(), 1, 'restart seeds the worker from the current driving state')
startHandlers[1]('kora_lib')
equal(alive(), 1, 'a second seed does not duplicate the worker')

print('kora_businesses mechanic: ' .. checks .. ' driving worker checks passed')
