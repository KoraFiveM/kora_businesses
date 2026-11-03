local activeItem
local prop
local animationDict
local cameraWatcherRunning = false
local items = {
    newscam = { model = 'prop_v_cam_01', bone = 28422, offset = vector3(0.0, 0.0, 0.0), anim = { 'missfinale_c2mcs_1', 'fin_c2_mcs_1_camman' } },
    newsmic = { model = 'prop_v_bmike_01', bone = 28422, offset = vector3(-0.08, 0.0, 0.0), anim = { 'missfra1', 'mcs2_crew_idle_m_boom' } },
    newsbmic = { model = 'p_ing_microphonel_01', bone = 60309, offset = vector3(0.055, 0.05, 0.0), anim = { 'missheistdocksprep1hold_cellphone', 'hold_cellphone' } },
}

local function removeEquipment()
    if prop and DoesEntityExist(prop) then DeleteEntity(prop) end
    ClearPedSecondaryTask(Kora.cache.ped())
    if animationDict then RemoveAnimDict(animationDict) end
    animationDict = nil
    prop, activeItem = nil, nil
    Kora.camera.close('equipment_removed')
end

-- Losing the job and dying end the equipment through events; only the camera overlay (which the player
-- can close themselves) needs a slow poll, and only while the camera is held.
local function watchCamera()
    if cameraWatcherRunning then return end
    cameraWatcherRunning = true
    CreateThread(function()
        while activeItem == 'newscam' do
            Wait(250)
            if activeItem == 'newscam' and not Kora.camera.isOpen() then removeEquipment() end
        end
        cameraWatcherRunning = false
    end)
end

local function useEquipment(itemName)
    if not News.isEmployee() then return end
    if activeItem then removeEquipment() return end
    local item = items[itemName]
    if not item then return end
    activeItem = itemName
    local ped, hash = Kora.cache.ped(), joaat(item.model)
    if not Kora.stream.loadModel(hash) then removeEquipment() return end
    prop = CreateObject(hash, GetEntityCoords(ped), true, true, false)
    SetModelAsNoLongerNeeded(hash)
    AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, item.bone), item.offset.x, item.offset.y, item.offset.z, 0.0, 0.0, 0.0, true, true, false, true, 0, true)
    if not Kora.stream.loadAnimDict(item.anim[1]) then removeEquipment() return end
    animationDict = item.anim[1]
    TaskPlayAnim(ped, item.anim[1], item.anim[2], 1.0, -1.0, -1, 50, 0.0, false, false, false)
    if itemName == 'newscam' then
        Kora.camera.open({
            mode = 'recording',
            title = 'WEAZEL NEWS',
            subtitle = 'FIELD UNIT // LIVE',
            cameraLabel = 'NEWS CAM 01',
            recording = true,
            viewMode = 4,
        })
        watchCamera()
    end
end

RegisterNetEvent('Cam:ToggleCam', function() useEquipment('newscam') end)
RegisterNetEvent('Mic:ToggleMic', function() useEquipment('newsmic') end)
RegisterNetEvent('Mic:ToggleBMic', function() useEquipment('newsbmic') end)

-- Event-driven removal (replaces the old per-frame job/death poll).
News.onJobChanged = function(employee)
    if not employee and activeItem then removeEquipment() end
end

local function watchDeath()
    Kora.cache.onChange('isDead', function(dead)
        if dead and activeItem then removeEquipment() end
    end)
end

watchDeath()
AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'kora_lib' then watchDeath() end
end)
AddEventHandler('onResourceStop', function(resourceName) if GetCurrentResourceName() == resourceName then removeEquipment() end end)
