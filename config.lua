Config = {}
Globals = {}

Config.Mechanic = true
Config.Taxi = true
Config.Garbage = true
Config.Recycle = true
Config.enable = {
    {
        name = 'mechanic',
        enabled = Config.Mechanic,
        filepaths = {
            server = { 'jobs/mechanic/server.lua' },
            client = { 'jobs/mechanic/client.lua' },
            shared = { 'jobs/mechanic/shared.lua' },
        },
    },
    {
        name = 'taxi',
        enabled = Config.Taxi,
        filepaths = {
            server = { 'jobs/taxi/server.lua' },
            client = { 'jobs/taxi/client.lua' },
            shared = { 'jobs/taxi/shared.lua' },
        },
    },
    {
        name = 'garbage',
        enabled = Config.Garbage,
        filepaths = {
            server = { 'jobs/garbage/server.lua' },
            client = { 'jobs/garbage/client.lua' },
            shared = { 'jobs/garbage/shared.lua' },
        },
    },
    {
        name = 'recycle',
        enabled = Config.Recycle,
        filepaths = {
            server = { 'jobs/recycle/server.lua' },
            client = { 'jobs/recycle/client.lua', 'jobs/recycle/sales.lua' },
            shared = { 'jobs/recycle/shared.lua' },
        },
    },
}

local function requireAll(list)
    if not list then return end
    for i = 1, #list do
        QB.require.current(list[i])
    end
end

local isServer = IsDuplicityVersion()

for _, job in ipairs(Config.enable) do
    if job.enabled then
        local paths = job.filepaths or {}
        requireAll(paths.shared)
        requireAll(isServer and paths.server or paths.client)
    else
        print(('[jobs] %s is disabled, skipping'):format(job.name))
    end
end

Globals.Config = Config

QB.require.current('init.lua')