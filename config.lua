Globals = {}

local isServer = IsDuplicityVersion()
local RESTART = ' Restart kora_businesses to apply a saved change.'

-- Job toggles are defined BEFORE the loader below: on the server `define` merges the saved
-- businesses.config.local.lua overrides immediately, so a saved "off" really skips the job.
-- (The per-job tables are registered later by init.lua through Kora.config.extend.)
Config = Kora.config.define({
    jobs = {
        mechanic = {
            enabled = Kora.config.boolean(true, {
                label = 'Mechanic job',
                description = 'Load the mechanic job (damage wear, repairs, permits).' .. RESTART,
            }),
        },
        taxi = {
            enabled = Kora.config.boolean(true, {
                label = 'Taxi job',
                description = 'Load the taxi job (NPC fares, fare meter). Do not run it together with the old kora_taxi resource.' .. RESTART,
            }),
            meter = {
                enabled = Kora.config.boolean(true, {
                    label = 'Taxi fare meter',
                    description = 'Show the fare meter screen for taxi drivers.' .. RESTART,
                }),
            },
            npcFromOwnTaxi = Kora.config.boolean(true, {
                label = 'NPC fares from any taxi',
                description = 'Let a taxi driver start an NPC fare from the driver seat of any taxi, not only the depot taxi.' .. RESTART,
            }),
            farePerMeter = Kora.config.number(0.2, {
                label = 'NPC fare per metre', min = 0.0, max = 100.0, step = 0.01, live = true,
                description = 'Cash paid per metre between the pickup and the drop-off of an NPC fare.',
            }),
            minSpeedMps = Kora.config.number(45.0, {
                label = 'Fastest believable trip speed (m/s)', min = 1.0, max = 500.0, live = true,
                advanced = true, scope = 'server',
                description = 'An NPC fare is only paid if the trip took at least distance / this speed. Stops teleporting from farming fares; raise it only if honest drivers get refused.',
            }),
            requireOnDuty = Kora.config.boolean(true, {
                label = 'Taxi drivers must be on duty',
                live = true, scope = 'server',
                description = 'Only on-duty taxi drivers can start and complete NPC fares.',
            }),
        },
        garbage = {
            enabled = Kora.config.boolean(true, {
                label = 'Garbage job', description = 'Load the garbage collection job.' .. RESTART,
            }),
        },
        recycle = {
            enabled = Kora.config.boolean(true, {
                label = 'Recycling job', description = 'Load the recycling job and its sell menu.' .. RESTART,
            }),
        },
        tow = {
            enabled = Kora.config.boolean(true, {
                label = 'Tow job', description = 'Load the tow truck job.' .. RESTART,
            }),
        },
        cctv = {
            enabled = Kora.config.boolean(true, {
                label = 'CCTV job', description = 'Load the CCTV engineer job.' .. RESTART,
            }),
        },
        hotdog = {
            enabled = Kora.config.boolean(false, {
                label = 'Hotdog job',
                description = 'Load the hotdog stand job. Off by default; do not run it together with the old kora_hotdogjob resource.' .. RESTART,
            }),
        },
    },
}, { fileName = 'businesses.config.local.lua' })

-- `conflicts` names the legacy standalone resources this job replaces. Both register the same
-- callbacks and events, so the job here steps aside if one of them is already running.
local jobList = {
    {
        name = 'mechanic',
        filepaths = {
            server = { 'jobs/mechanic/server.lua' },
            client = { 'jobs/mechanic/client.lua' },
            shared = { 'jobs/mechanic/shared.lua' },
        },
    },
    {
        name = 'taxi',
        conflicts = { 'kora_taxi' },
        filepaths = {
            server = { 'jobs/taxi/server.lua' },
            client = { 'jobs/taxi/client.lua', 'jobs/taxi/meter.lua' },
            shared = { 'jobs/taxi/shared.lua' },
        },
    },
    {
        name = 'garbage',
        filepaths = {
            server = { 'jobs/garbage/server.lua' },
            client = { 'jobs/garbage/client.lua' },
            shared = { 'jobs/garbage/shared.lua' },
        },
    },
    {
        name = 'recycle',
        filepaths = {
            server = { 'jobs/recycle/server.lua' },
            client = { 'jobs/recycle/client.lua', 'jobs/recycle/sales.lua' },
            shared = { 'jobs/recycle/shared.lua' },
        },
    },
    {
        name = 'tow',
        filepaths = {
            server = { 'jobs/tow/server.lua' },
            client = { 'jobs/tow/client.lua' },
            shared = { 'jobs/tow/shared.lua' },
        },
    },
    {
        name = 'cctv',
        filepaths = {
            server = { 'jobs/cctv/server.lua' },
            client = { 'jobs/cctv/client.lua' },
            shared = { 'jobs/cctv/shared.lua' },
        },
    },
    {
        name = 'hotdog',
        conflicts = { 'kora_hotdogjob' },
        filepaths = {
            server = { 'jobs/hotdog/server.lua' },
            client = { 'jobs/hotdog/client.lua' },
            shared = { 'jobs/hotdog/config.lua' },
        },
    },
}

local function requireAll(list)
    if not list then return end
    for i = 1, #list do
        Kora.require.current(list[i])
    end
end

local function conflictingResource(job)
    for _, resource in ipairs(job.conflicts or {}) do
        local state = GetResourceState(resource)
        if state == 'started' or state == 'starting' then return resource end
    end
end

-- The server decides which jobs load. Only the server sees the saved overrides at start-up, so
-- the client asks it instead of trusting its own (still default) copy of Config.jobs.
local function enabledJobs()
    local enabled = {}
    for _, job in ipairs(jobList) do
        local entry = Config.jobs[job.name]
        enabled[job.name] = entry ~= nil and entry.enabled == true and conflictingResource(job) == nil
    end
    return enabled
end

local function loadJobs(enabled)
    for _, job in ipairs(jobList) do
        if enabled[job.name] then
            local paths = job.filepaths
            requireAll(paths.shared)
            requireAll(isServer and paths.server or paths.client)
        elseif isServer then
            local blocker = conflictingResource(job)
            if blocker then
                print(('[jobs] %s is skipped: the standalone %s resource is running; stop it to use the one here'):format(job.name, blocker))
            else
                print(('[jobs] %s is disabled, skipping'):format(job.name))
            end
        end
    end
    Kora.require.current('init.lua')
end

if isServer then
    Kora.callback.register('kora_businesses:enabledJobs', function()
        return enabledJobs()
    end)
    loadJobs(enabledJobs())
else
    CreateThread(function()
        local enabled = Kora.callback.trigger('kora_businesses:enabledJobs')
        loadJobs(type(enabled) == 'table' and enabled or enabledJobs())
    end)
end
