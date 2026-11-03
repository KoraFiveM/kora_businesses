-- News job (jobs/news): F#277/278 (equipment and trunk fills are distance/cooldown/owned limited, one fill per
-- spawned vehicle), F#279 (no per-frame poll while holding equipment), F#280 (store option, active-vehicle cap,
-- bounded server table), F#281 (every locale key exists), F#282 (no export in canInteract), F#283 (blip lifecycle).
local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'
local checks = 0
local function equal(actual, expected, message)
    checks = checks + 1
    if actual ~= expected then error(('%s: expected %s, got %s'):format(message, tostring(expected), tostring(actual)), 2) end
end

local function read(path)
    local handle = assert(io.open(root .. path, 'rb'))
    local text = handle:read('a')
    handle:close()
    return text
end

local function newEnv()
    local env = {}
    for name, value in pairs(_G) do env[name] = value end
    env.Globals = {}
    env.vector3 = function(x, y, z) return { x = x, y = y, z = z } end
    env.vector4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end
    env.Config = { jobs = { news = { jobName = 'reporter', equipmentCooldownSeconds = 300, maxActiveVehicles = 1 } } }
    assert(loadfile(root .. 'jobs/news/shared.lua', 't', env))()
    return env
end

-- ===== server =====
local function server()
    local env = newEnv()
    local s = { now = 1000000, job = 'reporter', pos = env.News.Locations.shop, owned = {}, added = {}, trunks = {},
        notices = {}, deleted = {}, removedKeys = {}, existing = {}, events = {}, handlers = {}, callbacks = {}, hasKeys = true,
        nextNet = 100, env = env }
    local function samePoint(a, b, dist)
        local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
        return dx * dx + dy * dy + dz * dz <= dist * dist
    end
    s.entityPos = {}
    env.GetGameTimer = function() return s.now end
    env.GetCurrentResourceName = function() return 'kora_businesses' end
    env.source = 5
    env.RegisterNetEvent = function(name, fn) s.events[name] = fn end
    env.AddEventHandler = function(name, fn) s.handlers[name] = fn end
    env.NetworkGetEntityFromNetworkId = function(netId) return netId + 1000 end
    env.DoesEntityExist = function(e) return s.existing[e] == true end
    env.DeleteEntity = function(e) s.existing[e] = nil; s.deleted[#s.deleted + 1] = e end
    env.SetEntityRoutingBucket = function() end
    env.GetPlayerRoutingBucket = function() return 0 end
    env.SetVehicleNumberPlateText = function(e, plate) s.plates = s.plates or {}; s.plates[e] = plate end
    env.TriggerClientEvent = function() end
    env.Kora = {
        callback = { register = function(name, fn, opts) s.callbacks[name] = fn; s.opts = s.opts or {}; s.opts[name] = opts end },
        notify = { send = function(_, data) s.notices[#s.notices + 1] = data.message end },
        distance = {
            player = function(_, coords, dist) return samePoint(s.pos, coords, dist) end,
            entity = function(_, entity, dist) return samePoint(s.pos, s.entityPos[entity] or s.pos, dist) end,
        },
        entities = { createVehicle = function()
            s.nextNet = s.nextNet + 1
            s.existing[s.nextNet + 1000] = true
            return s.nextNet
        end },
        timers = { cooldown = function(interval)
            local last = {}
            return {
                use = function(key)
                    if last[key] and s.now - last[key] < interval then return false end
                    last[key] = s.now
                    return true
                end,
                remaining = function(key) return last[key] and math.max(0, interval - (s.now - last[key])) or 0 end,
                reset = function(key) if key == nil then last = {} else last[key] = nil end end,
            }
        end },
    }
    env.exports = {
        kora_core = {
            getPlayerData = function() return s.job end,
            createUseable = function(_, name, fn) s.useable = s.useable or {}; s.useable[name] = fn end,
        },
        kora_inventory = { getItemCount = function(_, _, item) return s.owned[item] or 0 end },
        kora_vehiclekeys = { removeKeys = function(_, src, plate) s.removedKeys[#s.removedKeys + 1] = plate end },
        ['qb-vehiclekeys'] = { HasKeys = function() return s.hasKeys end },
        ['qb-inventory'] = {
            CreateInventory = function(_, name) s.trunks[name] = s.trunks[name] or {} end,
            AddItem = function(_, target, item)
                if type(target) == 'number' then
                    s.owned[item] = (s.owned[item] or 0) + 1
                    s.added[#s.added + 1] = item
                else
                    local trunk = s.trunks[target]
                    trunk[#trunk + 1] = item
                end
                return true
            end,
        },
    }
    assert(loadfile(root .. 'jobs/news/server.lua', 't', env))()
    return s
end

-- 1. Equipment (F#277).
do
    local s = server()
    local request = s.events['qb-newsjob:server:requestedEquipment']
    s.pos = { x = 0, y = 0, z = 0 }
    for _ = 1, 50 do request('newscam') end
    equal(#s.added, 0, 'equipment cannot be requested from away from the shop')
    s.pos = s.env.News.Locations.shop
    request('lasergun'); request(nil); request({})
    equal(#s.added, 0, 'only the three news items can be requested')
    s.job = 'police'
    request('newscam')
    equal(#s.added, 0, 'other jobs get nothing')
    s.job = 'reporter'
    request('newscam')
    equal(#s.added, 1, 'a reporter at the shop gets the camera')
    for _ = 1, 20 do request('newscam') end
    equal(#s.added, 1, 'spamming the same item adds nothing while owned')
    s.owned.newscam = 0
    request('newscam')
    equal(#s.added, 1, 'the cooldown applies even after the item is gone')
    equal(s.notices[#s.notices]:find('Wait', 1, true) ~= nil, true, 'the reporter is told to wait')
    request('newsmic')
    equal(#s.added, 2, 'a different item has its own cooldown')
    s.now = s.now + 300 * 1000
    request('newscam')
    equal(#s.added, 3, 'after the cooldown the item can be taken again')
    s.job = 'journalist'
    s.env.Config.jobs.news.jobName = 'journalist'
    s.owned.newsbmic = 0
    request('newsbmic')
    equal(s.added[#s.added], 'newsbmic', 'the job name is configurable')
end

-- 2. Garage vehicles (F#280).
do
    local s = server()
    local spawn = s.callbacks['qb-newsjob:server:spawnVehicle']
    local store = s.callbacks['qb-newsjob:server:storeVehicle']
    equal(type(s.opts['qb-newsjob:server:spawnVehicle'] and s.opts['qb-newsjob:server:spawnVehicle'].rateLimit), 'table', 'spawning is rate limited')
    local garage = s.env.News.Locations.vehicle.coords
    s.pos = { x = 0, y = 0, z = 0 }
    equal(spawn(5, 'vehicle', 1), false, 'cannot spawn away from the garage')
    s.pos = garage
    equal(spawn(5, 'boat', 1), false, 'unknown garage refused')
    equal(spawn(5, 'vehicle', 99), false, 'unknown vehicle refused')
    s.job = 'police'
    equal(spawn(5, 'vehicle', 1), false, 'other jobs cannot spawn')
    s.job = 'reporter'
    local netId, plate = spawn(5, 'vehicle', 1)
    equal(type(netId), 'number', 'a reporter at the garage gets a vehicle')
    equal(plate:match('^WZNW%d%d%d%d$') ~= nil, true, 'the server picks the plate')
    equal(s.plates[netId + 1000], plate, 'the plate is set on the entity')
    equal(spawn(5, 'vehicle', 1), false, 'one active vehicle per reporter by default')
    s.env.Config.jobs.news.maxActiveVehicles = 2
    local second = spawn(5, 'vehicle', 1)
    equal(type(second), 'number', 'the cap is a live setting')
    s.env.Config.jobs.news.maxActiveVehicles = 1
    equal(store(5, second), true, 'the extra vehicle can be stored')

    -- storing
    equal(store(6, netId), false, 'another player cannot store it')
    equal(store(5, 99999), false, 'unknown vehicle refused')
    equal(store(5, 'x'), false, 'non-number refused')
    s.entityPos[netId + 1000] = { x = 500, y = 0, z = 0 }
    equal(store(5, netId), false, 'the vehicle must be at the garage')
    s.entityPos[netId + 1000] = nil
    equal(store(5, netId), true, 'a vehicle at the garage can be stored')
    equal(s.deleted[#s.deleted], netId + 1000, 'the entity is deleted')
    equal(s.removedKeys[#s.removedKeys], plate, 'the keys are removed')
    equal(store(5, netId), false, 'a stored vehicle cannot be stored again')
    local again = spawn(5, 'vehicle', 1)
    equal(type(again), 'number', 'storing frees the slot')

    -- destroyed elsewhere: pruned lazily
    s.existing[again + 1000] = nil
    equal(type(spawn(5, 'vehicle', 1)), 'number', 'a destroyed vehicle no longer counts')

    -- leaving deletes the vehicle
    local last = s.nextNet + 1000
    s.handlers.playerDropped()
    equal(s.deleted[#s.deleted], last, 'a dropped player\'s vehicle is cleaned up')
    equal(type(spawn(5, 'vehicle', 1)), 'number', 'nothing is left behind in the table')

    -- resource stop
    local live = s.nextNet + 1000
    s.handlers.onResourceStop('kora_businesses')
    equal(s.deleted[#s.deleted], live, 'resource stop deletes the remaining vehicles')
end

-- 3. Trunk items (F#278).
do
    local s = server()
    local spawn = s.callbacks['qb-newsjob:server:spawnVehicle']
    local store = s.callbacks['qb-newsjob:server:storeVehicle']
    local fill = s.events['qb-newsjob:server:addVehicleItems']
    s.pos = s.env.News.Locations.vehicle.coords
    fill('ZZZZ999'); fill(nil); fill({})
    equal(next(s.trunks), nil, 'an unknown plate stocks nothing')
    local netId, plate = spawn(5, 'vehicle', 1)
    s.hasKeys = false
    fill(plate)
    equal(next(s.trunks), nil, 'no keys, no trunk fill')
    s.hasKeys = true
    s.entityPos[netId + 1000] = { x = 500, y = 0, z = 0 }
    fill(plate)
    equal(next(s.trunks), nil, 'the vehicle must be near the player')
    s.entityPos[netId + 1000] = nil
    s.env.source = 6
    fill(plate)
    equal(next(s.trunks), nil, 'someone else\'s vehicle cannot be stocked')
    s.env.source = 5
    fill(' ' .. plate:lower() .. ' ')
    equal(#s.trunks['trunk-' .. plate], 3, 'the owner stocks the three news items')
    fill(plate)
    equal(#s.trunks['trunk-' .. plate], 3, 'a vehicle is stocked once')

    store(5, netId)
    local second, secondPlate = spawn(5, 'vehicle', 1)
    fill(secondPlate)
    equal(s.trunks['trunk-' .. secondPlate], nil, 'store/spawn cycling does not refill within the cooldown')
    store(5, second)
    s.now = s.now + 300 * 1000
    local third, thirdPlate = spawn(5, 'vehicle', 1)
    fill(thirdPlate)
    equal(#s.trunks['trunk-' .. thirdPlate], 3, 'a fresh vehicle is stocked after the cooldown')
    store(5, third)
    s.pos = s.env.News.Locations.heli.coords
    local heli, heliPlate = spawn(5, 'heli', 1)
    fill(heliPlate)
    equal(s.trunks['trunk-' .. heliPlate], nil, 'helicopters are not stocked')
end

-- ===== client =====
local function client(job)
    local env = newEnv()
    local c = { threads = {}, waits = {}, zones = {}, netEvents = {}, handlers = {}, cache = {}, exportCalls = 0, langKeys = {},
        blips = 0, removedBlips = 0, props = 0, closes = 0, cameraOpen = false, callbacks = {}, job = job, env = env }
    env.CreateThread = function(fn) c.threads[#c.threads + 1] = coroutine.create(fn) end
    env.Wait = function(ms) c.waits[#c.waits + 1] = ms; coroutine.yield() end
    env.RegisterNetEvent = function(name, fn) c.netEvents[name] = fn end
    env.AddEventHandler = function(name, fn) c.handlers[name] = fn end
    env.GetCurrentResourceName = function() return 'kora_businesses' end
    env.DoesEntityExist = function() return true end
    env.DeleteEntity = function() c.props = c.props - 1 end
    env.CreateObject = function() c.props = c.props + 1; return 55 end
    env.GetVehiclePedIsIn = function() return c.vehicle or 0 end
    env.NetworkGetNetworkIdFromEntity = function() return 321 end
    env.joaat = function() return 1 end
    env.GetEntityCoords = function() return env.vector3(0, 0, 0) end
    env.exports = { kora_core = { getPlayerData = function() c.exportCalls = c.exportCalls + 1; return c.job end } }
    local mt = { __index = function(_, key) if type(key) == 'string' and key ~= 'CurrentPlate' and key:match('^%u') then return function() return 0 end end end }
    setmetatable(env, { __index = function(t, key) return mt.__index(t, key) end })
    env.Kora = {
        lang = function(key) c.langKeys[#c.langKeys + 1] = key; return key end,
        cache = { ped = function() return 1 end, onChange = function(key, fn) c.cache[key] = fn end },
        blips = { create = function() c.blips = c.blips + 1; return c.blips end, remove = function() c.removedBlips = c.removedBlips + 1 end },
        interact = { addBoxZone = function(name, _, _, options) c.zones[name] = options end },
        visuals = { fade = function() end },
        vehicle = { plate = function() return c.plate end, requestControl = function() return true end, setProperties = function() end },
        stream = { loadModel = function() return true end, loadAnimDict = function() return true end },
        camera = {
            open = function() c.cameraOpen = true end,
            close = function() c.closes = c.closes + 1; c.cameraOpen = false end,
            isOpen = function() return c.cameraOpen end,
        },
        callback = { trigger = function(name, ...) c.callbacks[#c.callbacks + 1] = { name = name, ... }; return c.triggerResult end },
        nui = { registerApp = function() end, openApp = function() end },
        loops = { controlled = function() return 9 end },
    }
    function c.step()
        for _, thread in ipairs(c.threads) do
            if coroutine.status(thread) == 'suspended' then assert(coroutine.resume(thread)) end
        end
    end
    function c.alive()
        local n = 0
        for _, thread in ipairs(c.threads) do if coroutine.status(thread) ~= 'dead' then n = n + 1 end end
        return n
    end
    for _, file in ipairs({ 'client', 'spawner', 'camera' }) do
        assert(loadfile(root .. 'jobs/news/' .. file .. '.lua', 't', env))()
    end
    c.step()
    return c
end

-- 4. Job cache, blip lifecycle and zones (F#282, F#283).
do
    local c = client({ name = 'reporter' })
    equal(c.blips, 1, 'the garage blip is created on resource start for a reporter (F#283)')
    equal(c.exportCalls, 1, 'the job is read once at start-up')
    local calls = c.exportCalls
    for _, name in ipairs({ 'news_garage', 'news_heli', 'news_equipment_shop', 'news_door_in', 'news_door_out' }) do
        equal(c.zones[name] ~= nil, true, name .. ' zone exists')
        for _, option in ipairs(c.zones[name]) do
            if option.canInteract then equal(option.canInteract(), not option.label:find('store_vehicle', 1, true), name .. ' canInteract for a reporter') end
        end
    end
    equal(c.exportCalls, calls, 'canInteract never calls an export (F#282)')
    c.netEvents['QBCore:Client:OnJobUpdate']({ name = 'police' })
    equal(c.removedBlips, 1, 'losing the job removes the blip')
    equal(c.zones.news_garage[1].canInteract(), false, 'the cached job gates the options')
    c.netEvents['QBCore:Client:OnJobUpdate']({ name = 'reporter' })
    equal(c.blips, 2, 'getting the job adds the blip')
    c.netEvents['QBCore:Client:OnJobUpdate']({ name = 'reporter' })
    equal(c.blips, 2, 'a repeated job update does not duplicate the blip')
    c.netEvents['QBCore:Client:OnPlayerUnload']()
    equal(c.removedBlips, 2, 'unloading removes the blip')
    c.job = { name = 'reporter' }
    c.netEvents['QBCore:Client:OnPlayerLoaded']()
    equal(c.blips, 3, 'loading in as a reporter adds the blip')
    c.handlers.onClientResourceStop('kora_businesses')
    equal(c.removedBlips, 3, 'stopping the resource removes the blip')
    equal(client({ name = 'police' }).blips, 0, 'other jobs get no blip')
end

-- 5. Equipment has no per-frame poll (F#279).
do
    local c = client({ name = 'reporter' })
    c.netEvents['Mic:ToggleMic']()
    equal(c.props, 1, 'the microphone prop is created')
    c.step(); c.step()
    equal(c.alive(), 0, 'holding a microphone starts no worker')
    c.netEvents['Mic:ToggleMic']()
    equal(c.props, 0, 'toggling again removes it')

    c.netEvents['Cam:ToggleCam']()
    equal(c.cameraOpen, true, 'the camera overlay opens')
    equal(c.alive(), 1, 'only the camera starts a watcher')
    for _ = 1, 5 do c.step() end
    local fastest = math.huge
    for _, ms in ipairs(c.waits) do fastest = math.min(fastest, ms) end
    equal(fastest >= 250, true, 'the camera watcher polls no faster than 250 ms')
    c.cameraOpen = false
    c.step()
    equal(c.props, 0, 'closing the camera removes the equipment')
    c.step()
    equal(c.alive(), 0, 'and the watcher ends')

    c.netEvents['Mic:ToggleBMic']()
    c.cache.isDead(true)
    equal(c.props, 0, 'dying removes the equipment through the isDead event')
    c.netEvents['Mic:ToggleBMic']()
    c.netEvents['QBCore:Client:OnJobUpdate']({ name = 'police' })
    equal(c.props, 0, 'losing the job removes the equipment through the job event')
    c.netEvents['Mic:ToggleBMic']()
    equal(c.props, 0, 'a non-reporter cannot use the equipment')
    c.cache.onChange = nil
    c.handlers.onClientResourceStart('kora_lib')
    equal(type(c.cache.isDead), 'function', 'the death listener is re-registered when kora_lib restarts')
end

-- 6. Storing a vehicle (F#280).
do
    local c = client({ name = 'reporter' })
    c.env.CurrentPlate.WZNW1234 = true
    c.plate, c.vehicle, c.triggerResult = 'WZNW1234', 77, true
    c.env.storeCurrentVehicle()
    equal(c.callbacks[1].name, 'qb-newsjob:server:storeVehicle', 'the store option asks the server')
    equal(c.callbacks[1][1], 321, 'with the vehicle net id')
    equal(c.env.CurrentPlate.WZNW1234, nil, 'a stored vehicle is forgotten')
    c.env.CurrentPlate.WZNW1234 = true
    c.triggerResult = false
    c.env.storeCurrentVehicle()
    equal(c.env.CurrentPlate.WZNW1234, true, 'a refused store keeps it')
    c.plate = 'OTHER'
    local before = #c.callbacks
    c.env.storeCurrentVehicle()
    equal(#c.callbacks, before, 'only news vehicles are offered for storing')
    local store = c.zones.news_garage[2]
    c.vehicle = 0
    equal(store.canInteract(), false, 'the store option needs a vehicle')
    c.vehicle = 77
    equal(store.canInteract(), true, 'the store option shows in a vehicle')
end

-- 7. Locale keys (F#281): every key the job asks for exists.
do
    local locale = dofile(root .. 'locales/en.lua')
    local function lookup(key)
        local node = locale
        for part in key:gmatch('[^.]+') do node = type(node) == 'table' and node[part] or nil end
        return node
    end
    for _, file in ipairs({ 'client', 'spawner', 'camera' }) do
        for key in read('jobs/news/' .. file .. '.lua'):gmatch("Kora%.lang%('([%w_.]+)'%)") do
            equal(type(lookup(key)), 'string', 'locale key ' .. key)
        end
    end
    equal(type(lookup('news.text.vehicle')) == 'string' and type(lookup('news.text.heli')) == 'string', true, 'garage view titles exist')
    equal(read('jobs/news/client.lua'):find("text.exit", 1, true), nil, 'the undefined text.exit key is gone')
end

-- 8. The job is off by default, uses the reporter job and is wired into the loader.
do
    local config = read('config.lua')
    equal(config:find("name = 'news'", 1, true) ~= nil and config:find("jobs/news/server.lua", 1, true) ~= nil, true, 'news is in the job list')
    equal(config:find("jobName = Kora.config.string('reporter'", 1, true) ~= nil, true, 'the default job is reporter')
    equal(read('jobs/news/server.lua'):find("'news'", 1, true), nil, 'the server never hard-codes the non-existent news job')
end

print(('kora_businesses news: %d checks passed'):format(checks))
