CurrentPlate = CurrentPlate or {}
local Blip = nil
-- Cached from job events so the target `canInteract` filters and the equipment checks never call an export.
local employee = false

function News.isEmployee()
    return employee
end

local function removeBlip()
    if Blip then
        Kora.blips.remove(Blip)
        Blip = nil
    end
end

local function spawnBlips()
    if Blip or not employee then return end
    Blip = Kora.blips.create(News.Locations.vehicle.coords, {
        label = Kora.lang('news.text.vehicle'),
        sprite = 225,
        color = 1,
        scale = 0.6,
        shortRange = true
    })
end

local function setJob(job)
    employee = type(job) == 'table' and job.name == News.jobName()
    if employee then spawnBlips() else removeBlip() end
    if News.onJobChanged then News.onJobChanged(employee) end
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    setJob(exports.kora_core:getPlayerData({ 'job' }))
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', setJob)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    setJob(nil)
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() then removeBlip() end
end)

-- These files load after the player is already in the game (and again after a resource restart), so
-- the OnPlayerLoaded event has usually passed: read the job once now.
CreateThread(function()
    local ok, job = pcall(function() return exports.kora_core:getPlayerData({ 'job' }) end)
    if ok and job then setJob(job) end
end)

local function returnVec3(coords)
    return vector3(coords.x, coords.y, coords.z)
end

local function canUse()
    return employee
end

local function storeOption(label)
    return {
        label = label,
        icon = 'fas fa-warehouse',
        -- the store callback yields, so run it outside the target dispatch
        action = function() CreateThread(storeCurrentVehicle) end,
        canInteract = function() return employee and GetVehiclePedIsIn(Kora.cache.ped(), false) ~= 0 end,
    }
end

CreateThread(function()
    Kora.interact.addBoxZone('news_garage',
    returnVec3(News.Locations.vehicle.coords),
    vector3(4.0, 4.0, 4.0), {
        {
            label = Kora.lang('news.text.vehicles'),
            icon = "fas fa-car",
            action = function()
                menuGarage('vehicle')
            end,
            canInteract = canUse,
        },
        storeOption(Kora.lang('news.text.store_vehicle')),
    })
    Kora.interact.addBoxZone('news_heli', returnVec3(News.Locations.heli.coords), vector3(4.0, 4.0, 4.0), {
        {
            label = Kora.lang('news.text.helicopters'),
            icon = "fas fa-helicopter",
            action = function()
                menuGarage('heli')
            end,
            canInteract = canUse,
        },
        storeOption(Kora.lang('news.text.store_vehicle')),
    })

    Kora.interact.addBoxZone('news_equipment_shop', returnVec3(News.Locations.shop), vector3(2.0, 2.0, 2.0), {
        {
            label = Kora.lang('news.text.take_camera'), icon = 'fas fa-camera',
            action = function() TriggerServerEvent('qb-newsjob:server:requestedEquipment', 'newscam') end,
            canInteract = canUse,
        },
        {
            label = Kora.lang('news.text.take_boom_mic'), icon = 'fas fa-microphone',
            action = function() TriggerServerEvent('qb-newsjob:server:requestedEquipment', 'newsmic') end,
            canInteract = canUse,
        },
        {
            label = Kora.lang('news.text.take_hand_mic'), icon = 'fas fa-microphone',
            action = function() TriggerServerEvent('qb-newsjob:server:requestedEquipment', 'newsbmic') end,
            canInteract = canUse,
        },
    })

    local function doorZone(name, coords, text, teleCoords)
        Kora.interact.addBoxZone(name, returnVec3(coords), vector3(1.5, 1.5, 1.5), {
            {
                icon = "fas fa-door-open",
                label = text,
                action = function()
                    Kora.visuals.fade(teleCoords, 500)
                end,
                canInteract = canUse,
            }
        })
    end
    if News.Locations.outside then
        doorZone('news_door_in', News.Locations.outside, Kora.lang('news.text.enter'), News.Locations.inside)
    end
    if News.Locations.inside then
        doorZone('news_door_out', News.Locations.inside, Kora.lang('news.text.go_outside'), News.Locations.outside)
    end
end)
