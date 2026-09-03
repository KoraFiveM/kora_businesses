-- The business registry: the in-memory mirror of the `qbbusinesses` table, the
-- persistence funnel every mutation goes through, and the replication to
-- clients.
--
-- Every write goes through `State.persist`, which validates, writes the row,
-- updates the mirror and broadcasts -- in that order. Nothing else in this
-- resource touches the table directly, so a definition can never be live on a
-- client while the database disagrees.

QbBusinesses = QbBusinesses or {}

local S = QbBusinesses.schema
local State = {}
QbBusinesses.state = State

State.ready = false
---@type table<string, table> id -> normalised business
State.businesses = {}

local RESOURCE = GetCurrentResourceName()

---FNV-1a. Used both to fingerprint a definition for the clients and to stamp
---the migration; one implementation so the two cannot drift.
---@param value string
---@return string
local function checksum(value)
    local hash = 2166136261
    for i = 1, #value do hash = ((hash ~ value:byte(i)) * 16777619) & 0xFFFFFFFF end
    return ('%08x'):format(hash)
end

QbBusinesses.checksum = checksum

---A definition's fingerprint, computed once here rather than by each client.
---Clients rebuild a business only when this changes, so an edit to one business
---does not make every other business in the world flicker. Computing it
---client-side would not work: `json.encode` gives no key-order guarantee, so
---two encodes of the same table can differ.
---@param business table
local function stamp(business)
    business.rev = checksum(json.encode({ business.label, business.job, business.modules }))
    return business
end

local function decode(value, fallback)
    if type(value) ~= 'string' then return fallback end
    local ok, decoded = pcall(json.decode, value)
    return ok and type(decoded) == 'table' and decoded or fallback
end

QbBusinesses.decode = decode

---@param src integer
---@return table|nil
function State.playerJob(src)
    local data = exports.qbcore:getPlayerData(src)
    return data and data.job or nil
end

---@param name string
---@return table|nil
function State.jobDefinition(name)
    if type(name) ~= 'string' or name == '' or name == 'unemployed' then return nil end
    return QB.shared.get('jobs', name)
end

---@param src integer
---@return boolean
function State.isAdmin(src)
    return exports.qbcore:hasPermission(src, Config.adminPermission) == true
end

---True when `src` works this job at all (any grade).
---@param src integer
---@param job string
---@return boolean
function State.worksFor(src, job)
    local active = State.playerJob(src)
    return active ~= nil and active.name == job
end

---True when `src` holds a boss grade for this job.
---@param src integer
---@param job string
---@return boolean
function State.isBoss(src, job)
    local active = State.playerJob(src)
    if not active or active.name ~= job then return false end
    local definition = State.jobDefinition(job)
    local grade = definition and definition.grades and definition.grades[active.grade and active.grade.level]
    return grade ~= nil and grade.isboss == true
end

---@param src integer
---@param business table
---@return boolean
function State.canManage(src, business)
    return State.isAdmin(src) or State.isBoss(src, business.job)
end

---@param id any
---@return table|nil
function State.get(id)
    return type(id) == 'string' and State.businesses[id] or nil
end

---@param business table
---@param index any
---@return table|nil
function State.module(business, index)
    index = tonumber(index)
    if not index or not business then return nil end
    return business.modules[math.floor(index)]
end

---Definitions as they go over the wire. `rejected` is a server-side diagnostic
---and is deliberately not replicated.
---@return table[]
function State.snapshot()
    local list = {}
    for _, business in pairs(State.businesses) do
        list[#list + 1] = {
            id = business.id, label = business.label, job = business.job,
            modules = business.modules, rev = business.rev,
        }
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

---@param target? integer Server id, or nil for everyone.
function State.broadcast(target)
    TriggerClientEvent('qbbusinesses:client:sync', target or -1, State.snapshot())
end

---Validates, writes and publishes one business. The single write path.
---@param raw table
---@return table|nil business, string|nil err
function State.persist(raw)
    local business, err = S.normaliseBusiness(raw)
    if not business then return nil, err end

    local _, writeErr = QB.sql.execute([[INSERT INTO `qbbusinesses` (`id`,`label`,`job`,`modules`) VALUES (?,?,?,?)
        ON DUPLICATE KEY UPDATE `label` = VALUES(`label`), `job` = VALUES(`job`), `modules` = VALUES(`modules`)]], {
        business.id, business.label, business.job, json.encode(business.modules),
    })
    if writeErr then return nil, 'Could not save the business.' end

    State.businesses[stamp(business).id] = business
    QbBusinesses.register.business(business)
    State.broadcast()
    return business
end

---@param id string
---@return boolean ok, string|nil err
function State.remove(id)
    local business = State.get(id)
    if not business then return false, 'Unknown business.' end
    local _, err = QB.sql.execute('DELETE FROM `qbbusinesses` WHERE `id` = ?', { id })
    if err then return false, 'Could not delete the business.' end
    State.businesses[id] = nil
    State.broadcast()
    return true
end

---Loads every row, seeds any configured business that does not exist yet, and
---registers the server-side half of each module.
---@return boolean ok, string|nil err
function State.load()
    local rows, err = QB.sql.query('SELECT `id`, `label`, `job`, `modules` FROM `qbbusinesses`')
    if err then return false, err end

    State.businesses = {}
    for _, row in ipairs(rows or {}) do
        local business, rejectErr = S.normaliseBusiness({
            id = row.id, label = row.label, job = row.job, modules = decode(row.modules, {}),
        })
        if business then
            State.businesses[stamp(business).id] = business
            for _, rejected in ipairs(business.rejected) do
                print(('^3[qbbusinesses]^7 %s module #%d rejected: %s'):format(business.id, rejected.index, rejected.err))
            end
        else
            print(('^1[qbbusinesses]^7 skipped business %s: %s'):format(tostring(row.id), tostring(rejectErr)))
        end
    end

    -- A seed may carry the job it needs. Without this a shipped example lands on
    -- a server whose job list has never heard of it and sits there inert: no
    -- grade means no boss, and the job lock matches nobody.
    --
    -- This runs EVERY boot, unlike the business insert below. qbcore's shared
    -- registries are in-memory and rebuilt from its own seed files each start,
    -- so registering once alongside the first business insert would leave the
    -- job missing on every subsequent boot. The `not jobDefinition` guard is
    -- what keeps it safe to repeat, and it means a server that defines its own
    -- version of the job always wins.
    for _, seed in ipairs(Config.seeds or {}) do
        local job = type(seed.job) == 'string' and seed.job:lower() or nil
        if seed.jobDefinition and job and not State.jobDefinition(job) then
            local ok, err = exports.qbcore:registerShared('jobs', job, seed.jobDefinition)
            if ok then print(('^2[qbbusinesses]^7 registered seed job %s'):format(job))
            else print(('^3[qbbusinesses]^7 could not register seed job %s: %s'):format(job, tostring(err))) end
        end
    end

    -- Seeded businesses themselves are first-boot only. An admin who deleted or
    -- moved a seeded till in-game must not have it silently resurrected on the
    -- next restart, so the guard is on the business id existing at all, not on
    -- its contents.
    for _, seed in ipairs(Config.seeds or {}) do
        local id = S.slug(seed.id or seed.label)
        if id and not State.businesses[id] then
            local seeded, seedErr = State.persist(seed)
            if seeded then print(('^2[qbbusinesses]^7 seeded business %s'):format(seeded.id))
            else print(('^1[qbbusinesses]^7 could not seed %s: %s'):format(tostring(id), tostring(seedErr))) end
        end
    end

    for _, business in pairs(State.businesses) do
        -- An unknown job is not fatal -- the business still exists and can be
        -- reassigned in-game -- but nothing job-locked in it will ever appear,
        -- which is worth saying out loud rather than leaving to be discovered.
        if not State.jobDefinition(business.job) then
            print(('^3[qbbusinesses]^7 %s is assigned to job "%s", which is not registered; its job-locked modules will not appear.')
                :format(business.id, business.job))
        end
        QbBusinesses.register.business(business)
    end
    return true
end
