local carryPackage, packageCoords, carryPed = nil, nil, nil
local onDuty, isBusy, handingIn = false, false, false
local props = {}
local disableControls = {
    move = true,
    moveMode = 'controls', -- block walking with a control lease instead of freezing the ped (freeze/unfreeze pops the camera)
    car = true,
    combat = true,
}

local function carryAnim()
    local anim = Recycle.CarryAnim or {}
    return anim.dict or 'anim@heists@box_carry@', anim.clip or 'idle', anim.flag or 49
end

-- Field names follow Kora.progressbar.start: anim = { dict, clip, flag, blendIn, blendOut, duration }.
local function progressbar(label, time, anim)
    return Kora.progressbar.start({
        label = label,
        duration = time,
        useWhileDead = false,
        canCancel = true,
        disable = disableControls,
        anim = anim or nil,
    })
end

local function pickupAnim()
    local anim = Recycle.PickupAnim
    if anim == false then return nil end
    anim = anim or {}
    return {
        dict = anim.dict or 'mini@repair',
        clip = anim.clip or 'fixing_a_ped',
        flag = anim.flag or 1,
        blendIn = anim.blendIn,
        blendOut = anim.blendOut,
    }
end

local function handInAnim()
    local anim = Recycle.HandInAnim
    if not anim then return nil end
    return { dict = anim.dict, clip = anim.clip, flag = anim.flag or 1, blendIn = anim.blendIn, blendOut = anim.blendOut }
end

local function stopCarryAnim(ped)
    local dict, clip = carryAnim()
    StopAnimTask(ped, dict, clip, 2.0)
end

-- Only the current package's pallet is outlined; every other pallet is cleared.
local function refreshOutlines()
    local show = Recycle.DrawPackageLocationBlip and onDuty and packageCoords ~= nil
    for index, prop in pairs(props) do
        if show and index == packageCoords then
            SetEntityDrawOutline(prop, true)
            SetEntityDrawOutlineColor(prop, 15, 20, 60)
        else
            SetEntityDrawOutline(prop, false)
        end
    end
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    TriggerServerEvent('kora_businesses:recycle:cancelPickup')
    for _, v in pairs(props) do
        SetEntityDrawOutline(v, false)
        DeleteObject(v)
    end
    if carryPackage then
        DetachEntity(carryPackage, true, true)
        DeleteObject(carryPackage)
        carryPackage = nil
        stopCarryAnim(carryPed or PlayerPedId())
    end
    RemoveAnimDict((carryAnim()))
end)

local function GetRandomPackage()
    local total = #Recycle.PickupLocations
    if total <= 1 then
        packageCoords = 1
    else
        local newCoords
        repeat
            newCoords = math.random(1, total)
        until newCoords ~= packageCoords
        packageCoords = newCoords
    end
    refreshOutlines()
end

local function DropPackage()
    if not carryPackage then return end
    local object, ped = carryPackage, carryPed
    carryPackage, carryPed = nil, nil
    if not Kora.cache.isDead() then stopCarryAnim(ped or Kora.cache.ped()) end
    if DoesEntityExist(object) then
        DetachEntity(object, true, true)
        DeleteObject(object)
    end
    RemoveAnimDict((carryAnim()))
end

-- Drops the box and releases the server authorization; the player gets a new package to fetch.
local function abandonCarry()
    if not carryPackage then return end
    DropPackage()
    TriggerServerEvent('kora_businesses:recycle:cancelPickup')
    if onDuty and not packageCoords then GetRandomPackage() end
end

local function ensureCarryPose()
    local ped = carryPed
    local dict, clip, flag = carryAnim()
    if not ped or IsEntityPlayingAnim(ped, dict, clip, 3) or IsPedRagdoll(ped) or not HasAnimDictLoaded(dict) then return end
    TaskPlayAnim(ped, dict, clip, 5.0, -1, -1, flag, 0, false, false, false)
end

-- Carry interrupts come from kora_lib's cache change callbacks instead of a polling thread.
Kora.cache.onChange('isDead', function(dead)
    if dead then abandonCarry() end
end)
Kora.cache.onChange('ped', function(ped)
    if carryPackage and ped ~= carryPed then abandonCarry() end -- character/ped swap: the box hangs on the old ped
end)
Kora.cache.onChange('vehicle', function(vehicle)
    if vehicle then abandonCarry() end
end)
-- A jump, climb or ragdoll clears the upper-body carry pose; restore it on the cache's next position update.
Kora.cache.onChange('coords', function()
    if carryPackage and not handingIn and not isBusy then ensureCarryPose() end
end)

local function fail(reason)
    print(('[kora_businesses:recycle] carry prop failed: %s'):format(reason))
    return false
end

local function createCarryProp(model, ped, networked)
    local pos = GetEntityCoords(ped, true)
    local object = CreateObject(model, pos.x, pos.y, pos.z, networked, false, false)
    if not object or object == 0 or not DoesEntityExist(object) then return nil end
    -- Collision is switched off before the first physics step: a box spawned inside the ped otherwise shoves the camera.
    SetEntityCollision(object, false, false)
    -- Bone index is resolved against the current ped: it is skeleton specific and changes after a ped/character swap.
    local boneIndex = GetPedBoneIndex(ped, Recycle.CarryBone or 60309)
    local offset = Recycle.CarryOffset or vector3(0.025, 0.08, 0.255)
    local rotation = Recycle.CarryRotation or vector3(-145.0, 290.0, 0.0)
    AttachEntityToEntity(object, ped, boneIndex, offset.x, offset.y, offset.z, rotation.x, rotation.y, rotation.z, true, true, false, true, 1, true)
    return object
end

-- Returns true once the box is attached to the player's hands.
-- networked comes from the server: strict entity lockdown deletes client-created networked entities a moment
-- after they spawn, which is why the box used to vanish straight after the progress bar.
local function PickupPackage(networked)
    local ped = Kora.cache.ped()
    local dict, clip, flag = carryAnim()
    -- Kora.stream.loadModel returns the model hash (or false, reason) - never pass anything else to CreateObject.
    local loaded, model, reason = pcall(Kora.stream.loadModel, Recycle.PickupBoxModel)
    if not loaded or type(model) ~= 'number' then
        return fail(('model %s did not load (%s)'):format(tostring(Recycle.PickupBoxModel), tostring(loaded and reason or model)))
    end
    -- Load the carry pose first so the box never hangs in the air while the dictionary streams.
    local animLoaded, dictReady = pcall(Kora.stream.loadAnimDict, dict)
    local poseReady = animLoaded and dictReady ~= false and dictReady ~= nil
    local object = createCarryProp(model, ped, networked)
    if not object and networked then
        networked = false
        object = createCarryProp(model, ped, false) -- network object limit: fall back to a local prop
    end
    if not object then
        SetModelAsNoLongerNeeded(model)
        return fail('CreateObject returned no entity')
    end
    carryPackage, carryPed = object, ped
    if poseReady then
        TaskPlayAnim(ped, dict, clip, 5.0, 5.0, -1, flag, 0, false, false, false)
    end
    if networked then
        -- One-shot check: if the network refused the entity anyway (e.g. a locked-down routing bucket), carry a local box.
        SetTimeout(Recycle.CarryPropVerifyDelay or 1000, function()
            if carryPackage ~= object or DoesEntityExist(object) then SetModelAsNoLongerNeeded(model) return end
            local fallback = createCarryProp(model, carryPed, false)
            SetModelAsNoLongerNeeded(model)
            if fallback then
                carryPackage = fallback
            else
                fail('networked box was removed and no local fallback could be created')
            end
        end)
    else
        SetModelAsNoLongerNeeded(model)
    end
    return true
end

local function SetLocationBlip()
    Kora.blips.create(Recycle.OutsideLocation, {
        sprite = 365,
        color = 2,
        scale = 0.8,
        shortRange = true,
        label = Kora.lang('recycle.title')
    })
end

SetLocationBlip()

local function EnterLocation()
    Kora.visuals.fade(Recycle.InsideLocation)
end

local function ExitLocation()
    Kora.visuals.fade(Recycle.OutsideLocation)
    onDuty = false
    TriggerServerEvent('kora_businesses:recycle:cancelPickup')
    DropPackage()
    refreshOutlines()
end

local function toggleDuty()
    if onDuty then
        Kora.notify.send({ title = Kora.lang('recycle.title'), message = Kora.lang('recycle.text.clock_out'), type = 'success' })
        onDuty = false
        TriggerServerEvent('kora_businesses:recycle:cancelPickup')
        DropPackage()
        packageCoords = nil
        refreshOutlines()
    else
        Kora.notify.send({ title = Kora.lang('recycle.title'), message = Kora.lang('recycle.text.clock_in'), type = 'success' })
        onDuty = true
        GetRandomPackage()
    end
end

local function pickUp()
    -- One box at a time: a carried box (or a pickup already in progress) blocks any further pickup.
    if isBusy or handingIn or carryPackage or not onDuty or not packageCoords then return end
    isBusy = true
    local grant = Kora.callback.trigger('kora_businesses:recycle:pickupPackage', packageCoords)
    if not grant then
        -- Refused: the server may still hold the authorization for a box we carry, so never cancel it here.
        isBusy = false
        return
    end
    local success = progressbar(Kora.lang('recycle.text.picking_up_the_package'), Recycle.PickupActionDuration, pickupAnim())
    if not success then
        isBusy = false
        TriggerServerEvent('kora_businesses:recycle:cancelPickup')
        return
    end
    -- isBusy stays set while the prop streams in so a second pickup cannot start in that gap.
    local carried = PickupPackage(type(grant) == 'table' and grant.networked == true)
    isBusy = false
    if not carried then
        TriggerServerEvent('kora_businesses:recycle:cancelPickup')
        Kora.notify.send({ title = Kora.lang('recycle.title'), message = Kora.lang('recycle.error.carry_failed'), type = 'error' })
        return
    end
    packageCoords = nil
    refreshOutlines()
end

local function canHandIn()
    return carryPackage ~= nil and not handingIn and not isBusy
end

local function handInPackage()
    local object = carryPackage
    if not object or handingIn or isBusy then return end
    handingIn = true
    local success = progressbar(Kora.lang('recycle.text.unpacking_the_package'), Recycle.DeliveryActionDuration, handInAnim())
    handingIn = false
    -- The box may have been dropped (death, clock-out) while the bar ran; only a still-carried box pays out.
    if not success or carryPackage ~= object then return end
    DropPackage()
    TriggerServerEvent('kora_businesses:recycle:getItem')
    GetRandomPackage()
end

-- Lets sales.lua offer the hand-in on the drop-off ped (Recycle.HandInAtSellPed).
RecycleClient = { canHandIn = canHandIn, handIn = handInPackage }

local function Start()
    for k, v in pairs(Recycle.PickupLocations) do
        local model = Recycle.WarehouseObjects[v.model]
        props[k] = Kora.entities.create(model, v.loc, {freeze = true, invincible = true})
        SetEntityHeading(props[k], 180.0)
        exports.kora_target:addEntity(props[k], {
            {
                label = Kora.lang('recycle.text.get_package'),
                icon = 'fas fa-box',
                onSelect = pickUp,
                canInteract = function()
                    return packageCoords == k and not isBusy and not carryPackage
                end,
            },
        })
    end
    refreshOutlines()
    exports.kora_target:addBoxZone({
        coords = Recycle.OutsideLocation,
        size = vector4(4, 1.5, 2.0, 44.0),
        options = {
            {
                label = Kora.lang('recycle.text.enter_warehouse'),
                onSelect = EnterLocation,
            },
        }
    })
    exports.kora_target:addBoxZone({
        coords = Recycle.InsideLocation,
        size = vector4(4, 1.5, 2.0, 44.0),
        options = {
            {
                label = Kora.lang('recycle.text.exit_warehouse'),
                onSelect = ExitLocation,
            },
        }
    })
    exports.kora_target:addBoxZone({
        coords = Recycle.DutyLocation,
        size = vector4(4, 1.5, 2.0, 44.0),
        options = {
            {
                label = Kora.lang('recycle.text.toggle_duty'),
                onSelect = toggleDuty,
            },
        }
    })
    -- kora_target box zones take full extents as a vector3 and the heading as a separate `rotation` (degrees).
    local zone = Recycle.HandInZone or {}
    exports.kora_target:addBoxZone({
        coords = zone.coords or Recycle.DropLocation,
        size = zone.size or vector3(4.0, 4.0, 3.0),
        rotation = zone.rotation or 0.0,
        options = {
            {
                label = Kora.lang('recycle.text.hand_in_package'),
                icon = 'fas fa-box-open',
                onSelect = handInPackage,
                canInteract = canHandIn,
            },
        }
    })
end
CreateThread(function()
    Wait(100)
    Start()
end)
