local carryBone = GetPedBoneIndex(PlayerPedId(), 57005)
local carryPackage, packageCoords = nil, nil
local onDuty, isBusy = false, false
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
    if packageCoords and props[packageCoords] then
        SetEntityDrawOutline(props[packageCoords], false)
    end
    for _, v in pairs(props) do
        DeleteObject(v)
    end
    if carryPackage then
        DeleteObject(carryPackage)
    end
    RemoveAnimDict('anim@heists@box_carry@')
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

local function PickupPackage()
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped, true)
    QB.stream.loadModel(Recycle.PickupBoxModel)
    QB.stream.loadAnimDict('anim@heists@box_carry@')
    TaskPlayAnim(ped, 'anim@heists@box_carry@', 'idle', 5.0, -1, -1, 50, 0, false, false, false)
    local object = CreateObject(Recycle.PickupBoxModel, pos.x, pos.y, pos.z, true, true, true)
    SetModelAsNoLongerNeeded(Recycle.PickupBoxModel)
    AttachEntityToEntity(object, ped, carryBone, 0.05, 0.1, -0.3, 300.0, 250.0, 20.0, true, true, false, true, 1, true)
    carryPackage = object
end

local function DropPackage()
    if not carryPackage then return end
    ClearPedTasks(PlayerPedId())
    DetachEntity(carryPackage, true, true)
    DeleteObject(carryPackage)
    carryPackage = nil
    RemoveAnimDict('anim@heists@box_carry@')
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
    DropPackage()
end

local function toggleDuty()
    if onDuty then
        QB.notify.send({ title = 'Recycle Center', message = QB.lang('recycle.text.clock_out'), type = 'success' })
        onDuty = false
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
    if isBusy then return end
    isBusy = true
    local success = progressbar(QB.lang('recycle.text.picking_up_the_package'), Recycle.PickupActionDuration)
    isBusy = false
    if not success then return end
    if props[packageCoords] then
        SetEntityDrawOutline(props[packageCoords], false)
    end
    packageCoords = nil
    PickupPackage()
end

local function handInPackage()
    local success = progressbar(QB.lang('recycle.text.unpacking_the_package'), Recycle.DeliveryActionDuration)
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
        exports.qbtarget:addEntity(props[k], {
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
    exports.qbtarget:addBoxZone({
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
    exports.qbtarget:addBoxZone({
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
    exports.qbtarget:addBoxZone({
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
    exports.qbtarget:addBoxZone({
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
