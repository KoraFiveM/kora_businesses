local towDrivers = {}

local function getNewLocation()
    return math.random(1, #Tow.Locations.towspots)
end

Kora.callback.register('qb-tow:server:TakeOutVehicle', function(source)
    assert(source, "Source is nil")
    assert(Kora.distance.player(source, Tow.Locations.vehicle.coords, 10.0), "Player is too far from the vehicle location")
    assert(not towDrivers[source], "Player already has a tow vehicle out")

    local job = exports.kora_core:getPlayerData(source).job
    assert(job, "Player job data is nil")

    if job.name ~= 'tow' then return end

    exports.kora_vehiclekeys:giveKeys(source, 'TOW', true)

    towDrivers[source] = {
        location = getNewLocation(),
        droppedOff = 0,
        hasPickedUp = false
    }

    return towDrivers[source]
end)

Kora.callback.register('qb-tow:server:pickUp', function(source)
    assert(towDrivers[source], "Player does not have a tow vehicle out")

    local coords = Tow.Locations.towspots[towDrivers[source].location].coords

    if not Kora.distance.player(source, coords, 10.0) then
        return false
    end

    towDrivers[source].hasPickedUp = true
    return true
end)

Kora.callback.register('qb-tow:server:DropOff', function(source)
    assert(source, "Source is nil")
    assert(towDrivers[source], "Player does not have a tow vehicle out")
    assert(towDrivers[source].hasPickedUp, "Player has not picked up a vehicle")
    assert(Kora.distance.player(source, Tow.Locations.vehicle.coords, 10.0), "Player is too far from the tow yard")

    towDrivers[source].hasPickedUp = false
    towDrivers[source].droppedOff = towDrivers[source].droppedOff + 1
    towDrivers[source].location = getNewLocation()

    return towDrivers[source]
end)

Kora.callback.register('qb-tow:server:ReturnVehicle', function(source)
    assert(towDrivers[source], Kora.lang('tow.no_vehicle'))
    assert(Kora.distance.player(source, Tow.Locations.vehicle.coords, 10.0), Kora.lang('tow.vehicle_location'))

    if towDrivers[source].droppedOff > 0 then
        exports.kora_core:addMoney(source, 'bank', towDrivers[source].droppedOff * Tow.payPerVehicle)
        Kora.notify.send(source, {
            title = Kora.lang('tow.title'),
            message = Kora.lang('tow.payout',
                towDrivers[source].droppedOff * Tow.payPerVehicle,
                towDrivers[source].droppedOff
            ),
            type = 'success'
        })
    end

    towDrivers[source] = nil
    exports.kora_vehiclekeys:removeKeys(source, 'TOW')

    return true
end)
