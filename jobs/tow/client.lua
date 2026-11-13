local pickupBlip, pickupVeh, veh, towAttached, delay, blip = nil, nil, nil, false, false, nil

local function delayed()
    delay = true
    SetTimeout(5000, function()
        delay = false
    end)
end

local function reset()
    if pickupBlip then RemoveBlip(pickupBlip) pickupBlip = nil end
    if pickupVeh then
        local vehicle = pickupVeh
        pickupVeh = nil
        SetTimeout(15500, function()
            DeleteVehicle(vehicle)
        end)
    end
    towAttached = false
end

local function setUpPickup(data)
    local indexed = Tow.Locations.towspots[data.location]
    local vehicle, loc = indexed.model, indexed.coords
    Kora.stream.loadModel(vehicle)
    pickupVeh = CreateVehicle(vehicle, loc, 0.0, true, true)
    SetModelAsNoLongerNeeded(vehicle)
    pickupBlip = AddBlipForEntity(pickupVeh)
    Kora.notify.send({
        title = Kora.lang('tow.title'),
        message = Kora.lang('tow.new_vehicle'),
        type = 'success'
    })
    SetBlipSprite(pickupBlip, 326)
    SetBlipDisplay(pickupBlip, 4)
    SetBlipScale(pickupBlip, 0.6)
    SetBlipAsShortRange(pickupBlip, true)
    SetBlipColour(pickupBlip, 15)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName(Kora.lang('tow.pickup_blip'))
    EndTextCommandSetBlipName(pickupBlip)
    SetNewWaypoint(loc.x, loc.y)
    exports.kora_target:addEntity(pickupVeh, {
            {
                label = Kora.lang('tow.tow_vehicle'),
                icon = "fas fa-car",
                onSelect = function()
                    local confirm = Kora.callback.trigger("qb-tow:server:pickUp")
                    if not confirm then
                        return
                    end
                    AttachEntityToEntity(pickupVeh, veh, GetEntityBoneIndexByName(veh, 'bodyshell'), 0.0, -1.5 + -0.85, 0.0 + 1.15, 0, 0, 0, 1, 1, 0, 1, 0, 1)
                    towAttached = true
                    Kora.notify.send({
                        title = Kora.lang('tow.title'),
                        message = Kora.lang('tow.return_yard'),
                        type = 'success'
                    })
                end,
                canInteract = function()
                    return not towAttached and not delay
                end
            },
            {
                label = Kora.lang('tow.place_vehicle'),
                icon = "fas fa-car",
                onSelect = function()
                    DetachEntity(pickupVeh, true, true)
                    local coords = Kora.raycast.getCoords({type = 'object',object = GetEntityModel(pickupVeh)})
                    if coords and coords.coords then
                        SetEntityCoords(pickupVeh, coords.coords.x, coords.coords.y, coords.coords.z)
                        SetEntityHeading(pickupVeh, coords.coords.h or 180.0)
                        reset()
                        local data = Kora.callback.trigger("qb-tow:server:DropOff")
                        if data then
                            reset()
                            setUpPickup(data)
                        end
                    end
                end,
                canInteract = function()
                    return towAttached and not delay
                end
            }
    })
end

Kora.interact.addBoxZone('towVehGet', Tow.Locations.vehicle.coords, vector3(3, 3, 3), {
    {
        label = Kora.lang('tow.pull_out'),
        icon = "fas fa-car",
        action = function()
            local data = Kora.callback.trigger("qb-tow:server:TakeOutVehicle")
            if not data then
                return
            end
            Kora.stream.loadModel(Tow.Vehicles)
            veh = CreateVehicle(Tow.Vehicles, Tow.Locations.vehicle.spawncoords, Tow.Locations.vehicle.coords.h or 180.0, true, true)
            SetModelAsNoLongerNeeded(Tow.Vehicles)
            SetEntityHeading(veh, Tow.Locations.vehicle.coords.h or 180.0)
            TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
            SetVehicleNumberPlateText(veh, "TOW")
            SetVehicleFuelLevel(veh, 100.0)
            SetVehicleEngineOn(veh, true, true, false)
            setUpPickup(data)
            delayed()
        end,
        canInteract = function()
            return not veh
        end
    },
    {
        label = Kora.lang('tow.detach'),
        icon = "fas fa-car",
        action = function()
            local checkDist = Kora.callback.trigger("qb-tow:server:CheckDistance")
            if not checkDist then
                return
            end
            DetachEntity(pickupVeh, true, true)
        end,
        canInteract = function()
            return veh and pickupVeh and towAttached and not delay
        end
    },
    {
        label = Kora.lang('tow.store'),
        icon = "fas fa-car",
        action = function()
            local confirmed = Kora.callback.trigger("qb-tow:server:ReturnVehicle")
            if not confirmed then
                return
            end
            if veh then
                DeleteVehicle(veh)
                veh = nil
            end
            if pickupVeh then
                DeleteVehicle(pickupVeh)
                pickupVeh = nil
            end
        end,
        canInteract = function()
            return veh and not delay
        end
    }
})

local function addBlips()
    blip = Kora.blips.create(Tow.Locations.vehicle.coords, {
        sprite = 225,
        display = 4,
        scale = 0.8,
        shortRange = true,
        name = "Tow Yard"
    })
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    if exports.kora_core:getPlayerData().job.name == 'tow' then
        addBlips()
    end
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(JobInfo)
    if JobInfo.name == 'tow' then
        addBlips()
    elseif blip then
        RemoveBlip(blip)
        blip = nil
    end
end)
