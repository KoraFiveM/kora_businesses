local blips = {}
local garbage = {
    truck = nil,
    route = nil,
    routeIndex = 1,
    bags = 0,
    bagsRequired = 0,
    collectedForStop = 0,
    bagObject = nil,
    stopZone = nil,
    truckTargetAdded = false,
    busy = false,
}
local depotRoute = false

local BAG_MODEL = `hei_prop_heist_binbag`
local BAG_ANIM_DICT = 'missfbi4prepp1'
local BAG_ANIM_NAME = '_idle_garbage_man'

local function removeBlips()
    for _, blip in pairs(blips) do
        Kora.blips.remove(blip)
    end
    blips = {}
    depotRoute = false
end

local function createDepotBlip(route)
    if route == nil then route = depotRoute end
    route = route == true

    if blips.depot then
        if depotRoute == route then return end
        Kora.blips.remove(blips.depot)
        blips.depot = nil
    end

    for _, blipData in pairs(Garbage.BlipData) do
        blips.depot = Kora.blips.create(blipData.coords, {
            label = blipData.label,
            sprite = blipData.sprite,
            color = blipData.color,
            scale = blipData.scale,
            display = blipData.display,
            route = route,
        })
    end

    depotRoute = route
end

local function removeStopZone()
    if garbage.stopZone then
        exports.kora_target:removeZone(garbage.stopZone)
        garbage.stopZone = nil
    end
end

local function clearBag()
    if garbage.bagObject and DoesEntityExist(garbage.bagObject) then
        DeleteEntity(garbage.bagObject)
    end

    garbage.bagObject = nil
    garbage.bags = 0
    ClearPedSecondaryTask(PlayerPedId())
end

local function createStopBlip(stopId)
    if blips.stop then
        Kora.blips.remove(blips.stop)
        blips.stop = nil
    end

    local stop = Garbage.Locations.trashcan[stopId]
    if not stop then return end

    blips.stop = Kora.blips.create(stop.coords, {
        label = ('Garbage Stop %s'):format(stopId),
        sprite = 318,
        color = 5,
        scale = 0.8,
        shortRange = false,
        route = true,
    })
end

local function attachBag()
    if garbage.bagObject then return false end

    local ped = PlayerPedId()

    if not Kora.stream.loadModel(BAG_MODEL) then return false end

    local coords = GetEntityCoords(ped)
    garbage.bagObject = CreateObject(BAG_MODEL, coords.x, coords.y, coords.z, true, true, false)

    AttachEntityToEntity(
        garbage.bagObject,
        ped,
        GetPedBoneIndex(ped, 57005),
        0.12, 0.0, -0.05,
        25.0, 270.0, 180.0,
        true, true, false, true, 1, true
    )

    SetModelAsNoLongerNeeded(BAG_MODEL)

    -- The dict must be streamed in first or TaskPlayAnim silently does nothing.
    local animOk, dict = pcall(Kora.stream.loadAnimDict, BAG_ANIM_DICT)
    if animOk and dict then
        TaskPlayAnim(ped, BAG_ANIM_DICT, BAG_ANIM_NAME, 8.0, -8.0, -1, 49, 0.0, false, false, false)
    end

    return true
end

local function removeCurrentStop()
    removeStopZone()

    if blips.stop then
        Kora.blips.remove(blips.stop)
        blips.stop = nil
    end
end

local function addStopZone(stopId)
    local stop = Garbage.Locations.trashcan[stopId]
    if not stop then return end

    garbage.stopZone = exports.kora_target:addBoxZone({
        coords = vector3(stop.coords.x, stop.coords.y, stop.coords.z),
        size = vector3(1.5, 1.5, 1.5),
        rotation = stop.coords.w or 180.0,
        options = {
             {
                icon = 'fas fa-trash',
                label = ('Grab Trash (%s/%s)'):format(garbage.collectedForStop, garbage.bagsRequired),
                onSelect = function()
                    if garbage.busy then return end

                    if garbage.collectedForStop >= garbage.bagsRequired then
                        return
                    end

                    if garbage.bagObject then
                        Kora.notify.send({
                            title = 'Garbage',
                            message = 'You are already carrying a bag.',
                            type = 'warning',
                        })
                        return
                    end

                    -- attachBag yields while streaming, so lock first or a double select spawns two bags.
                    garbage.busy = true
                    if not attachBag() then
                        garbage.busy = false
                        return
                    end

                    local ok = Kora.callback.trigger('qb-garbagejob:collectBag', stopId)
                    garbage.busy = false

                    -- The stop may have changed (or the job ended) while waiting on the server.
                    local current = garbage.route and garbage.route[garbage.routeIndex]
                    if not ok or not current or current.stop ~= stopId then
                        clearBag()
                        return
                    end

                    garbage.bags += 1
                    garbage.collectedForStop += 1

                    -- Labels are fixed at registration, so re-register to show the new count.
                    removeStopZone()
                    addStopZone(stopId)
                end,
                canInteract = function()
                    return garbage.truck ~= nil
                        and garbage.route
                        and garbage.route[garbage.routeIndex]
                        and garbage.route[garbage.routeIndex].stop == stopId
                        and garbage.collectedForStop < garbage.bagsRequired
                        and garbage.bagObject == nil
                end,
            },
        }
    })
end

local function setupStop(stopId, bagsRequired)
    removeCurrentStop()

    garbage.bags = 0
    garbage.collectedForStop = 0
    garbage.bagsRequired = bagsRequired

    createStopBlip(stopId)
    addStopZone(stopId)
end

local function addTruckTarget()
    if garbage.truckTargetAdded or not garbage.truck then return end

    exports.kora_target:addEntity(garbage.truck, {
        {
            icon = 'fas fa-dumpster',
            label = 'Throw Trash Bag',
            onSelect = function()
                if garbage.busy then return end

                if not garbage.bagObject then
                    Kora.notify.send({
                        title = 'Garbage',
                        message = 'You are not carrying a trash bag.',
                        type = 'warning',
                    })
                    return
                end

                local currentStop = garbage.route and garbage.route[garbage.routeIndex]
                if not currentStop then return end

                garbage.busy = true
                local ok = Kora.callback.trigger('qb-garbagejob:depositBag', currentStop.stop)
                if not ok or not garbage.bagObject then
                    garbage.busy = false
                    return
                end

                local ped = PlayerPedId()

                ClearPedSecondaryTask(ped)

                if garbage.bagObject and DoesEntityExist(garbage.bagObject) then
                    DeleteEntity(garbage.bagObject)
                end

                garbage.bagObject = nil
                garbage.bags -= 1

                if garbage.bags == 0 and garbage.collectedForStop >= garbage.bagsRequired then
                    local complete = Kora.callback.trigger(
                        'qb-garbagejob:completeStop',
                        garbage.routeIndex
                    )

                    if complete and garbage.route then
                        removeCurrentStop()
                        garbage.routeIndex += 1

                        local nextStop = garbage.route and garbage.route[garbage.routeIndex]
                        if nextStop then
                            setupStop(nextStop.stop, nextStop.bags)
                            Kora.notify.send({
                                title = 'Garbage',
                                message = 'Stop completed. Continue to the next stop.',
                                type = 'success',
                            })
                        else
                            createDepotBlip(Config.GarbageDepotRoute ~= false)
                            Kora.notify.send({
                                title = 'Garbage',
                                message = ('All %s stops are complete. Return the truck to the depot.'):format(#garbage.route),
                                type = 'success',
                            })
                        end
                    end
                end

                garbage.busy = false
            end,
            canInteract = function()
                return garbage.bagObject ~= nil
                    and garbage.route
                    and garbage.route[garbage.routeIndex] ~= nil
            end,
        },
        {
            icon = 'fas fa-rotate-left',
            label = 'Return Garbage Truck',
            onSelect = function()
                if garbage.busy then return end

                if not garbage.route or garbage.route[garbage.routeIndex] then
                    Kora.notify.send({
                        title = 'Garbage',
                        message = 'Finish all of your stops before returning the truck.',
                        type = 'warning',
                    })
                    return
                end

                local coords = GetEntityCoords(garbage.truck)
                if #(coords - Garbage.Locations.main) > Garbage.ReturnDistance then
                    Kora.notify.send({
                        title = 'Garbage',
                        message = 'You need to bring the truck back to the depot.',
                        type = 'warning',
                    })
                    return
                end

                garbage.busy = true
                local returned = Kora.callback.trigger('qb-garbagejob:returnTruck', VehToNet(garbage.truck))
                garbage.busy = false
                if not returned then return end

                removeCurrentStop()
                clearBag()

                -- Still on the job: keep the depot blip, just drop the route line.
                createDepotBlip(false)

                if type(returned) == 'number' then
                    Kora.notify.send({
                        title = 'Garbage',
                        message = ('You were paid $%s for your garbage route.'):format(returned),
                        type = 'success',
                    })
                end

                if DoesEntityExist(garbage.truck) then
                    exports.kora_target:removeEntity(garbage.truck)
                    DeleteVehicle(garbage.truck)
                end

                garbage.truck = nil
                garbage.route = nil
                garbage.routeIndex = 1
                garbage.bags = 0
                garbage.bagsRequired = 0
                garbage.collectedForStop = 0
                garbage.truckTargetAdded = false
            end,
            canInteract = function()
                return garbage.truck ~= nil
                    and garbage.route
                    and garbage.route[garbage.routeIndex] == nil
            end,
        },
    })

    garbage.truckTargetAdded = true
end

local function spawnTruck()
    local playerData = exports.kora_core:getPlayerData()
    if playerData.job.name ~= 'garbage' then return end
    if garbage.truck or garbage.busy then return end

    garbage.busy = true
    local route = Kora.callback.trigger('qb-garbagejob:spawnTruck')
    if not route then
        garbage.busy = false
        Kora.notify.send({
            title = 'Garbage',
            message = 'You are already on a garbage route.',
            type = 'error',
        })
        return
    end

    local spawn = Garbage.Locations.vehicle[math.random(1, #Garbage.Locations.vehicle)].coords
    local model = Garbage.Vehicle

    Kora.stream.loadModel(model)

    garbage.truck = CreateVehicle(model, spawn.x, spawn.y, spawn.z, spawn.w, true, true)
    SetVehicleNumberPlateText(garbage.truck, 'GARBAGE')
    SetVehicleOnGroundProperly(garbage.truck)
    SetEntityAsMissionEntity(garbage.truck, true, true)
    SetModelAsNoLongerNeeded(model)

    -- The server only sees the truck once it has replicated, so retry briefly.
    local registered = false
    for _ = 1, 10 do
        if not DoesEntityExist(garbage.truck) then break end

        if NetworkGetEntityIsNetworked(garbage.truck) then
            local netId = VehToNet(garbage.truck)
            if netId and netId ~= 0 and Kora.callback.trigger('qb-garbagejob:setTruck', netId) then
                registered = true
                break
            end
        end

        Wait(300)
    end

    if not registered then
        Kora.callback.trigger('qb-garbagejob:cancel')
        if DoesEntityExist(garbage.truck) then
            DeleteVehicle(garbage.truck)
        end
        garbage.truck = nil
        garbage.busy = false
        Kora.notify.send({
            title = 'Garbage',
            message = 'Unable to start the route. Please try again.',
            type = 'error',
        })
        return
    end

    garbage.route = route
    garbage.routeIndex = 1
    garbage.truckTargetAdded = false
    garbage.collectedForStop = 0

    local firstStop = garbage.route[garbage.routeIndex]
    setupStop(firstStop.stop, firstStop.bags)
    addTruckTarget()
    garbage.busy = false

    Kora.notify.send({
        title = 'Garbage',
        message = 'Your truck is ready. Follow the route to the first stop.',
        type = 'success',
    })
end

local function setUpPed()
    for _, pedData in pairs(Garbage.Peds) do
        local ped = Kora.entities.create(pedData.model, pedData.coords, {
            freeze = true,
            invincible = true,
            blockNonTempEvents = true,
        })

        exports.kora_target:addEntity(ped, {
            {
                icon = 'fas fa-hand-paper',
                label = 'Start Garbage Route',
                onSelect = function()
                    spawnTruck()
                end,
                canInteract = function()
                    local playerData = exports.kora_core:getPlayerData()
                    return playerData.job and playerData.job.name == 'garbage'
                        and garbage.truck == nil
                end,
            },
        })
    end
end

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    if job.name == 'garbage' then
        createDepotBlip()
        return
    end

    if garbage.truck then
        Kora.callback.trigger('qb-garbagejob:cancel')
        removeCurrentStop()
        clearBag()

        if DoesEntityExist(garbage.truck) then
            exports.kora_target:removeEntity(garbage.truck)
            DeleteVehicle(garbage.truck)
        end

        garbage.truck = nil
        garbage.route = nil
        garbage.routeIndex = 1
        garbage.bags = 0
        garbage.bagsRequired = 0
        garbage.collectedForStop = 0
        garbage.truckTargetAdded = false
    end

    garbage.busy = false
    removeBlips()
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    local playerData = exports.kora_core:getPlayerData()
    if playerData.job.name == 'garbage' then
        createDepotBlip()
    else
        removeBlips()
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    removeCurrentStop()
    removeBlips()
    clearBag()

    if garbage.truck and DoesEntityExist(garbage.truck) then
        exports.kora_target:removeEntity(garbage.truck)
        DeleteVehicle(garbage.truck)
    end
end)

CreateThread(function()
    setUpPed()

    local playerData = exports.kora_core:getPlayerData()
    if playerData and playerData.job and playerData.job.name == 'garbage' then
        createDepotBlip()
    end
end)
