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
}

local BAG_MODEL = `hei_prop_heist_binbag`

local function removeBlips()
    for _, blip in pairs(blips) do
        Kora.blips.remove(blip)
    end
    blips = {}
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

    TaskPlayAnim(ped, 'missfbi4prepp1', 'idle', 8.0, -8.0, -1, 49, 0.0, false, false, false)

    return true
end

local function removeCurrentStop()
    removeStopZone()

    if blips.stop then
        Kora.blips.remove(blips.stop)
        blips.stop = nil
    end
end

local function setupStop(stopId, bagsRequired)
    removeCurrentStop()

    garbage.bags = 0
    garbage.collectedForStop = 0
    garbage.bagsRequired = bagsRequired

    createStopBlip(stopId)

    local stop = Garbage.Locations.trashcan[stopId]
    garbage.stopZone = exports.kora_target:addBoxZone({
        coords = vector3(stop.coords.x, stop.coords.y, stop.coords.z),
        size = vector3(1.5, 1.5, 1.5),
        rotation = stop.coords.w or 180.0,
        options = {
             {
                icon = 'fas fa-trash',
                label = ('Grab Trash (%s/%s)'):format(garbage.bags, garbage.bagsRequired),
                onSelect = function()
                    if garbage.bags >= garbage.bagsRequired then
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

                    if not attachBag() then
                        return
                    end

                    local ok = Kora.callback.trigger('qb-garbagejob:collectBag', stopId)
                    if not ok then
                        clearBag()
                        return
                    end

                    garbage.bags += 1
                    garbage.collectedForStop += 1
                end,
                canInteract = function()
                    return garbage.truck ~= nil
                        and garbage.route
                        and garbage.route[garbage.routeIndex]
                        and garbage.route[garbage.routeIndex].stop == stopId
                        and garbage.bags < garbage.bagsRequired
                        and garbage.bagObject == nil
                end,
            },
        }
    })
end

local function addTruckTarget()
    if garbage.truckTargetAdded or not garbage.truck then return end

    exports.kora_target:addEntity(garbage.truck, {
        {
            icon = 'fas fa-dumpster',
            label = 'Throw Trash Bag',
            onSelect = function()
                if not garbage.bagObject then
                    Kora.notify.send({
                        title = 'Garbage',
                        message = 'You are not carrying a trash bag.',
                        type = 'warning',
                    })
                    return
                end

                local ok = Kora.callback.trigger('qb-garbagejob:depositBag', garbage.route[garbage.routeIndex].stop)
                if not ok then return end

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

                    if complete then
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
                            Kora.notify.send({
                                title = 'Garbage',
                                message = ('All %s stops are complete. Return the truck to the depot.'):format(#garbage.route),
                                type = 'success',
                            })
                        end
                    end
                end
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

                local returned = Kora.callback.trigger('qb-garbagejob:returnTruck', VehToNet(garbage.truck))
                if not returned then return end

                removeCurrentStop()
                removeBlips()
                clearBag()

                if DoesEntityExist(garbage.truck) then
                    exports.kora_target:RemoveTargetEntity(garbage.truck)
                    DeleteVehicle(garbage.truck)
                end

                garbage.truck = nil
                garbage.route = nil
                garbage.routeIndex = 1
                garbage.bags = 0
                garbage.bagsRequired = 0
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
    if garbage.truck then return end

    local route = Kora.callback.trigger('qb-garbagejob:spawnTruck')
    if not route then
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

    if not Kora.callback.trigger('qb-garbagejob:setTruck', VehToNet(garbage.truck)) then
        Kora.callback.trigger('qb-garbagejob:cancel')
        if DoesEntityExist(garbage.truck) then
            DeleteVehicle(garbage.truck)
        end
        garbage.truck = nil
        Kora.notify.send({
            title = 'Garbage',
            message = 'Unable to start the route. Please try again.',
            type = 'error',
        })
        return
    end

    TriggerEvent('qb-vehiclekeys:client:AddKeys', 'GARBAGE')

    garbage.route = route
    garbage.routeIndex = 1
    garbage.truckTargetAdded = false
    garbage.collectedForStop = 0

    local firstStop = garbage.route[garbage.routeIndex]
    setupStop(firstStop.stop, firstStop.bags)
    addTruckTarget()

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

local function createDepotBlip()
    if blips.depot then return end

    for _, blipData in pairs(Garbage.BlipData) do
        blips.depot = Kora.blips.create(blipData.coords, {
            label = blipData.label,
            sprite = blipData.sprite,
            color = blipData.color,
            scale = blipData.scale,
            display = blipData.display,
        })
    end
end

AddEventHandler('QBCore:Client:OnJobUpdate', function(job)
    if job.name == 'garbage' then
        createDepotBlip()
        return
    end

    if garbage.truck then
        Kora.callback.trigger('qb-garbagejob:cancel')
        removeCurrentStop()
        clearBag()

        if DoesEntityExist(garbage.truck) then
            exports.kora_target:RemoveTargetEntity(garbage.truck)
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

    removeBlips()
end)

AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
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
        exports.kora_target:RemoveTargetEntity(garbage.truck)
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
