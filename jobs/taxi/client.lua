
local taxi = nil
local ownsTaxi = false
local pickupLocation, destination, npc = nil, nil, nil
local pickupZone, dropOffZone = nil, nil

local function dropOff()
    SetNewWaypoint(destination.x, destination.y)
    dropOffZone = Kora.zones.box({
        coords = destination,
        size = vector3(5.0, 5.0, 5.0),
        rotation = 0,
        debug = false,
        onEnter = function()
            local departingNpc = npc
            TaskLeaveVehicle(npc, taxi, 0)
            dropOffZone.remove()
            TriggerServerEvent('qb-taxi:dropOff')
            TriggerEvent('qbtaxi:client:meterTripFinished')
            pickupLocation, destination = nil, nil
            CreateThread(function()
                Wait(5000)
                Kora.entities.remove(departingNpc)
            end)
        end,
    })
end

local function spawnPickup()
    local data = Kora.callback.trigger('qb-taxi:getPickupLocation')
    if not data then
        Kora.notify.send({ title = 'Taxi', message = 'You must be on duty as a taxi driver.', type = 'error' })
        return false
    end
    pickupLocation = data.pickup
    destination = data.dropoff
    npc = Kora.entities.create(Taxi.Peds[math.random(1, #Taxi.Peds)], pickupLocation, {})
    TaskStartScenarioInPlace(npc, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)
    SetEntityAsMissionEntity(npc, true, true)
    FreezeEntityPosition(npc, true)
    SetNewWaypoint(pickupLocation.x, pickupLocation.y)
    pickupZone = Kora.zones.box({
        coords = pickupLocation,
        size = vector3(5.0, 5.0, 5.0),
        rotation = 0,
        debug = false,
        onEnter = function()
            FreezeEntityPosition(taxi, true)
            local maxSeats, freeSeat = GetVehicleMaxNumberOfPassengers(taxi)
            for i = maxSeats - 1, 0, -1 do
                if IsVehicleSeatFree(taxi, i) then
                    freeSeat = i
                    break
                end
            end
            ClearPedTasksImmediately(npc)
            TriggerServerEvent('qb-taxi:pickup')
            FreezeEntityPosition(npc, false)
            TaskEnterVehicle(npc, taxi, -1, freeSeat, 1.0, 0)
            FreezeEntityPosition(taxi, false)
            TriggerEvent('qbtaxi:client:meterTrip', pickupLocation, destination)
            dropOff()
        end,
        onExit = function()
            pickupZone.remove()
        end,
    })
    return true
end

RegisterNetEvent('qb-taxi:client:spawnPickup', function()
    if source ~= 65535 then return end
    spawnPickup()
end)

Kora.interact.addBoxZone('taxi_veh', Taxi.parkLocation, vector4(4.0, 4.0, 3.0, 0.0), {
    {
        label = 'Spawn Taxi',
        action = function()
            taxi = Kora.entities.create('taxi', Taxi.parkLocation, {})
            ownsTaxi = true
            TaskWarpPedIntoVehicle(PlayerPedId(), taxi, -1)
            SetVehicleNumberPlateText(taxi, "TAXI")
            if not spawnPickup() then
                Kora.entities.remove(taxi)
                taxi = nil
            end
        end,
        canInteract = function()
            return taxi == nil
        end
    },
    {
        label = 'Return Taxi',
        action = function()
            if ownsTaxi then Kora.entities.remove(taxi) end
            ownsTaxi = false
            TriggerEvent('qbtaxi:client:meterTripFinished')
            taxi = nil
            pickupLocation, destination = nil, nil
            if pickupZone then
                pickupZone.remove()
                pickupZone = nil
            end
            if dropOffZone then
                dropOffZone.remove()
                dropOffZone = nil
            end
            if npc then
                Kora.entities.remove(npc)
                npc = nil
            end
        end,
        canInteract = function()
            return taxi ~= nil
        end
    }
}, false)

-- The stock radial menu requests a native route; the server still validates the taxi job and arrivals.
RegisterNetEvent('qb-taxi:client:DoTaxiNpc', function()
    if not Config.jobs.taxi.npcFromOwnTaxi then return end
    if pickupLocation or npc and DoesEntityExist(npc) then
        Kora.notify.send({ title = 'Taxi', message = 'Finish the current taxi trip first.', type = 'error' })
        return
    end
    local ped = PlayerPedId()
    local current = GetVehiclePedIsIn(ped, false)
    if current == 0 or GetPedInVehicleSeat(current, -1) ~= ped or GetEntityModel(current) ~= joaat('taxi') then
        Kora.notify.send({ title = 'Taxi', message = 'Use the driver seat of a taxi to request a trip.', type = 'error' })
        return
    end
    if taxi ~= current then taxi, ownsTaxi = current, false end
    spawnPickup()
end)
