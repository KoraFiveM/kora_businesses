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

local function carryAnim()
    local anim = Recycle.CarryAnim or {}
    return anim.dict or 'anim@heists@box_carry@', anim.clip or 'idle', anim.flag or 49
end

local function progressbar(label, time)
    return Kora.progressbar.start({
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
    if not Kora.cache.isDead() then ClearPedTasks(PlayerPedId()) end
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
            if ped ~= carryPed or Kora.cache.isDead() or not DoesEntityExist(object) then
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
    local loaded, model = pcall(Kora.stream.loadModel, Recycle.PickupBoxModel)
    if not loaded or not model then return false end
    local pos = GetEntityCoords(ped, true)
    local object = CreateObject(model, pos.x, pos.y, pos.z, Recycle.CarryPropNetworked ~= false, false, false)
    SetModelAsNoLongerNeeded(model)
    if not object or object == 0 or not DoesEntityExist(object) then return false end
    -- Bone index is resolved against the current ped: it is skeleton specific and changes after a ped/character swap.
    local boneIndex = GetPedBoneIndex(ped, Recycle.CarryBone or 57005)
    local offset = Recycle.CarryOffset or vector3(0.05, 0.1, -0.3)
    local rotation = Recycle.CarryRotation or vector3(300.0, 250.0, 20.0)
    AttachEntityToEntity(object, ped, boneIndex, offset.x, offset.y, offset.z, rotation.x, rotation.y, rotation.z, true, true, false, true, 1, true)
    carryPackage, carryPed = object, ped
    local animLoaded, dictReady = pcall(Kora.stream.loadAnimDict, dict)
    if animLoaded and dictReady then
        TaskPlayAnim(ped, dict, clip, 5.0, -1, -1, flag, 0, false, false, false)
    end
    watchCarry(object)
    return true
end

local function SetLocationBlip()
    Kora.blips.create(Recycle.OutsideLocation, {
        sprite = 365,
        color = 2,
        scale = 0.8,
        shortRange = true,
        label = 'Recycle Center'
    })
end

SetLocationBlip()

local function EnterLocation()
    Kora.visuals.fade(Recycle.InsideLocation)
end

local function ExitLocation()
    Kora.visuals.fade(Recycle.OutsideLocation)
    onDuty = false
    TriggerServerEvent('qb-recyclejob:server:cancelPickup')
    DropPackage()
    if packageCoords and props[packageCoords] then
        SetEntityDrawOutline(props[packageCoords], false)
    end
end

local function toggleDuty()
    if onDuty then
        Kora.notify.send({ title = 'Recycle Center', message = Kora.lang('recycle.text.clock_out'), type = 'success' })
        onDuty = false
        TriggerServerEvent('qb-recyclejob:server:cancelPickup')
        DropPackage()
        if packageCoords and props[packageCoords] then
            SetEntityDrawOutline(props[packageCoords], false)
        end
        packageCoords = nil
    else
        Kora.notify.send({ title = 'Recycle Center', message = Kora.lang('recycle.text.clock_in'), type = 'success' })
        onDuty = true
        GetRandomPackage()
    end
end

local function pickUp()
    -- One box at a time: a carried box (or a pickup already in progress) blocks any further pickup.
    if isBusy or handingIn or carryPackage or not onDuty or not packageCoords then return end
    isBusy = true
    if not Kora.callback.trigger('qb-recyclejob:server:pickupPackage', packageCoords) then
        -- Refused: the server may still hold the authorization for a box we carry, so never cancel it here.
        isBusy = false
        return
    end
    local success = progressbar(Kora.lang('recycle.text.picking_up_the_package'), Recycle.PickupActionDuration)
    if not success then
        isBusy = false
        TriggerServerEvent('qb-recyclejob:server:cancelPickup')
        return
    end
    -- isBusy stays set while the prop streams in so a second pickup cannot start in that gap.
    local carried = PickupPackage()
    isBusy = false
    if not carried then
        TriggerServerEvent('qb-recyclejob:server:cancelPickup')
        Kora.notify.send({ title = 'Recycle Center', message = Kora.lang('recycle.error.carry_failed'), type = 'error' })
        return
    end
    if props[packageCoords] then
        SetEntityDrawOutline(props[packageCoords], false)
    end
    packageCoords = nil
end

local function handInPackage()
    local object = carryPackage
    if not object or handingIn or isBusy then return end
    handingIn = true
    local success = progressbar(Kora.lang('recycle.text.unpacking_the_package'), Recycle.DeliveryActionDuration)
    handingIn = false
    -- The box may have been dropped (death, clock-out) while the bar ran; only a still-carried box pays out.
    if not success or carryPackage ~= object then return end
    DropPackage()
    TriggerServerEvent('qb-recyclejob:server:getItem')
    GetRandomPackage()
end

local function Start()
    for k, v in pairs(Recycle.PickupLocations) do
        local model = Recycle.WarehouseObjects[v.model]
        props[k] = Kora.entities.create(model, v.loc, {freeze = true, invincible = true})
        SetEntityHeading(props[k], 180.0)
        exports.kora_target:addEntity(props[k], {
            {
                label = Kora.lang('recycle.text.get_package'),
                icon = 'fas fa-box',
                onSelect = function()
                    pickUp()
                end,
                canInteract = function()
                    return packageCoords == k and not isBusy and not carryPackage
                end,
            },
        })
    end
    exports.kora_target:addBoxZone({
        coords = Recycle.OutsideLocation,
        size = vector4(4, 1.5, 2.0, 44.0),
        options = {
            {
                label = Kora.lang('recycle.text.enter_warehouse'),
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
                label = Kora.lang('recycle.text.exit_warehouse'),
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
                label = Kora.lang('recycle.text.toggle_duty'),
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
                label = Kora.lang('recycle.text.hand_in_package'),
                onSelect = function()
                    handInPackage()
                end,
                canInteract = function()
                    return carryPackage ~= nil and not handingIn and not isBusy
                end,
            },
        }
    })
end
CreateThread(function()
    Wait(100)
    Start()
end)
