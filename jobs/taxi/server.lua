local currentTaxis = {}
-- source -> entity of the depot taxi this job spawned for that player
local ownedTaxis = {}
local meterModels

local function warn(message)
    if Kora.print and Kora.print.warn then Kora.print.warn(('[taxi] %s'):format(message)) end
end

local function taxiPlayer(source)
    local player = exports.kora_core:getPlayer(source)
    if not player or not player.job or player.job.name ~= Taxi.jobRequired then
        return nil
    end
    if Config.jobs.taxi.requireOnDuty and player.job.onduty == false then
        return nil
    end
    return player
end

local function inMeteredVehicle(source)
    if not meterModels then
        meterModels = {}
        for _, model in ipairs(Taxi.Meter.vehicles) do
            meterModels[joaat(model)] = true
        end
    end
    local vehicle = GetVehiclePedIsIn(GetPlayerPed(source), false)
    return vehicle ~= 0 and meterModels[GetEntityModel(vehicle)] == true
end

local function removeOwnedTaxi(source)
    local entity = ownedTaxis[source]
    ownedTaxis[source] = nil
    if entity and DoesEntityExist(entity) then
        DeleteEntity(entity)
    end
end

local function clearPlayer(source)
    currentTaxis[source] = nil
    removeOwnedTaxi(source)
end

-- The depot taxi is a networked server-side vehicle so other players see it (and its driver).
Kora.callback.register('qb-taxi:spawnTaxi', function(source)
    if not taxiPlayer(source) then return nil end
    if not Kora.distance.player(source, Taxi.parkLocation, 15.0) then return nil end
    removeOwnedTaxi(source)
    local park = Taxi.parkLocation
    local netId = Kora.entities.createVehicle('taxi', { x = park.x, y = park.y, z = park.z, w = 0.0 }, 'automobile')
    if not netId or netId == 0 then return nil end
    local entity = NetworkGetEntityFromNetworkId(netId)
    SetEntityRoutingBucket(entity, GetPlayerRoutingBucket(source))
    ownedTaxis[source] = entity
    return netId
end)

RegisterNetEvent('qb-taxi:returnTaxi', function()
    clearPlayer(source)
end)

Kora.callback.register('qb-taxi:getPickupLocation', function(source)
    if not taxiPlayer(source) then return nil end
    local pickup, dropoff = Taxi.PickUp[math.random(1, #Taxi.PickUp)], Taxi.DropOffs[math.random(1, #Taxi.DropOffs)]
    currentTaxis[source] = {
        pickup = pickup,
        dropoff = dropoff,
        distance = Kora.util.vecDistance(pickup, dropoff),
        pickupComplete = false,
    }
    return {pickup = pickup, dropoff = dropoff}
end)

RegisterNetEvent('qb-taxi:pickup', function()
    local src = source
    if not taxiPlayer(src) then return end
    local trip = currentTaxis[src]
    if not trip then return warn(('no taxi trip for %s'):format(src)) end
    if not Kora.distance.player(src, trip.pickup, 5.0) then
        return warn(('%s is too far from the pickup location'):format(src))
    end
    if trip.pickupComplete then return end
    trip.pickupComplete = true
    trip.pickedUpAt = GetGameTimer()
end)

RegisterNetEvent('qb-taxi:dropOff', function()
    local src = source
    if not taxiPlayer(src) then return end
    local trip = currentTaxis[src]
    if not trip then return warn(('no taxi trip for %s'):format(src)) end
    if not Kora.distance.player(src, trip.dropoff, 5.0) then
        return warn(('%s is too far from the dropoff location'):format(src))
    end
    if not trip.pickupComplete then return warn(('%s dropped off before the pickup'):format(src)) end
    -- A real trip takes at least its straight-line distance at a believable speed; a teleport does not.
    local elapsed = (GetGameTimer() - trip.pickedUpAt) / 1000
    if elapsed < trip.distance / Config.jobs.taxi.minSpeedMps then
        currentTaxis[src] = nil
        return warn(('%s finished a %.0f m taxi trip in %.1f s; not paid'):format(src, trip.distance, elapsed))
    end
    if not inMeteredVehicle(src) then
        currentTaxis[src] = nil
        return warn(('%s finished a taxi trip outside a taxi; not paid'):format(src))
    end
    local pay = math.floor(trip.distance * Config.jobs.taxi.farePerMeter)
    exports.kora_core:addMoney(src, 'cash', pay)
    currentTaxis[src] = nil
    TriggerClientEvent('qb-taxi:client:spawnPickup', src)
end)

AddEventHandler('playerDropped', function()
    clearPlayer(source)
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(source)
    clearPlayer(source)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for source in pairs(ownedTaxis) do
        removeOwnedTaxi(source)
    end
end)
