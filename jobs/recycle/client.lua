local carryPackage, packageCoords, carryPed = nil, nil, nil
local onDuty, isBusy, handingIn = false, false, false
local props = {}
local progressConfig = {
    disable = {
        move = true,
        car = true,
        combat = true,
    },
    anim = {
        dict = 'mp_arresting',
        clip = 'a_uncuff',
        flags = 17
    }
}

-- Carry animation comes from Recycle.CarryAnim (shared.lua), read at use time.
local function carryAnim()
    local anim = Recycle.CarryAnim or {}
    return anim.dict or 'anim@heists@box_carry@', anim.clip or 'idle', anim.flag or 49
end

local function progressbar(label, time)
    return QB.progressbar.start({
        label = label,
        duration = time,
        useWhileDead = false,
        canCancel = true,
        disable = progressConfig.disable,
        anim = progressConfig.anim,
    })
end
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    TriggerServerEvent('qb-recyclejob:server:cancelPickup')
    if packageCoords and props[packageCoords] then
        SetEntityDrawOutline(props[packageCoords], false)
    end
    for _, v in pairs(props) do
        DeleteObject(v)
    end
    if carryPackage then
        DetachEntity(carryPackage, true, true)
        DeleteObject(carryPackage)
        carryPackage = nil
        ClearPedTasks(PlayerPedId())
    end
    RemoveAnimDict((carryAnim()))
end)

local function DrawPackageLocationBlip()
    if not Recycle.DrawPackageLocationBlip then return end
    local prop = props[packageCoords]
    if not prop then return end
    SetEntityDrawOutline(prop, true)
    SetEntityDrawOutlineColor(prop, 15, 20, 60)
end

local function GetRandomPackage()
    local total = #Recycle.PickupLocations
    if total <= 1 then
        packageCoords = 1
    else
        local newCoords
        repeat
            Wait(0)
            newCoords = math.random(1, total)
        until newCoords ~= packageCoords
        packageCoords = newCoords
    end
    DrawPackageLocationBlip()
end

local function DropPackage()
    if not carryPackage then return end
    local object = carryPackage
    carryPackage, carryPed = nil, nil
    if not QB.cache.isDead() then ClearPedTasks(PlayerPedId()) end
    if DoesEntityExist(object) then
        DetachEntity(object, true, true)
        DeleteObject(object)
    end
    RemoveAnimDict((carryAnim()))
end

-- Releases the box when the carrier dies, switches ped (character swap) or the prop vanishes,
-- and re-applies the carry pose if something (vehicle, ragdoll) knocked it off.
local function watchCarry(object)
    CreateThread(function()
        while carryPackage == object do
            Wait(500)
            if carryPackage ~= object then break end
            local ped = PlayerPedId()
            if ped ~= carryPed or QB.cache.isDead() or not DoesEntityExist(object) then
                DropPackage()
                TriggerServerEvent('qb-recyclejob:server:cancelPickup')
                if onDuty and not packageCoords then GetRandomPackage() end
                break
            end
            local dict, clip, flag = carryAnim()
            if not handingIn and not isBusy and not IsEntityPlayingAnim(ped, dict, clip, 3) and HasAnimDictLoaded(dict) then
                TaskPlayAnim(ped, dict, clip, 5.0, -1, -1, flag, 0, false, false, false)
            end
        end
    end)
end

-- Returns true once the box is attached to the player's hand.
local function PickupPackage()
    local ped = PlayerPedId()
    local dict, clip, flag = carryAnim()
    local loaded, model = pcall(QB.stream.loadModel, Recycle.PickupBoxModel)
    if not loaded or not model then return false end
    local pos = GetEntityCoords(ped, true)
    -- Not a door object (last arg false) and not a mission entity: the old call passed true for all three.
    local object = CreateObject(model, pos.x, pos.y, pos.z, Recycle.CarryPropNetworked ~= false, false, false)
    SetModelAsNoLongerNeeded(model)
    if not object or object == 0 or not DoesEntityExist(object) then return false end
    -- Bone index is resolved against the current ped: it is skeleton specific and changes after a ped/character swap.
    local boneIndex = GetPedBoneIndex(ped, Recycle.CarryBone or 57005)
    local offset = Recycle.CarryOffset or vector3(0.05, 0.1, -0.3)
    local rotation = Recycle.CarryRotation or vector3(300.0, 250.0, 20.0)
    AttachEntityToEntity(object, ped, boneIndex, offset.x, offset.y, offset.z, rotation.x, rotation.y, rotation.z, true, true, false, true, 1, true)
    carryPackage, carryPed = object, ped
    local animLoaded, dictReady = pcall(QB.stream.loadAnimDict, dict)
    if animLoaded and dictReady then
        TaskPlayAnim(ped, dict, clip, 5.0, -1, -1, flag, 0, false, false, false)
    end
    watchCarry(object)
    return true
end

local function SetLocationBlip()
    QB.blips.create(Recycle.OutsideLocation, {
        sprite = 365,
        color = 2,
        scale = 0.8,
        shortRange = true,
        label = 'Recycle Center'
    })
end

SetLocationBlip()

local function EnterLocation()
    QB.visuals.fade(Recycle.InsideLocation)
end

local function ExitLocation()
    QB.visuals.fade(Recycle.OutsideLocation)
    onDuty = false
    TriggerServerEvent('qb-recyclejob:server:cancelPickup')
    DropPackage()
    if packageCoords and props[packageCoords] then
        SetEntityDrawOutline(props[packageCoords], false)
    end
end

local function toggleDuty()
    if onDuty then
        QB.notify.send({ title = 'Recycle Center', message = QB.lang('recycle.text.clock_out'), type = 'success' })
        onDuty = false
        TriggerServerEvent('qb-recyclejob:server:cancelPickup')
        DropPackage()
        if packageCoords and props[packageCoords] then
            SetEntityDrawOutline(props[packageCoords], false)
        end
        packageCoords = nil
    else
        QB.notify.send({ title = 'Recycle Center', message = QB.lang('recycle.text.clock_in'), type = 'success' })
        onDuty = true
        GetRandomPackage()
    end
end

local function pickUp()
    if isBusy or not onDuty or not packageCoords then return end
    isBusy = true
    if not QB.callback.trigger('qb-recyclejob:server:pickupPackage', packageCoords) then
        isBusy = false
        TriggerServerEvent('qb-recyclejob:server:cancelPickup')
        return
    end
    local success = progressbar(QB.lang('recycle.text.picking_up_the_package'), Recycle.PickupActionDuration)
    isBusy = false
    if not success then
        TriggerServerEvent('qb-recyclejob:server:cancelPickup')
        return
    end
    if not PickupPackage() then
        TriggerServerEvent('qb-recyclejob:server:cancelPickup')
        QB.notify.send({ title = 'Recycle Center', message = QB.lang('recycle.error.carry_failed'), type = 'error' })
        return
    end
    if props[packageCoords] then
        SetEntityDrawOutline(props[packageCoords], false)
    end
    packageCoords = nil
end

local function handInPackage()
    handingIn = true
    local success = progressbar(QB.lang('recycle.text.unpacking_the_package'), Recycle.DeliveryActionDuration)
    handingIn = false
    if not success then return end
    DropPackage()
    TriggerServerEvent('qb-recyclejob:server:getItem')
    GetRandomPackage()
end

local function Start()
    for k, v in pairs(Recycle.PickupLocations) do
        local model = Recycle.WarehouseObjects[v.model]
        props[k] = QB.entities.create(model, v.loc, {freeze = true, invincible = true})
        SetEntityHeading(props[k], 180.0)
        exports.kora_target:addEntity(props[k], {
            {
                label = QB.lang('recycle.text.get_package'),
                icon = 'fas fa-box',
                onSelect = function()
                    pickUp()
                end,
                canInteract = function()
                    return packageCoords == k and not isBusy
                end,
            },
        })
    end
    exports.kora_target:addBoxZone({
        coords = Recycle.OutsideLocation,
        size = vector4(4, 1.5, 2.0, 44.0),
        options = {
            {
                label = QB.lang('recycle.text.enter_warehouse'),
                onSelect = function()
                    EnterLocation()
                end,
            },
        }
    })
    exports.kora_target:addBoxZone({
        coords = Recycle.InsideLocation,
        size = vector4(4, 1.5, 2.0, 44.0),
        options = {
            {
                label = QB.lang('recycle.text.exit_warehouse'),
                onSelect = function()
                    ExitLocation()
                end,
            },
        }
    })
    exports.kora_target:addBoxZone({
        coords = Recycle.DutyLocation,
        size = vector4(4, 1.5, 2.0, 44.0),
        options = {
            {
                label = QB.lang('recycle.text.toggle_duty'),
                onSelect = function()
                    toggleDuty()
                end,
            },
        }
    })
    exports.kora_target:addBoxZone({
        coords = Recycle.DropLocation,
        size = vector4(4, 1.5, 2.0, 44.0),
        options = {
            {
                label = QB.lang('recycle.text.hand_in_package'),
                onSelect = function()
                    handInPackage()
                end,
                canInteract = function()
                    return carryPackage ~= nil
                end,
            },
        }
    })
end
CreateThread(function()
    Wait(100)
    Start()
end)
