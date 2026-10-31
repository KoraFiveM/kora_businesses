local permits = {}
local permitCounter = 0

local function notify(src, message, kind)
    Kora.notify.send(src, { title = 'Vehicle service', message = message, type = kind or 'error' })
end

local function getVehicle(src, netId)
    return Kora.world.resolveNetworkEntity(src, netId, {
        entityType = 'vehicle',
        maxDistance = Mechanic.interaction.distance,
    })
end

local function nearGarage(vehicle)
    if not Mechanic.fullRepair.requireGarage then return true end
    local vehicleCoords = GetEntityCoords(vehicle)
    for _, coords in ipairs(Mechanic.fullRepair.garages) do
        if #(vehicleCoords - coords) <= Mechanic.fullRepair.garageRadius then return true end
    end
    return false
end

local function roleFor(src)
    local job = exports.kora_core:getJob(src)
    if not job then return nil end
    if Mechanic.roles.requireOnDuty and not job.onduty then return nil end
    return job
end

local function canPerform(src, action, vehicle)
    local job = roleFor(src)
    if not job then return false, 'You must be on duty to do that.' end

    local isRoadside = Mechanic.roles.roadsideJobs[job.name] == true
    local isAutomotive = job.name == Mechanic.roles.fullRepairJob or job.type == Mechanic.roles.automotiveType
    local isBodyshop = Mechanic.roles.bodyshopJobs[job.name] == true or Mechanic.roles.bodyshopTypes[job.type] == true

    if action == 'fullRepair' then
        if not isAutomotive or isRoadside then return false, 'Only a qualified mechanic can complete a full repair.' end
        if not nearGarage(vehicle) then return false, 'A full repair must be completed in a Mechanicured garage bay.' end
        return true
    end
    if action == 'roadsideRepair' then
        if not isAutomotive then return false, 'Only automotive staff can stabilise a vehicle.' end
        return true
    end
    if action == 'paint' or action == 'bumpers' then
        if not isBodyshop then return false, 'Only bodyshop staff can change vehicle cosmetics.' end
        return true
    end
    return false, 'Unknown vehicle service action.'
end

local function itemCost(action)
    if action == 'fullRepair' then return Mechanic.fullRepair.consume end
    if action == 'roadsideRepair' then return Mechanic.roadsideRepair.consume end
    return Mechanic.cosmetics.consume
end

local function validPayload(action, payload)
    if action == 'fullRepair' or action == 'roadsideRepair' then return payload == nil or type(payload) == 'table' end
    if type(payload) ~= 'table' then return false end
    if action == 'paint' then
        local lo, hi = Mechanic.cosmetics.paintColourMin, Mechanic.cosmetics.paintColourMax
        return type(payload.primary) == 'number' and payload.primary % 1 == 0 and payload.primary >= lo and payload.primary <= hi
            and type(payload.secondary) == 'number' and payload.secondary % 1 == 0 and payload.secondary >= lo and payload.secondary <= hi
    end
    if action == 'bumpers' then
        local max = Mechanic.cosmetics.bumperModMax
        return type(payload.front) == 'number' and payload.front % 1 == 0 and payload.front >= -1 and payload.front <= max
            and type(payload.rear) == 'number' and payload.rear % 1 == 0 and payload.rear >= -1 and payload.rear <= max
    end
    return false
end

local function makePermit(src, action, netId)
    permitCounter = permitCounter + 1
    local id = ('%d:%d:%d'):format(src, GetGameTimer(), permitCounter)
    permits[id] = { src = src, action = action, netId = netId, expires = GetGameTimer() + Mechanic.interaction.permitLifetime }
    return id
end

Kora.callback.register('qbbusinesses:mechanic:permit', function(src, action, netId)
    local vehicle = getVehicle(src, netId)
    if not vehicle then return false, 'Move closer to a valid vehicle.' end
    local allowed, reason = canPerform(src, action, vehicle)
    if not allowed then return false, reason end
    return true, makePermit(src, action, netId)
end, { rateLimit = Mechanic.interaction.permitRateLimit })

RegisterNetEvent('qbbusinesses:server:serviceCompleted', function(permitId, payload)
    local src = source
    local permit = permits[permitId]
    permits[permitId] = nil -- permits are single-use even if validation fails
    if not permit or permit.src ~= src or permit.expires < GetGameTimer() then
        return notify(src, 'That service authorisation expired. start again.', 'error')
    end

    local vehicle = getVehicle(src, permit.netId)
    if not vehicle then return notify(src, 'Move closer to the vehicle and start again.', 'error') end
    local allowed, reason = canPerform(src, permit.action, vehicle)
    if not allowed then return notify(src, reason, 'error') end
    if not validPayload(permit.action, payload) then return notify(src, 'The requested vehicle modification is invalid.', 'error') end

    local cost = itemCost(permit.action)
    if cost then
        local removed, err = exports.kora_core:removeItem(src, cost.item, cost.amount or 1, nil, 'vehicle service')
        if not removed then return notify(src, ('Required item missing: %s.'):format(err or cost.item), 'error') end
    end
    TriggerClientEvent('qbbusinesses:client:serviceApplied', src, permit.action, permit.netId, payload)
end)

AddEventHandler('playerDropped', function()
    local src = source
    for id, permit in pairs(permits) do if permit.src == src then permits[id] = nil end end
end)

CreateThread(function()
    while true do
        Wait(60000)
        local now = GetGameTimer()
        for id, permit in pairs(permits) do if permit.expires < now then permits[id] = nil end end
    end
end)
