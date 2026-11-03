-- Job toggles: config.lua must define Config.jobs (with saved overrides merged) BEFORE the loader
-- runs, using the real kora_lib config consumer. Set KORA_LIB_ROOT if kora_lib lives elsewhere.
local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'
local libRoot = os.getenv('KORA_LIB_ROOT') or root .. '../kora_lib'
local makeConfig = dofile(libRoot .. '/modules/config/consumer.lua')

local JOBS = { 'mechanic', 'taxi', 'garbage', 'recycle', 'tow', 'cctv', 'hotdog' }
local checks = 0
local function check(value, label)
    assert(value, label)
    checks = checks + 1
end

local files, netEvents, serverEvents, registered = {}, {}, {}, {}
local function boot(options)
    files = options.files or {}
    netEvents, serverEvents, registered = {}, {}, {}
    _G.GetCurrentResourceName = function() return 'kora_businesses' end
    _G.IsDuplicityVersion = function() return options.server end
    _G.LoadResourceFile = function(_, path) return files[path] end
    _G.SaveResourceFile = function(_, path, contents) files[path] = contents; return true end
    _G.RegisterNetEvent = function(name, handler) if handler then netEvents[name] = handler end end
    _G.AddEventHandler = function() end
    _G.TriggerServerEvent = function(name, ...) serverEvents[#serverEvents + 1] = { name = name, ... } end
    _G.GetInvokingResource = function() return 'kora_lib' end
    _G.TriggerClientEvent = function() end
    _G.exports = options.server and setmetatable({}, { __call = function(_, name, fn) registered[name] = fn end }) or nil

    local required, callbacks, printed = {}, {}, {}
    local env = setmetatable({
        Kora = {
            config = makeConfig({ config_register = function() return true end, config_open = function() return true end }),
            require = { current = function(path) required[#required + 1] = path end },
            callback = {
                register = function(name, fn) callbacks[name] = fn end,
                trigger = function(name) return options.serverMap end,
            },
        },
        GetResourceState = function(resource) return options.running and options.running[resource] or 'missing' end,
        CreateThread = function(fn) fn() end,
        print = function(...) printed[#printed + 1] = table.concat({ ... }, ' ') end,
    }, { __index = _G })
    assert(loadfile(root .. 'config.lua', 't', env))()
    return env, required, callbacks, printed
end

local function has(list, value)
    for _, entry in ipairs(list) do if entry == value then return true end end
    return false
end

-- 1. Defaults: every job loads except hotdog (D3).
do
    local env, required = boot({ server = true })
    for _, name in ipairs(JOBS) do
        check(type(env.Config.jobs[name].enabled) == 'boolean', name .. ' has a toggle')
    end
    check(env.Config.jobs.hotdog.enabled == false, 'hotdog is off by default')
    for _, name in ipairs({ 'mechanic', 'taxi', 'garbage', 'recycle', 'tow', 'cctv' }) do
        check(has(required, 'jobs/' .. name .. '/server.lua') and has(required, 'jobs/' .. name .. '/shared.lua'),
            name .. ' loads by default')
    end
    check(not has(required, 'jobs/hotdog/server.lua') and not has(required, 'jobs/hotdog/config.lua'), 'hotdog is skipped')
    check(has(required, 'jobs/mechanic/props.lua'), 'the mechanic SaveVehicleProps handler loads with the job')
    check(env.Config.jobs.mechanic.persistCosmetics == true, 'mechanic cosmetics persist by default')
    check(not has(required, 'jobs/taxi/client.lua'), 'server never loads client files')
    check(required[#required] == 'init.lua', 'init.lua loads after the jobs')
    check(env.Config.jobs.taxi.farePerMeter == 0.2 and env.Config.jobs.taxi.minSpeedMps == 45.0
        and env.Config.jobs.taxi.requireOnDuty == true and env.Config.jobs.taxi.meter.enabled == true
        and env.Config.jobs.taxi.npcFromOwnTaxi == true, 'taxi defaults match the plan')
end

-- 2. A saved override really changes what the server loads (this never worked before: the loader
-- ran before the override was merged).
do
    local env, required, _, printed = boot({ server = true, files = {
        ['businesses.config.local.lua'] = 'return { jobs = { taxi = { enabled = false }, hotdog = { enabled = true } } }',
    } })
    check(env.Config.jobs.taxi.enabled == false and env.Config.jobs.hotdog.enabled == true, 'override merged')
    check(not has(required, 'jobs/taxi/server.lua') and not has(required, 'jobs/taxi/shared.lua'), 'disabled taxi is not loaded')
    check(has(required, 'jobs/hotdog/server.lua') and has(required, 'jobs/hotdog/config.lua'), 'enabled hotdog is loaded')
    check(has(required, 'jobs/garbage/server.lua'), 'untouched jobs keep loading')
    local skipped = false
    for _, line in ipairs(printed) do if line:find('taxi is disabled', 1, true) then skipped = true end end
    check(skipped, 'a skipped job is logged')
end

-- 3. The legacy standalone resources win while they run (same callbacks and events).
do
    local env, required, _, printed = boot({ server = true, running = { kora_taxi = 'started', kora_hotdogjob = 'starting' },
        files = { ['businesses.config.local.lua'] = 'return { jobs = { hotdog = { enabled = true } } }' } })
    check(env.Config.jobs.taxi.enabled == true, 'config still says enabled')
    check(not has(required, 'jobs/taxi/server.lua'), 'taxi steps aside for a running kora_taxi')
    check(not has(required, 'jobs/hotdog/server.lua'), 'hotdog steps aside for a running kora_hotdogjob')
    local mentioned = false
    for _, line in ipairs(printed) do if line:find('kora_taxi', 1, true) then mentioned = true end end
    check(mentioned, 'the conflict is logged')
    local _, requiredStopped = boot({ server = true, running = { kora_taxi = 'stopped' } })
    check(has(requiredStopped, 'jobs/taxi/server.lua'), 'a stopped kora_taxi does not block')
end

-- 4. The server tells clients which jobs loaded, and the client follows it, not its own defaults.
do
    local env, _, callbacks = boot({ server = true, files = {
        ['businesses.config.local.lua'] = 'return { jobs = { cctv = { enabled = false } } }',
    } })
    local map = callbacks['kora_businesses:enabledJobs']()
    check(map.cctv == false and map.taxi == true and map.hotdog == false, 'callback reports the server toggles')

    local clientEnv, required = boot({ server = false, serverMap = map })
    check(clientEnv.Config.jobs.cctv.enabled == true, 'the client config is still on defaults at start')
    check(not has(required, 'jobs/cctv/client.lua') and has(required, 'jobs/taxi/client.lua')
        and has(required, 'jobs/taxi/meter.lua') and has(required, 'jobs/taxi/shared.lua'), 'client follows the server map')
    check(not has(required, 'jobs/taxi/server.lua'), 'client never loads server files')

    local _, fallback = boot({ server = false })
    check(has(fallback, 'jobs/cctv/client.lua') and not has(fallback, 'jobs/hotdog/client.lua'),
        'without a server answer the client falls back to its local config')
end

-- 5. init.lua registers the job tables once the toggles exist and mirrors saved/live values back
-- into the tables the jobs read.
do
    local env = boot({ server = true, files = {
        ['businesses.config.local.lua'] = 'return { Garbage = { payout = 9 } }',
    } })
    env.Globals.Garbage = { payout = 5, list = { 1, 2, 3 }, callback = function() end }
    assert(loadfile(root .. 'init.lua', 't', env))()
    check(env.Globals.Garbage.payout == 9, 'saved job override reaches the job table')
    check(#env.Globals.Garbage.list == 3 and type(env.Globals.Garbage.callback) == 'function', 'untouched fields survive')
    check(env.Config.jobs.taxi.enabled == true, 'extend keeps the toggles')

    local clientEnv = boot({ server = false })
    clientEnv.Globals.Garbage = { payout = 5 }
    assert(loadfile(root .. 'init.lua', 't', clientEnv))()
    local request = serverEvents[#serverEvents]
    check(request and request.name == 'kora_lib:server:configRequested', 'client requests its snapshot')
    netEvents['kora_lib:client:configSnapshot']('kora_businesses', { Garbage = { payout = 12 } }, 2, request[2])
    check(clientEnv.Globals.Garbage.payout == 12, 'client snapshot reaches the job table')
end

-- 6. The hotdog stock icon exists, is shipped to clients and is referenced by the right nui path.
do
    local function read(path)
        local handle = assert(io.open(root .. path, 'rb'))
        local text = handle:read('a')
        handle:close()
        return text
    end
    check(#read('jobs/hotdog/icon.png') > 8, 'hotdog icon.png exists')
    check(read('fxmanifest.lua'):find("'jobs/hotdog/icon.png'", 1, true), 'icon is in the manifest files')
    check(read('fxmanifest.lua'):find("provide 'qb-mechanicjob'", 1, true) and read('fxmanifest.lua'):find("provide 'qbmechanic'", 1, true),
        'the legacy mechanic resource names are provided')
    check(read('jobs/hotdog/client.lua'):find("nui://kora_businesses/jobs/hotdog/icon.png", 1, true),
        'client points at the kora_businesses nui path')
    check(not read('jobs/hotdog/client.lua'):find('qb-hotdogjob/icon.png', 1, true), 'no stale qb-hotdogjob path')
end

print(('kora_businesses config toggles: %d checks passed'):format(checks))
