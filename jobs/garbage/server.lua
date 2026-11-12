local onJob = {}

local function newRoute()
    local route = {}
    local available = {}

    for i = 1, #Garbage.Locations.trashcan do
        available[i] = i
    end

    for i = #available, 2, -1 do
        local j = math.random(i)
        available[i], available[j] = available[j], available[i]
    end

    local stopCount = math.min(
        math.random(Garbage.MinStops, Garbage.MaxStops),
        #available
    )

    for i = 1, stopCount do
        route[i] = {
            stop = available[i],
            bags = math.random(Garbage.MinBagsPerStop, Garbage.MaxBagsPerStop),
        }
    end

    return route
end

local function getCurrentStop(job)
    return job and job.route and job.route[job.routeIndex]
end

local function isGarbageJob(source)
    local Player = exports.kora_core:getPlayerData(source)
    return Player and Player.job and Player.job.name == 'garbage'
end

local function getTruck(job)
    if not job or not job.vehicleNet then return 0 end

    local vehicle = NetworkGetEntityFromNetworkId(job.vehicleNet)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return 0
    end

    return vehicle
end

local function isNearEntity(source, entity, distance)
    if entity == 0 then return false end

    local ped = GetPlayerPed(source)
    if ped == 0 then return false end

    return #(GetEntityCoords(ped) - GetEntityCoords(entity)) <= distance
end

Kora.callback.register('qb-garbagejob:spawnTruck', function(source)
    if onJob[source] then
        return false
    end

    if not isGarbageJob(source) then
        return false
    end

    local route = newRoute()

    onJob[source] = {
        route = route,
        routeIndex = 1,
        pickedUp = 0,
        deposited = 0,
        vehicleNet = nil,
    }
    return route
end)

Kora.callback.register('qb-garbagejob:setTruck', function(source, vehicleNet)
    local job = onJob[source]
    if not job or job.vehicleNet then
        return false
    end

    if type(vehicleNet) ~= 'number' or vehicleNet <= 0 then
        return false
    end

    local vehicle = NetworkGetEntityFromNetworkId(vehicleNet)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return false
    end

    if GetEntityModel(vehicle) ~= joaat(Garbage.Vehicle) then
        return false
    end

    -- The depot NPC is up to 23 metres from the configured truck spawns.
    if not isNearEntity(source, vehicle, 30.0) then
        return false
    end

    job.vehicleNet = vehicleNet
    pcall(function() exports.kora_vehiclekeys:giveKeys(source, 'GARBAGE') end)
    return true
end)

Kora.callback.register('qb-garbagejob:collectBag', function(source, stopId)
    local job = onJob[source]
    if not job then return false end

    local current = getCurrentStop(job)
    if not current or current.stop ~= stopId then
        return false
    end

    if job.pickedUp >= current.bags then
        return false
    end

    local stop = Garbage.Locations.trashcan[stopId]
    if not stop or not Kora.distance.player(source, stop.coords, 4.0) then
        return false
    end

    job.pickedUp += 1
    return true
end)

Kora.callback.register('qb-garbagejob:depositBag', function(source, stopId)
    local job = onJob[source]
    if not job then return false end

    local current = getCurrentStop(job)
    if not current or current.stop ~= stopId then
        return false
    end

    if job.deposited >= job.pickedUp or job.deposited >= current.bags then
        return false
    end

    local vehicle = getTruck(job)
    if vehicle == 0 or not isNearEntity(source, vehicle, 6.0) then
        return false
    end

    job.deposited += 1
    return true
end)

Kora.callback.register('qb-garbagejob:completeStop', function(source, routeIndex)
    local job = onJob[source]
    if not job or job.routeIndex ~= routeIndex then
        return false
    end

    local current = getCurrentStop(job)
    if not current then
        return false
    end

    if job.pickedUp ~= current.bags or job.deposited ~= current.bags then
        return false
    end

    job.routeIndex += 1
    job.pickedUp = 0
    job.deposited = 0

    return true
end)

Kora.callback.register('qb-garbagejob:returnTruck', function(source, vehicleNet)
    local job = onJob[source]
    if not job or job.routeIndex <= #job.route then
        return false
    end

    if job.vehicleNet ~= vehicleNet then
        return false
    end

    local vehicle = getTruck(job)
    if vehicle == 0 then
        return false
    end

    if GetEntityModel(vehicle) ~= joaat(Garbage.Vehicle) then
        return false
    end

    if not isNearEntity(source, vehicle, Garbage.ReturnDistance) then
        return false
    end

    if not Kora.distance.player(source, Garbage.Locations.main, Garbage.ReturnDistance) then
        return false
    end

    if job.returning then return false end
    job.returning = true

    local stops = #job.route
    local payment = stops * 50

    if not exports.kora_core:addMoney(source, 'bank', payment, 'garbage-route') then
        job.returning = nil
        return false
    end

    DeleteEntity(vehicle)
    onJob[source] = nil

    return payment
end)

Kora.callback.register('qb-garbagejob:cancel', function(source)
    local job = onJob[source]
    if not job then
        return true
    end

    local vehicle = getTruck(job)
    if vehicle ~= 0 then
        DeleteEntity(vehicle)
    end

    onJob[source] = nil
    return true
end)

AddEventHandler('playerDropped', function()
    onJob[source] = nil
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        onJob = {}
    end
end)
