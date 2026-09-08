-- Building and editing businesses at runtime.
--
-- Every mutation is a whole-business write: the caller's change is applied to a
-- COPY of the module list, the copy is validated and persisted as one row, and
-- only then does the in-memory registry move. A rejected edit therefore leaves
-- both the database and the live server exactly as they were.

QbBusinesses = QbBusinesses or {}

local S = QbBusinesses.schema
local State = QbBusinesses.state
local Logs = QbBusinesses.logs
local Staff = QbBusinesses.staff

---@class QBBossMenuBalanceExports
---@field getBusinessBalance fun(self: QBBossMenuBalanceExports, jobName: string): number?, string?

---@param business table
---@return table[] a detached copy of the module list
local function copyModules(business)
    return json.decode(json.encode(business.modules)) or {}
end

---@param src integer
---@param businessId any
---@param requireAdmin boolean
---@return table|nil business, string|nil err
local function authorise(src, businessId, requireAdmin)
    if not State.ready then return nil, 'Businesses are still loading.' end
    local business = State.get(businessId)
    if not business then return nil, 'Unknown business.' end
    if requireAdmin then
        if not State.isAdmin(src) then return nil, 'You cannot edit businesses.' end
    elseif not State.canManage(src, business) then
        return nil, 'You do not manage this business.'
    end
    return business
end

QB.callback.register('qbbusinesses:server:hydrate', function(src)
    return {
        businesses = State.snapshot(),
        staff = Staff.counts(),
        admin = State.isAdmin(src),
        ready = State.ready,
    }
end, { rateLimit = { max = 5, window = 10000 } })

---The job list an admin picks from when creating a business.
QB.callback.register('qbbusinesses:server:jobs', function(src)
    if not State.isAdmin(src) then return nil, 'You cannot edit businesses.' end
    -- `QB.shared.all` returns a dense ARRAY of records, not a name-keyed map --
    -- the key lives on the record as `.name`.
    local jobs = {}
    for _, job in ipairs(QB.shared.all('jobs') or {}) do
        if job.name and job.name ~= 'unemployed' then
            jobs[#jobs + 1] = { value = job.name, label = job.label or job.name }
        end
    end
    table.sort(jobs, function(a, b) return a.label < b.label end)
    return jobs
end, { rateLimit = { max = 5, window = 10000 } })

QB.callback.register('qbbusinesses:server:createBusiness', function(src, payload)
    if not State.ready then return nil, 'Businesses are still loading.' end
    if not State.isAdmin(src) then return nil, 'You cannot create businesses.' end
    if type(payload) ~= 'table' then return nil, 'Invalid business.' end

    local id = S.slug(payload.id or payload.label)
    if not id then return nil, 'That name cannot be used as an id.' end
    if State.get(id) then return nil, 'A business with that id already exists.' end
    if not State.jobDefinition(payload.job) then return nil, 'That job does not exist.' end

    local business, err = State.persist({ id = id, label = payload.label, job = payload.job, modules = {} })
    if not business then return nil, err end

    Logs.record(business, { category = 'admin', src = src, message = ('Created business %s (%s).'):format(business.label, business.job) })
    return business.id
end, { rateLimit = { max = 5, window = 30000 } })

QB.callback.register('qbbusinesses:server:editBusiness', function(src, businessId, payload)
    local business, err = authorise(src, businessId, true)
    if not business then return false, err end
    if type(payload) ~= 'table' then return false, 'Invalid business.' end

    local job = payload.job or business.job
    if not State.jobDefinition(job) then return false, 'That job does not exist.' end

    -- The id is the primary key and is referenced by log rows and till ids, so
    -- a rename changes the label only. Renaming the id is a delete plus a
    -- rebuild, and it should look like one.
    local saved, saveErr = State.persist({
        id = business.id, label = payload.label or business.label, job = job, modules = copyModules(business),
    })
    if not saved then return false, saveErr end

    Logs.record(saved, { category = 'admin', src = src, message = ('Updated business details (%s / %s).'):format(saved.label, saved.job) })
    return true
end, { rateLimit = { max = 10, window = 30000 } })

QB.callback.register('qbbusinesses:server:deleteBusiness', function(src, businessId)
    local business, err = authorise(src, businessId, true)
    if not business then return false, err end

    local ok, removeErr = State.remove(business.id)
    if not ok then return false, removeErr end

    -- Logged against the business that no longer exists on purpose: the row
    -- survives it, and "who deleted this" is exactly what you want afterwards.
    Logs.record(business, { category = 'admin', src = src, message = ('Deleted business %s.'):format(business.label) })
    return true
end, { rateLimit = { max = 5, window = 30000 } })

---Appends a module (`index` nil) or replaces one in place.
QB.callback.register('qbbusinesses:server:saveModule', function(src, businessId, index, payload)
    local business, err = authorise(src, businessId, true)
    if not business then return false, err end

    local module, moduleErr = S.normaliseModule(payload)
    if not module then return false, moduleErr end

    local modules = copyModules(business)
    local position = tonumber(index)
    if position then
        position = math.floor(position)
        if not modules[position] then return false, 'That module no longer exists.' end
        modules[position] = module
    else
        position = #modules + 1
        modules[position] = module
    end

    local saved, saveErr = State.persist({ id = business.id, label = business.label, job = business.job, modules = modules })
    if not saved then return false, saveErr end

    Logs.record(saved, {
        category = 'admin', src = src,
        message = ('%s %s module "%s".'):format(index and 'Updated' or 'Added', module.moduleType, module.label),
    })
    return true, position
end, { rateLimit = { max = 20, window = 30000 } })

QB.callback.register('qbbusinesses:server:removeModule', function(src, businessId, index)
    local business, err = authorise(src, businessId, true)
    if not business then return false, err end

    local modules = copyModules(business)
    local position = math.floor(tonumber(index) or 0)
    local removed = modules[position]
    if not removed then return false, 'That module no longer exists.' end
    table.remove(modules, position)

    local saved, saveErr = State.persist({ id = business.id, label = business.label, job = business.job, modules = modules })
    if not saved then return false, saveErr end

    Logs.record(saved, { category = 'admin', src = src, message = ('Removed %s module "%s".'):format(removed.moduleType, removed.label) })
    return true
end, { rateLimit = { max = 20, window = 30000 } })

QB.callback.register('qbbusinesses:server:logs', function(src, businessId, limit)
    local business, err = authorise(src, businessId, false)
    if not business then return nil, err end
    return Logs.recent(business.id, limit)
end, { rateLimit = { max = 10, window = 10000 } })

QB.callback.register('qbbusinesses:server:balance', function(src, businessId)
    local business, err = authorise(src, businessId, false)
    if not business then return nil, err end
    if GetResourceState('qbbossmenu') ~= 'started' then return nil, 'No business account resource is running.' end
    ---@type QBBossMenuBalanceExports
    local bossMenu = exports.qbbossmenu
    return bossMenu:getBusinessBalance(business.job)
end, { rateLimit = { max = 10, window = 10000 } })

-- ---------------------------------------------------------------------------
-- Exports for other resources
-- ---------------------------------------------------------------------------

exports('getBusinesses', function() return State.snapshot() end)
exports('getBusiness', function(id) local business = State.get(id); return business and json.decode(json.encode(business)) or nil end)

---@param job string
---@return table[] businesses operating under this job
exports('getBusinessesByJob', function(job)
    local list = {}
    for _, business in pairs(State.businesses) do
        if business.job == job then list[#list + 1] = business.id end
    end
    table.sort(list)
    return list
end)

exports('getStaffCounts', function() return Staff.counts() end)
exports('recordBusinessLog', function(businessId, category, message, amount)
    local business = State.get(businessId)
    if not business then return false, 'unknown business' end
    Logs.record(business, {
        category = type(category) == 'string' and category:sub(1, 32) or 'admin',
        message = tostring(message), amount = tonumber(amount),
    })
    return true
end)
