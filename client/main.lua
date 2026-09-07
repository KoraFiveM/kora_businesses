-- Lifecycle: receive the world, rebuild it, and tear it down cleanly.
--
-- A sync is a full replacement rather than a diff. Definitions change rarely
-- (an admin editing one), and rebuilding a business outright is both simpler to
-- reason about and impossible to leave half-applied -- the alternative would be
-- diffing zone geometry, prop placement and target registrations against each
-- other for no measurable gain.

QbBusinesses = QbBusinesses or {}

local Client = QbBusinesses.client
local Business = QbBusinesses.Business
local Creator = QbBusinesses.creator

local RESOURCE = GetCurrentResourceName()

---@type table<string, table> businessId -> live Business
local live = {}
local hydrating = false
local lastPresenceJob = nil

---@param definitions table[]
local function apply(definitions)
    local incoming = {}
    for _, definition in ipairs(definitions or {}) do incoming[definition.id] = definition end

    for id, business in pairs(live) do
        if not incoming[id] then
            Business.destroy(business)
            live[id] = nil
            Client.definitions[id] = nil
        end
    end

    for id, definition in pairs(incoming) do
        -- Rebuild only what actually changed. A player standing inside a
        -- business whose neighbour was edited should not have their own tills
        -- flicker out and back. `rev` is the server's own fingerprint of the
        -- definition -- comparing encoded tables here would not work, since
        -- json.encode gives no key-order guarantee.
        local previous = Client.definitions[id]
        if not previous or previous.rev ~= definition.rev then
            if live[id] then live[id]:destroy() end
            Client.definitions[id] = definition
            live[id] = Business.create(definition)
        end
    end

    Creator.refresh()
end

RegisterNetEvent('qbbusinesses:client:sync', function(definitions)
    apply(definitions)
end)

RegisterNetEvent('qbbusinesses:client:staff', function(counts)
    Client.staff = type(counts) == 'table' and counts or {}
    Creator.refresh()
end)

---Rebuild local world handles so qbtarget/qblib pick up an administrator's
---debug-visualisation preference. This is intentionally client-local: debug
---outlines are a troubleshooting aid, not shared business data.
---@param value boolean
function Client.setDebug(value)
    Client.debug = value == true
    for id, business in pairs(live) do
        local definition = Client.definitions[id]
        Business.destroy(business)
        live[id] = Business.create(definition)
    end
    Creator.refresh()
end

---A job change does not move any zone, but it does change what the player may
---see and whether they should be clocked in where they are standing.
RegisterNetEvent('QBCore:Client:OnJobUpdate', function()
    -- qbcore can emit the compatibility job event more than once for one
    -- replicated change. Presence only depends on the job name, so repeating
    -- the same transition would send identical enter/leave callbacks for every
    -- business the player is standing in and eventually trip their rate limit.
    local jobName = Client.job().name
    if jobName == lastPresenceJob then return end
    lastPresenceJob = jobName

    CreateThread(function()
        for _, business in pairs(live) do
            if business.inside then
                if Client.worksFor(business) then
                    if business.controlDuty and Config.duty.enabled then Business.setDuty(business, true) end
                    QB.callback.trigger('qbbusinesses:server:enter', business.id)
                else
                    QB.callback.trigger('qbbusinesses:server:leave', business.id)
                end
            end
        end
        Creator.refresh()
    end)
end)

local function hydrate()
    -- Login, job, and duty events can all be delivered as the client mirror
    -- settles. One hydrate contains the complete snapshot, so concurrent
    -- requests only duplicate work and can consume the server callback quota.
    if hydrating then return false end
    hydrating = true
    local data = QB.callback.trigger('qbbusinesses:server:hydrate')
    if type(data) == 'table' then
        Creator.setAdmin(data.admin)
        Client.staff = data.staff or {}
        apply(data.businesses)
    end
    hydrating = false
    return type(data) == 'table' and data.ready == true
end

CreateThread(function()
    -- The server broadcasts on boot and on character load, but a client that
    -- restarts this resource on its own would otherwise sit empty until the
    -- next edit, so ask once at start too.
    while not hydrate() do Wait(2000) end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= RESOURCE then return end
    -- The server cannot observe one client stopping a resource, so tell it
    -- rather than leaving this player counted as standing in a shop forever.
    TriggerServerEvent('qbbusinesses:server:leaveAll')
    for _, business in pairs(live) do Business.destroy(business, true) end
    live = {}
end)

exports('getBusinesses', function() return Client.definitions end)
exports('openBusinessMenu', function() Creator.open() end)
