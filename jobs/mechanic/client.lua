local state = { vehicle = 0, coords = nil, speed = 0.0, engineHealth = nil, bodyHealth = nil, nextTyreRoll = 0 }

local function eligible(vehicle)
    return vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == PlayerPedId()
        and not Mechanic.damage.excludedClasses[GetVehicleClass(vehicle)]
end

local function lowerHealth(vehicle, getter, setter, amount)
    if amount <= 0 then return end
    setter(vehicle, math.max(-4000.0, getter(vehicle) - amount))
end

local function reset(vehicle)
    if state.vehicle ~= 0 and DoesEntityExist(state.vehicle) then SetVehicleEngineTorqueMultiplier(state.vehicle, 1.0) end
    state.vehicle, state.coords, state.speed = vehicle or 0, nil, 0.0
    state.engineHealth, state.bodyHealth, state.nextTyreRoll = nil, nil, 0
end

local function rollTyreBurst(vehicle, speed)
    local tyres = Mechanic.damage.tyres
    if not tyres.enabled or speed < tyres.minSpeed or GetVehicleEngineHealth(vehicle) > tyres.minEngineHealth then return end
    local now = GetGameTimer()
    if now < state.nextTyreRoll then return end
    state.nextTyreRoll = now + tyres.checkInterval
    if math.random() >= tyres.chance then return end
    local wheels = GetVehicleNumberOfWheels(vehicle)
    if wheels > 0 then SetVehicleTyreBurst(vehicle, math.random(0, wheels - 1), tyres.burstOnRims, 1000.0) end
end

CreateThread(function()
    while true do
        Wait(Mechanic.damage.interval)
        if not Mechanic.damage.enabled then goto continue end
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        if not eligible(vehicle) then
            if state.vehicle ~= 0 then reset(0) end
            goto continue
        end
        if state.vehicle ~= vehicle then reset(vehicle) end

        local coords, speed = GetEntityCoords(vehicle), GetEntitySpeed(vehicle)
        local engineHealth, bodyHealth = GetVehicleEngineHealth(vehicle), GetVehicleBodyHealth(vehicle)
        if state.coords then
            local distance = #(coords - state.coords)
            if Mechanic.damage.distanceWear.enabled and speed >= Mechanic.damage.distanceWear.minSpeed then
                local km = distance / 1000.0
                lowerHealth(vehicle, GetVehicleEngineHealth, SetVehicleEngineHealth, km * Mechanic.damage.distanceWear.enginePerKm)
                lowerHealth(vehicle, GetVehicleBodyHealth, SetVehicleBodyHealth, km * Mechanic.damage.distanceWear.bodyPerKm)
            end

            local speedLoss = state.speed - speed
            -- Deceleration alone is not evidence of a crash: braking, handbrake
            -- turns and releasing the throttle can all exceed minSpeedLoss.
            -- Native health loss since our previous sample is persistent crash
            -- evidence, unlike HasEntityCollidedWithAnything (current frame only).
            local minHealthLoss = Mechanic.damage.collision.minNativeHealthLoss or 1.0
            local collisionDamage = state.engineHealth and state.bodyHealth
                and (engineHealth < state.engineHealth - minHealthLoss or bodyHealth < state.bodyHealth - minHealthLoss)
            if Mechanic.damage.collision.enabled and collisionDamage and speedLoss >= Mechanic.damage.collision.minSpeedLoss then
                lowerHealth(vehicle, GetVehicleEngineHealth, SetVehicleEngineHealth, math.min(Mechanic.damage.collision.maxEngineDamage, speedLoss * Mechanic.damage.collision.engineDamagePerSpeedLoss))
                lowerHealth(vehicle, GetVehicleBodyHealth, SetVehicleBodyHealth, math.min(Mechanic.damage.collision.maxBodyDamage, speedLoss * Mechanic.damage.collision.bodyDamagePerSpeedLoss))
            end
        end
        rollTyreBurst(vehicle, speed)

        local limp = Mechanic.damage.limpMode
        if limp.enabled and GetVehicleEngineHealth(vehicle) <= limp.engineHealthThreshold then
            SetVehicleEngineTorqueMultiplier(vehicle, limp.torqueMultiplier)
            if speed >= limp.stallMinSpeed and math.random() < limp.stallChance then SetVehicleEngineOn(vehicle, false, true, true) end
        else
            SetVehicleEngineTorqueMultiplier(vehicle, 1.0)
        end
        state.coords, state.speed = coords, speed
        state.engineHealth, state.bodyHealth = GetVehicleEngineHealth(vehicle), GetVehicleBodyHealth(vehicle)
        ::continue::
    end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() then reset(0) end
end)

local function notify(message, kind)
    Kora.notify.send({ title = 'Vehicle service', message = message, type = kind or 'info' })
end

local function playerJob()
    local ok, job = pcall(function() return exports.kora_core:getPlayerData({ 'job' }) end)
    return ok and job or nil
end

local function isOnDuty(job)
    return job and (not Mechanic.roles.requireOnDuty or job.onduty)
end

local function canRepair()
    local job = playerJob()
    return isOnDuty(job) and (job.name == Mechanic.roles.fullRepairJob or job.type == Mechanic.roles.automotiveType)
end

local function canFullRepair()
    local job = playerJob()
    return canRepair() and not Mechanic.roles.roadsideJobs[job.name]
end

local function canUseBodyshop()
    local job = playerJob()
    return isOnDuty(job) and (Mechanic.roles.bodyshopJobs[job.name] or Mechanic.roles.bodyshopTypes[job.type])
end

local function servicePayload(action, vehicle)
    if action == 'paint' then
        local primary, secondary = GetVehicleColours(vehicle)
        local response = Kora.nui.openInputDialog({
            { id = 'primary', label = 'Primary paint index', type = 'number', default = primary, min = Mechanic.cosmetics.paintColourMin, max = Mechanic.cosmetics.paintColourMax, required = true },
            { id = 'secondary', label = 'Secondary paint index', type = 'number', default = secondary, min = Mechanic.cosmetics.paintColourMin, max = Mechanic.cosmetics.paintColourMax, required = true },
        }, 'Respray vehicle', 'GTA palette indices; both colours are applied after the service.')
        if not response or response.cancelled then return nil end
        return { primary = math.floor(response.values.primary), secondary = math.floor(response.values.secondary) }
    end
    if action == 'bumpers' then
        SetVehicleModKit(vehicle, 0)
        local front, rear = GetVehicleMod(vehicle, 1), GetVehicleMod(vehicle, 2)
        local response = Kora.nui.openInputDialog({
            { id = 'front', label = 'Front bumper variation (-1 stock)', type = 'number', default = front, min = -1, max = Mechanic.cosmetics.bumperModMax, required = true },
            { id = 'rear', label = 'Rear bumper variation (-1 stock)', type = 'number', default = rear, min = -1, max = Mechanic.cosmetics.bumperModMax, required = true },
        }, 'Customise bumpers', 'Values are clamped to variations supported by this vehicle.')
        if not response or response.cancelled then return nil end
        return { front = math.floor(response.values.front), rear = math.floor(response.values.rear) }
    end
    return {}
end

local function durationFor(action)
    if action == 'fullRepair' then return Mechanic.fullRepair.duration end
    if action == 'roadsideRepair' then return Mechanic.roadsideRepair.duration end
    return Mechanic.cosmetics.duration
end

local function labelFor(action)
    if action == 'fullRepair' then return Mechanic.fullRepair.label end
    if action == 'roadsideRepair' then return Mechanic.roadsideRepair.label end
    if action == 'paint' then return 'Respraying vehicle' end
    return 'Fitting bumper components'
end

local function beginService(action, vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    local payload = servicePayload(action, vehicle)
    if payload == nil then return end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if not netId or netId == 0 then return notify('This vehicle is not networked and cannot be serviced.', 'error') end

    local allowed, permitOrReason = Kora.callback.trigger('qbbusinesses:mechanic:permit', action, netId)
    if not allowed then return notify(permitOrReason or 'Service could not be authorised.', 'error') end

    local completed = Kora.progressbar.start({
        label = labelFor(action), duration = durationFor(action), canCancel = true,
        scenario = { name = 'WORLD_HUMAN_VEHICLE_MECHANIC' }, disable = { move = true, combat = true },
    })
    if not completed then return notify('Service cancelled.', 'warning') end
    TriggerServerEvent('qbbusinesses:server:serviceCompleted', permitOrReason, payload)
end

local function fixOneTyre(vehicle)
    for index = 0, GetVehicleNumberOfWheels(vehicle) - 1 do
        if IsVehicleTyreBurst(vehicle, index, false) then
            SetVehicleTyreFixed(vehicle, index)
            return true
        end
    end
    return false
end

RegisterNetEvent('qbbusinesses:client:serviceApplied', function(action, netId, payload)
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle)
        or not Kora.entities.requestControl(vehicle, 2000) then
        return notify('Could not obtain control of the vehicle. Try again.', 'error')
    end

    if action == 'fullRepair' then
        SetVehicleFixed(vehicle)
        SetVehicleDeformationFixed(vehicle)
        SetVehicleEngineHealth(vehicle, 1000.0)
        SetVehicleBodyHealth(vehicle, 1000.0)
        SetVehiclePetrolTankHealth(vehicle, 1000.0)
        SetVehicleUndriveable(vehicle, false)
        notify('Full repair completed.', 'success')
    elseif action == 'roadsideRepair' then
        SetVehicleEngineHealth(vehicle, math.max(GetVehicleEngineHealth(vehicle), Mechanic.roadsideRepair.engineHealthFloor))
        SetVehicleBodyHealth(vehicle, math.max(GetVehicleBodyHealth(vehicle), Mechanic.roadsideRepair.bodyHealthFloor))
        if Mechanic.roadsideRepair.repairOneTyre then fixOneTyre(vehicle) end
        SetVehicleUndriveable(vehicle, false)
        notify('Vehicle stabilised. It still needs a full garage repair.', 'success')
    elseif action == 'paint' then
        SetVehicleColours(vehicle, payload.primary, payload.secondary)
        notify('Respray completed.', 'success')
    elseif action == 'bumpers' then
        SetVehicleModKit(vehicle, 0)
        for _, entry in ipairs({ { type = 1, value = payload.front }, { type = 2, value = payload.rear } }) do
            local count = GetNumVehicleMods(vehicle, entry.type)
            local value = math.min(entry.value, count - 1)
            SetVehicleMod(vehicle, entry.type, value >= 0 and value or -1, false)
        end
        notify('Bumper customisation completed.', 'success')
    end
end)

exports['qb-target']:AddGlobalVehicle({ options = {
    -- kora_target invokes legacy `action` handlers inside a protected dispatch;
    -- start a fresh coroutine because dialogs, callbacks and progress bars all
    -- yield while the player works.
    { icon = 'fas fa-wrench', label = 'Full garage repair', action = function(entity) CreateThread(function() beginService('fullRepair', entity) end) end, canInteract = canFullRepair, distance = Mechanic.interaction.distance },
    { icon = 'fas fa-truck-pickup', label = 'Roadside stabilisation', action = function(entity) CreateThread(function() beginService('roadsideRepair', entity) end) end, canInteract = canRepair, distance = Mechanic.interaction.distance },
    { icon = 'fas fa-paint-roller', label = 'Respray vehicle', action = function(entity) CreateThread(function() beginService('paint', entity) end) end, canInteract = canUseBodyshop, distance = Mechanic.interaction.distance },
    { icon = 'fas fa-car', label = 'Customise bumpers', action = function(entity) CreateThread(function() beginService('bumpers', entity) end) end, canInteract = canUseBodyshop, distance = Mechanic.interaction.distance },
} })
