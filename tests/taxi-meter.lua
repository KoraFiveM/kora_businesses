-- Lua meter/lifecycle contract; no game client or NUI rendering claim.
local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'
local events, nui, messages, threads, cacheHandlers = {}, {}, {}, {}, {}
local vehicle, seat, model, coords = 10, -1, 'taxi', { x = 0, y = 0, z = 0 }
local modelReads, threadsStarted = 0, 0
local env = {}
for name, value in pairs(_G) do env[name] = value end
env.Config = { jobs = { taxi = { meter = { enabled = true }, farePerMeter = 0.2 } } }
env.Taxi = { Meter = { defaultPrice = 125, startingPrice = 10, vehicles = { 'taxi' } } }
env.GetEntityModel = function() modelReads = modelReads + 1; return model end
env.joaat = function(x) return x end
env.GetCurrentResourceName = function() return 'kora_businesses' end
env.SendNUIMessage = function(data) messages[#messages + 1] = data end
env.RegisterNetEvent = function(name, fn) events[name] = fn end
env.AddEventHandler = env.RegisterNetEvent
env.RegisterNUICallback = function(name, fn) nui[name] = fn end
env.Kora = {
    notify = { send = function() end },
    cache = {
        vehicle = function() return vehicle end,
        seat = function() return seat end,
        coords = function() return coords end,
        onChange = function(key, fn) cacheHandlers[key] = fn end,
    },
}
env.Wait = function() coroutine.yield() end
env.CreateThread = function(fn)
    local co = coroutine.create(fn)
    threads[#threads + 1] = co
    threadsStarted = threadsStarted + 1
    assert(coroutine.resume(co))
end
local function tick()
    for _, co in ipairs(threads) do
        if coroutine.status(co) ~= 'dead' then assert(coroutine.resume(co)) end
    end
end
local function alive()
    local count = 0
    for _, co in ipairs(threads) do
        if coroutine.status(co) ~= 'dead' then count = count + 1 end
    end
    return count
end

local checks = 0
local function check(value, label)
    assert(value, label)
    checks = checks + 1
end
local function last() return messages[#messages] end
local function fire(name) events['qb-taxi:client:' .. name]() end

assert(loadfile(root .. 'jobs/taxi/meter.lua', 't', env))()
check(cacheHandlers.seat and cacheHandlers.vehicle, 'eligibility follows cache changes, not a poll')

seat = 0; fire('toggleMeter'); check(#messages == 0, 'passenger cannot open meter')
seat = -1; model = 'adder'; fire('toggleMeter'); check(#messages == 0, 'unsupported vehicle cannot open meter')
vehicle = false; model = 'taxi'; fire('toggleMeter'); check(#messages == 0, 'on foot cannot open meter')
vehicle = 10
fire('toggleMeter'); check(last().visible and not last().running, 'eligible driver opens stopped meter')
check(threadsStarted == 0, 'an open but stopped meter runs no thread')
fire('enableMeter'); check(last().running and alive() == 1, 'radial event starts actual state and one sampler')
modelReads = 0
coords = { x = 1609, y = 0, z = 0 }; tick()
check(last().meterData.distanceTraveled == 1 and last().meterData.currentFare == 135, 'mile conversion and configured starting fare')
local sentBefore = #messages
tick(); tick()
check(#messages == sentBefore, 'an unchanged fare is not republished')
check(modelReads == 0, 'ticks do not re-read the vehicle model')
fire('enableMeter'); check(not last().running and last().meterData.currentFare == 0, 'stop resets upstream meter totals')
local response
nui.enableMeter({ enabled = 'yes' }, function(value) response = value end); check(response == 'denied', 'NUI requires exact boolean')
nui.enableMeter({ enabled = true }, function(value) response = value end); check(response == 'ok' and last().running, 'NUI mirrors validated toggle')
fire('toggleMeter'); check(not last().visible, 'hide is effective')
coords = { x = 3218, y = 0, z = 0 }; tick(); fire('toggleMeter'); tick()
check(last().meterData.distanceTraveled == 0, 'hidden distance not silently added')
seat = 0; cacheHandlers.seat(0, -1); check(not last().visible and not last().running, 'seat change clears meter')
tick(); check(alive() == 0, 'sampler ends with the meter')

seat = -1; coords = { x = 0, y = 0, z = 0 }
events['qbtaxi:client:meterTrip']({ x = 0, y = 0, z = 0 }, { x = 1000, y = 0, z = 0 })
coords = { x = 500, y = 0, z = 0 }; tick()
check(last().meterData.currentFare == 100 and last().meterData.defaultPrice == 321.8, 'NPC display matches the configured server route rate')
env.Config.jobs.taxi.farePerMeter = 0.5
tick()
check(last().meterData.currentFare == 250, 'live fare-per-metre change applies')
env.Config.jobs.taxi.farePerMeter = 0.2
events['qbtaxi:client:meterTripFinished'](); check(last().meterData.currentFare == 0 and not last().running, 'NPC completion resets without payment event')

vehicle = 11; cacheHandlers.vehicle(11, 10); check(not last().visible, 'leaving the metered taxi closes the meter')
vehicle = 10
env.Config.jobs.taxi.meter.enabled = false
local count = #messages
fire('toggleMeter'); fire('enableMeter'); events['qbtaxi:client:meterTrip']({ x = 0, y = 0, z = 0 }, { x = 10, y = 0, z = 0 })
nui.enableMeter({ enabled = true }, function(value) response = value end)
check(#messages == count and response == 'denied', 'the meter toggle disables every entry point')
env.Config.jobs.taxi.meter.enabled = true

events['QBCore:Client:OnPlayerUnload'](); check(not last().visible, 'logout closes meter')
fire('toggleMeter'); events.onResourceStop('kora_businesses'); check(not last().visible, 'own stop closes meter')
events.onResourceStop('other'); fire('toggleMeter'); events.onResourceStop('other'); check(last().visible, 'other resource stop is ignored')
count = #messages
nui.meterReady({}, function(value) response = value end)
check(response == 'ok' and #messages == count + 1, 'late NUI ready always gets the current state')
print(('taxi meter: %d checks passed'):format(checks))
