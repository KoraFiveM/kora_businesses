-- Client-side regression coverage for the recycle carry prop (attach, failure and cleanup paths).
local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'

local function vec(x, y, z, w) return { x = x, y = y, z = z, w = w } end

local threads, serverEvents, notifications, handlers = {}, {}, {}, {}
local targets, pickups, zoneDefs, bars, outlines, palletEntities = {}, {}, {}, {}, {}, {}
local entities, nextHandle = {}, 100
local state = { ped = 1, dead = false, modelOk = true, createFails = false, doorFlag = nil, networked = nil, bone = nil, attach = nil, anim = nil, playing = true }
local deleted = {}
local cacheListeners, timeouts = {}, {}

local function newEntity() nextHandle = nextHandle + 1; entities[nextHandle] = true; return nextHandle end

local Kora = {
    cache = {
        isDead = function() return state.dead end,
        ped = function() return state.ped end,
        onChange = function(key, fn) cacheListeners[key] = cacheListeners[key] or {}; table.insert(cacheListeners[key], fn) end,
    },
    stream = {
        loadModel = function(model) state.loadedModel = model; if not state.modelOk then return false, 'timeout' end return 1234 end,
        loadAnimDict = function(dict) return dict end,
    },
    notify = { send = function(n) notifications[#notifications + 1] = n end },
    lang = function(key) return key end,
    blips = { create = function() end },
    visuals = { fade = function() end },
    entities = { create = function() local e = newEntity(); palletEntities[#palletEntities + 1] = e; return e end },
    callback = { trigger = function() state.triggers = (state.triggers or 0) + 1; return state.callbackOk ~= false and { networked = state.grantNetworked == true } or false end },
    progressbar = { start = function(payload) bars[#bars + 1] = payload; return true end },
}

local env
env = setmetatable({
    Kora = Kora, Kora = Kora,
    Recycle = {
        OutsideLocation = vec(0, 0, 0, 0), InsideLocation = vec(1, 1, 1, 1), DutyLocation = vec(2, 2, 2, 2), DropLocation = vec(3, 3, 3, 3),
        DrawPackageLocationBlip = true, PickupActionDuration = 10, DeliveryActionDuration = 10,
        PickupBoxModel = 'prop_cs_cardbox_01',
        CarryPropNetworked = true, CarryBone = 28422,
        CarryOffset = vec(0.5, 0.6, 0.7), CarryRotation = vec(1.0, 2.0, 3.0),
        CarryAnim = { dict = 'test@dict', clip = 'test_clip', flag = 49 },
        PickupLocations = { { model = 1, loc = vec(9, 9, 9, 9) }, { model = 1, loc = vec(8, 8, 8, 8) } },
        PickupAnim = { dict = 'pick@dict', clip = 'pick_clip', flag = 1 },
        HandInZone = { size = vec(4.0, 4.0, 3.0), rotation = 0.0 },
        WarehouseObjects = { 'prop_boxpile_05a' },
    },
    exports = { kora_target = {
        addEntity = function(_, _, opts) pickups[#pickups + 1] = opts[1] end,
        addBoxZone = function(_, def) targets[#targets + 1] = def.options[1]; zoneDefs[#zoneDefs + 1] = def end,
    } },
    vector3 = vec, vector4 = vec,
    GetCurrentResourceName = function() return 'kora_businesses' end,
    AddEventHandler = function(name, fn) handlers[name] = fn end,
    TriggerServerEvent = function(name) serverEvents[#serverEvents + 1] = name end,
    CreateThread = function(fn) threads[#threads + 1] = coroutine.create(fn) end,
    SetTimeout = function(ms, fn) timeouts[#timeouts + 1] = { ms = ms, fn = fn } end,
    IsPedRagdoll = function() return state.ragdoll == true end,
    Wait = function() if coroutine.isyieldable() then coroutine.yield() end end,
    PlayerPedId = function() return state.ped end,
    GetEntityCoords = function() return vec(0, 0, 0) end,
    SetEntityHeading = function() end, SetEntityDrawOutline = function(e, on) outlines[e] = on or nil end, SetEntityDrawOutlineColor = function() end,
    GetPedBoneIndex = function(ped, bone) state.bone = { ped = ped, bone = bone }; return 5000 + bone end,
    SetEntityCollision = function(e, on) state.collision = { entity = e, on = on } end,
    StopAnimTask = function() state.stopped = (state.stopped or 0) + 1 end,
    CreateObject = function(model, _, _, _, networked, mission, door)
        state.createdModel = model
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
    math = setmetatable({ random = function(a, b) state.r = ((state.r or 0) % (b or 1)) + 1; return state.r end }, { __index = math }),
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
pump(3) -- Start(): registers targets (third pass reaps the finished thread)
assert(#threads == 0, 'no polling thread is left running')

local function fire(key, new, old) for _, fn in ipairs(cacheListeners[key] or {}) do fn(new, old) end end
local function runTimeouts() local list = timeouts; timeouts = {}; for _, t in ipairs(list) do t.fn() end end

local pickupTarget = {
    onSelect = function() pickups[1].onSelect() end,
    canInteract = function() for _, t in ipairs(pickups) do if t.canInteract() then return true end end return false end,
}
local dutyTarget, dropTarget = targets[3], targets[4]
assert(#pickups == 2 and dutyTarget and dropTarget, 'targets registered')

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
assert(state.doorFlag == false and state.networked == false, 'prop is a plain (non-door) local object unless the server grants networking')
assert(#threads == 0, 'carrying starts no polling thread')
assert(state.anim and state.anim.dict == 'test@dict' and state.anim.flag == 49, 'configured carry anim played with walkable flag')
local firstObject = state.attach.obj

-- 2. Hand-in deletes the prop and requests rewards.
dropTarget.onSelect()
assert(deleted[firstObject] and not dropTarget.canInteract(), 'hand-in removes the prop')
assert(count(serverEvents, 'kora_businesses:recycle:getItem') == 1)

-- 3. Death while carrying drops the prop and releases the pending pickup.
startCarrying()
local obj = state.attach.obj
state.dead = true
fire('isDead', true, false)
assert(deleted[obj] and not dropTarget.canInteract(), 'death removes the prop')
assert(count(serverEvents, 'kora_businesses:recycle:cancelPickup') >= 1, 'death cancels the server pickup')
state.dead = false

-- 4. Ped swap (character switch) drops the prop that was attached to the old ped.
startCarrying()
obj = state.attach.obj
state.ped = 2
fire('ped', 2, 1)
assert(deleted[obj] and not dropTarget.canInteract(), 'ped change removes the prop')
state.ped = 1

-- 5. Anim is re-applied if it was knocked off while carrying.
startCarrying()
state.anim, state.playing = nil, false
state.ragdoll = true
fire('coords', vec(1, 0, 0), vec(0, 0, 0))
assert(not state.anim, 'carry pose waits until the ped is off the floor')
state.ragdoll = false
fire('coords', vec(2, 0, 0), vec(1, 0, 0))
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
serverEvents = {}
pickupTarget.onSelect()
assert(not dropTarget.canInteract(), 'no carry state when the model failed to load')
assert(notifications[#notifications] and notifications[#notifications].type == 'error', 'player is told the pickup failed')
assert(count(serverEvents, 'kora_businesses:recycle:cancelPickup') >= 1, 'failed pickup releases the server authorization')
state.modelOk = true

-- 9. CreateObject failure behaves the same.
reset()
state.createFails = true
serverEvents = {}
pickupTarget.onSelect()
assert(not dropTarget.canInteract() and notifications[#notifications], 'failed object creation is reported')
state.createFails = false
serverEvents = {}
pickupTarget.onSelect()
assert(dropTarget.canInteract(), 'pickup can be retried after a failure')

-- 10. One box at a time: carrying hides the pickup option, ignores select and never cancels the server authorization.
dropTarget.onSelect() -- finish the box carried from test 9
reset()
startCarrying()
local carried = state.attach.obj
local triggersBefore = state.triggers
state.attach = nil
assert(not pickupTarget.canInteract(), 'pickup option hidden while carrying')
serverEvents = {}
pickupTarget.onSelect()
assert(state.triggers == triggersBefore and not state.attach, 'no second pickup while carrying')
assert(count(serverEvents, 'kora_businesses:recycle:cancelPickup') == 0, 'carrying a box keeps its server authorization')
assert(dropTarget.canInteract() and entities[carried], 'box is still carried and can be handed in')

-- 11. Hand-in pays once and a refused pickup after it does not cancel anything.
serverEvents = {}
dropTarget.onSelect()
dropTarget.onSelect()
assert(count(serverEvents, 'kora_businesses:recycle:getItem') == 1, 'hand-in requested once')
state.callbackOk = false
serverEvents = {}
pickupTarget.onSelect()
assert(count(serverEvents, 'kora_businesses:recycle:cancelPickup') == 0, 'refused pickup does not cancel the server state')
state.callbackOk = true
serverEvents = {}
pickupTarget.onSelect()
assert(dropTarget.canInteract(), 'next box can be picked up after a hand-in')

-- 12. Progress bar payloads use kora_lib field names (flag, not flags) and the configured pickup animation.
local bar = bars[1]
assert(bar and bar.anim and bar.anim.dict == 'pick@dict' and bar.anim.clip == 'pick_clip' and bar.anim.flag == 1, 'pickup bar plays the configured animation')
for _, b in ipairs(bars) do assert(not (b.anim and b.anim.flags), 'no unknown anim.flags field') end
assert(bar.disable.move and bar.disable.moveMode == 'controls', 'movement is blocked without freezing the ped')

-- 13. The prop is created from the real model hash with collision off, and the carry pose uses the configured flag.
assert(state.createdModel == 1234 and type(state.createdModel) == 'number', 'CreateObject receives the loaded model hash')
assert(state.collision and state.collision.on == false, 'carried box has collision disabled')

-- 14. Hand-in only shows while carrying; the drop zone uses a vector3 size and a separate rotation.
reset()
if dropTarget.canInteract() then dropTarget.onSelect() end -- finish any box still carried
if not pickupTarget.canInteract() then dutyTarget.onSelect() end -- clock in when needed
assert(not dropTarget.canInteract(), 'no hand-in prompt before picking up')
assert(zoneDefs[4].size.w == nil and zoneDefs[4].rotation ~= nil and zoneDefs[4].size.z >= 2, 'drop zone uses vector3 size + rotation')
local RecycleClient = env.RecycleClient
assert(RecycleClient and not RecycleClient.canHandIn(), 'sell ped hand-in is gated on carrying too')

-- 15. Only the current pallet is outlined, the previous one is cleared and nothing stays outlined while carrying.
local function outlined() local n, which = 0, nil; for e, on in pairs(outlines) do if on then n = n + 1; which = e end end return n, which end
local function currentIndex() for i, t in ipairs(pickups) do if t.canInteract() then return i end end end
local first = currentIndex()
local n, which = outlined()
assert(n == 1 and which == palletEntities[first], 'only the current pallet is outlined')
serverEvents = {}
pickupTarget.onSelect()
assert(outlined() == 0, 'no pallet outlined while the box is carried')
RecycleClient.handIn()
local second = currentIndex()
n, which = outlined()
assert(second and second ~= first and n == 1 and which == palletEntities[second], 'new package outlines only the new pallet')
assert(count(serverEvents, 'kora_businesses:recycle:getItem') == 1, 'hand-in pays out through the server once')


-- 16. Strict entity lockdown regression: a box that vanishes after pickup no longer silently cancels the carry.
reset()
if dropTarget.canInteract() then dropTarget.onSelect() end
if not pickupTarget.canInteract() then dutyTarget.onSelect() end
pickupTarget.onSelect()
local localBox = state.attach.obj
assert(state.networked == false and #timeouts == 0, 'default grant carries a local box with no follow-up check')
fire('coords', vec(5, 0, 0), vec(4, 0, 0))
assert(dropTarget.canInteract() and entities[localBox], 'box stays carried while walking')
dropTarget.onSelect()

-- 17. Networked grant: if the network removes the box anyway, a local one replaces it and the hand-in still pays.
reset()
state.grantNetworked = true
pickupTarget.onSelect()
local netBox = state.attach.obj
assert(state.networked == true and #timeouts == 1, 'server-granted box is networked and verified once')
entities[netBox] = nil -- server lockdown deletes the networked entity
runTimeouts()
assert(state.networked == false and state.attach.obj ~= netBox and entities[state.attach.obj], 'local box replaces the removed networked one')
local replacement = state.attach.obj
assert(dropTarget.canInteract(), 'still carrying after the networked box was removed')
serverEvents = {}
dropTarget.onSelect()
assert(deleted[replacement] and count(serverEvents, 'kora_businesses:recycle:getItem') == 1, 'replacement box is handed in and paid')
state.grantNetworked = false

-- 18. Getting into a vehicle drops the box and releases the authorization.
reset()
pickupTarget.onSelect()
obj = state.attach.obj
fire('vehicle', 77, false)
assert(deleted[obj] and not dropTarget.canInteract(), 'entering a vehicle removes the prop')
assert(count(serverEvents, 'kora_businesses:recycle:cancelPickup') == 1, 'vehicle entry cancels the server pickup')
fire('vehicle', false, 77)
fire('isDead', false, true)
assert(count(serverEvents, 'kora_businesses:recycle:cancelPickup') == 1, 'interrupts are ignored when nothing is carried')

print('kora_businesses recycle carry prop: attach config, failure and cleanup paths passed')
