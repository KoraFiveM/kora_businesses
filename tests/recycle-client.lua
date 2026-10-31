-- Client-side regression coverage for the recycle carry prop (attach, failure and cleanup paths).
local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'

local function vec(x, y, z, w) return { x = x, y = y, z = z, w = w } end

local threads, serverEvents, notifications, handlers = {}, {}, {}, {}
local targets = {}
local entities, nextHandle = {}, 100
local state = { ped = 1, dead = false, modelOk = true, createFails = false, doorFlag = nil, networked = nil, bone = nil, attach = nil, anim = nil, playing = true }
local deleted = {}

local function newEntity() nextHandle = nextHandle + 1; entities[nextHandle] = true; return nextHandle end

local Kora = {
    cache = { isDead = function() return state.dead end },
    stream = {
        loadModel = function(model) if not state.modelOk then return false, 'timeout' end return 1234 end,
        loadAnimDict = function(dict) return dict end,
    },
    notify = { send = function(n) notifications[#notifications + 1] = n end },
    lang = function(key) return key end,
    blips = { create = function() end },
    visuals = { fade = function() end },
    entities = { create = function() return newEntity() end },
    callback = { trigger = function() return true end },
    progressbar = { start = function() return true end },
}

local env
env = setmetatable({
    Kora = Kora, QB = Kora,
    Recycle = {
        OutsideLocation = vec(0, 0, 0, 0), InsideLocation = vec(1, 1, 1, 1), DutyLocation = vec(2, 2, 2, 2), DropLocation = vec(3, 3, 3, 3),
        DrawPackageLocationBlip = false, PickupActionDuration = 10, DeliveryActionDuration = 10,
        PickupBoxModel = 'prop_cs_cardbox_01',
        CarryPropNetworked = true, CarryBone = 28422,
        CarryOffset = vec(0.5, 0.6, 0.7), CarryRotation = vec(1.0, 2.0, 3.0),
        CarryAnim = { dict = 'test@dict', clip = 'test_clip', flag = 49 },
        PickupLocations = { { model = 1, loc = vec(9, 9, 9, 9) } },
        WarehouseObjects = { 'prop_boxpile_05a' },
    },
    exports = { kora_target = {
        addEntity = function(_, _, opts) targets.pickup = opts[1] end,
        addBoxZone = function(_, def) targets[#targets + 1] = def.options[1] end,
    } },
    vector3 = vec, vector4 = vec,
    GetCurrentResourceName = function() return 'kora_businesses' end,
    AddEventHandler = function(name, fn) handlers[name] = fn end,
    TriggerServerEvent = function(name) serverEvents[#serverEvents + 1] = name end,
    CreateThread = function(fn) threads[#threads + 1] = coroutine.create(fn) end,
    Wait = function() coroutine.yield() end,
    PlayerPedId = function() return state.ped end,
    GetEntityCoords = function() return vec(0, 0, 0) end,
    SetEntityHeading = function() end, SetEntityDrawOutline = function() end, SetEntityDrawOutlineColor = function() end,
    GetPedBoneIndex = function(ped, bone) state.bone = { ped = ped, bone = bone }; return 5000 + bone end,
    CreateObject = function(_, _, _, _, networked, mission, door)
        state.networked, state.doorFlag = networked, door
        if state.createFails then return 0 end
        return newEntity()
    end,
    SetModelAsNoLongerNeeded = function() end,
    DoesEntityExist = function(e) return entities[e] == true end,
    AttachEntityToEntity = function(obj, ped, bone, ox, oy, oz, rx, ry, rz) state.attach = { obj = obj, ped = ped, bone = bone, ox = ox, oy = oy, oz = oz, rx = rx, ry = ry, rz = rz } end,
    DetachEntity = function() end,
    DeleteObject = function(e) deleted[e] = true; entities[e] = nil end,
    ClearPedTasks = function() state.cleared = (state.cleared or 0) + 1 end,
    RemoveAnimDict = function() end,
    HasAnimDictLoaded = function() return true end,
    IsEntityPlayingAnim = function() return state.playing end,
    TaskPlayAnim = function(ped, dict, clip, _, _, _, flag) state.anim = { dict = dict, clip = clip, flag = flag } end,
    math = setmetatable({ random = function(a) return a end }, { __index = math }),
}, { __index = _G })

assert(loadfile(root .. 'jobs/recycle/client.lua', 't', env))()

local function pump(n)
    for _ = 1, n or 1 do
        for i = #threads, 1, -1 do
            local co = threads[i]
            if coroutine.status(co) == 'dead' then table.remove(threads, i)
            else assert(coroutine.resume(co)) end
        end
    end
end
pump(2) -- Start(): registers targets

local pickupTarget, dutyTarget, dropTarget = targets.pickup, targets[3], targets[4]
assert(pickupTarget and dutyTarget and dropTarget, 'targets registered')

local function count(list, name) local n = 0; for _, v in ipairs(list) do if v == name then n = n + 1 end end return n end
local function reset() state.attach, state.anim, state.dead, state.ped, state.playing = nil, nil, false, 1, true; serverEvents = {}; notifications = {} end

local function startCarrying()
    reset()
    if not pickupTarget.canInteract() then dutyTarget.onSelect() end -- clock in when needed
    pickupTarget.onSelect()
    assert(dropTarget.canInteract(), 'carrying after pickup')
end

-- 1. Attach uses the current ped, configured bone/offset/rotation/anim and is not a door object.
startCarrying()
assert(state.attach, 'box prop is attached on pickup')
assert(state.bone.ped == 1 and state.bone.bone == 28422, 'bone resolved from configured id on the current ped')
assert(state.attach.bone == 5000 + 28422 and state.attach.ped == 1)
assert(state.attach.ox == 0.5 and state.attach.oy == 0.6 and state.attach.oz == 0.7 and state.attach.rx == 1.0 and state.attach.rz == 3.0, 'configured offsets used')
assert(state.doorFlag == false and state.networked == true, 'prop is created as a plain (non-door) object')
assert(state.anim and state.anim.dict == 'test@dict' and state.anim.flag == 49, 'configured carry anim played with walkable flag')
local firstObject = state.attach.obj

-- 2. Hand-in deletes the prop and requests rewards.
dropTarget.onSelect()
assert(deleted[firstObject] and not dropTarget.canInteract(), 'hand-in removes the prop')
assert(count(serverEvents, 'qb-recyclejob:server:getItem') == 1)

-- 3. Death while carrying drops the prop and releases the pending pickup.
startCarrying()
local obj = state.attach.obj
state.dead = true
pump(2)
assert(deleted[obj] and not dropTarget.canInteract(), 'death removes the prop')
assert(count(serverEvents, 'qb-recyclejob:server:cancelPickup') >= 1, 'death cancels the server pickup')
state.dead = false

-- 4. Ped swap (character switch) drops the prop that was attached to the old ped.
startCarrying()
obj = state.attach.obj
state.ped = 2
pump(2)
assert(deleted[obj] and not dropTarget.canInteract(), 'ped change removes the prop')
state.ped = 1

-- 5. Anim is re-applied if it was knocked off while carrying.
startCarrying()
state.anim, state.playing = nil, false
pump(2)
assert(state.anim and state.anim.clip == 'test_clip', 'carry pose restored')
state.playing = true

-- 6. Clocking out drops the prop.
obj = state.attach.obj
dutyTarget.onSelect()
assert(deleted[obj] and not dropTarget.canInteract(), 'clock out removes the prop')

-- 7. Resource stop deletes the carried prop.
startCarrying()
obj = state.attach.obj
handlers.onResourceStop('kora_businesses')
assert(deleted[obj], 'resource stop removes the prop')
dutyTarget.onSelect() -- reset duty state (handlers ran; duty was on)

-- 8. Model failing to load is reported and nothing is carried.
reset()
state.modelOk = false
if not pickupTarget.canInteract() then dutyTarget.onSelect() end
pickupTarget.onSelect()
assert(not dropTarget.canInteract(), 'no carry state when the model failed to load')
assert(notifications[#notifications] and notifications[#notifications].type == 'error', 'player is told the pickup failed')
assert(count(serverEvents, 'qb-recyclejob:server:cancelPickup') >= 1, 'failed pickup releases the server authorization')
state.modelOk = true

-- 9. CreateObject failure behaves the same.
reset()
state.createFails = true
pickupTarget.onSelect()
assert(not dropTarget.canInteract() and notifications[#notifications], 'failed object creation is reported')
state.createFails = false
pickupTarget.onSelect()
assert(dropTarget.canInteract(), 'pickup can be retried after a failure')

print('kora_businesses recycle carry prop: attach config, failure and cleanup paths passed')
