-- Legacy meter events used by qb-radialmenu. This is a fare display, never payment authority.
local visible, running, vehicle, previous, miles, fare, trip = false, false, nil, nil, 0, 0, nil
local watching = false
-- What the NUI was last told, so an unchanged meter does not re-render every tick.
local sent = { visible = false, running = false, fare = 0, miles = 0, price = nil }
local modelSet

local function meterEnabled()
    return Config.jobs.taxi.meter.enabled == true
end

local function distance(a, b)
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
end

local function meterModels()
    if not modelSet then
        modelSet = {}
        for _, model in ipairs(Taxi.Meter.vehicles) do
            modelSet[joaat(model)] = true
        end
    end
    return modelSet
end

-- The vehicle the local player is driving, if it is a metered model.
local function driver()
    local current = Kora.cache.vehicle()
    if not current or Kora.cache.seat() ~= -1 then return nil end
    if meterModels()[GetEntityModel(current)] then return current end
end

local function publish(force)
    local price = trip and Config.jobs.taxi.farePerMeter * 1609 or Taxi.Meter.defaultPrice
    if not force and sent.visible == visible and sent.running == running and sent.fare == fare
        and sent.miles == miles and sent.price == price then
        return
    end
    sent.visible, sent.running, sent.fare, sent.miles, sent.price = visible, running, fare, miles, price
    SendNUIMessage({
        action = 'meterState', visible = visible, running = running,
        meterData = { defaultPrice = price, currentFare = fare, distanceTraveled = miles },
    })
end

local function stop()
    visible, running, vehicle, previous, miles, fare, trip = false, false, nil, nil, 0, 0, nil
    publish()
end

-- One sampling thread, alive only while a visible meter is running.
local function watch()
    if watching or not (visible and running) then return end
    watching = true
    CreateThread(function()
        while visible and running do
            Wait(2000)
            if not (visible and running) then break end
            local coords = Kora.cache.coords()
            if trip then
                local travelled = math.max(0, math.min(trip.distance, trip.distance - distance(coords, trip.destination)))
                miles, fare = travelled / 1609, math.floor(travelled * Config.jobs.taxi.farePerMeter)
            elseif previous then
                miles = miles + distance(previous, coords) / 1609
                fare = math.floor(miles * Taxi.Meter.defaultPrice + Taxi.Meter.startingPrice)
            end
            publish()
            previous = coords
        end
        watching = false
    end)
end

local function setRunning(enabled)
    if not visible or driver() ~= vehicle then return false end
    running = enabled == true
    previous = Kora.cache.coords()
    if not running then miles, fare = 0, 0 end
    publish()
    watch()
    return true
end

-- Losing the driver seat (or the taxi) closes the meter; no per-tick check needed.
local function recheck()
    if visible and driver() ~= vehicle then stop() end
end
Kora.cache.onChange('vehicle', recheck)
Kora.cache.onChange('seat', recheck)

RegisterNetEvent('qb-taxi:client:toggleMeter', function()
    if not meterEnabled() then return end
    if visible then
        visible = false
        publish()
        return
    end
    local current = driver()
    if not current then
        Kora.notify.send({ title = 'Taxi', message = 'Use the driver seat of a taxi to open its meter.', type = 'error' })
        return
    end
    if current ~= vehicle then running, miles, fare, trip = false, 0, 0, nil end
    vehicle, previous, visible = current, Kora.cache.coords(), true
    publish()
    watch()
end)

RegisterNetEvent('qb-taxi:client:enableMeter', function()
    if not meterEnabled() then return end
    if not setRunning(not running) then
        Kora.notify.send({ title = 'Taxi', message = 'Open the taxi meter first.', type = 'error' })
    end
end)

RegisterNUICallback('enableMeter', function(data, cb)
    cb(meterEnabled() and type(data) == 'table' and type(data.enabled) == 'boolean' and setRunning(data.enabled) and 'ok' or 'denied')
end)

RegisterNUICallback('meterReady', function(_, cb)
    publish(true)
    cb('ok')
end)

-- Local gameplay hooks: native route data drives the display, while server distance/arrival checks own NPC pay.
AddEventHandler('qbtaxi:client:meterTrip', function(pickup, destination)
    if not meterEnabled() then return end
    local current = driver()
    if not current then return end
    vehicle, visible, running = current, true, true
    trip = { distance = distance(pickup, destination), destination = destination }
    previous, miles, fare = Kora.cache.coords(), 0, 0
    publish()
    watch()
end)

AddEventHandler('qbtaxi:client:meterTripFinished', function()
    running, miles, fare, trip = false, 0, 0, nil
    publish()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', stop)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then stop() end
end)
