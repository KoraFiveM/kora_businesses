-- Boot sequence and lifecycle.

QbBusinesses = QbBusinesses or {}

local State = QbBusinesses.state
local Pos = QbBusinesses.pos
local Logs = QbBusinesses.logs

local RESOURCE = GetCurrentResourceName()

-- qbsql compares this against the recorded checksum, so an edited migration is
-- caught instead of silently skipped.
local checksum = QbBusinesses.checksum

CreateThread(function()
    if not QB.sql.ready(60000) then
        return print('^1[qbbusinesses]^7 qbsql was not ready; resource disabled.')
    end

    local sql = assert(LoadResourceFile(RESOURCE, 'sql/001_businesses.sql'), 'missing qbbusinesses migration')
    local _, err = QB.sql.migrate(RESOURCE, { { version = 1, name = 'businesses', sql = sql, checksum = checksum(sql) } })
    if err then return print(('^1[qbbusinesses]^7 migration failed: %s'):format(err)) end

    Pos.loadPrices()

    local ok, loadErr = State.load()
    if not ok then return print(('^1[qbbusinesses]^7 could not load businesses: %s'):format(tostring(loadErr))) end

    State.ready = true

    local count = 0
    for _ in pairs(State.businesses) do count = count + 1 end
    print(('^2[qbbusinesses]^7 %d business(es) live.'):format(count))

    State.broadcast()
end)

---A client that just loaded a character asks for the world it should build.
---This is deliberately a push rather than relying on the join-time broadcast:
---a player who connects mid-restart would otherwise see nothing.
RegisterNetEvent('QBCore:Server:PlayerLoaded', function()
    if State.ready then State.broadcast(source) end
end)

---Log trimming is periodic rather than per-write: a busy till writes several
---rows a minute, and a DELETE after each one would cost more than it saves.
CreateThread(function()
    while true do
        Wait(15 * 60 * 1000)
        if State.ready then
            for id in pairs(State.businesses) do Logs.trim(id) end
        end
    end
end)
