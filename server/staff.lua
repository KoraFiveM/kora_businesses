-- Who is standing inside which business, and the automatic duty toggle.
--
-- The client reports which perimeter transition happened, but the server proves
-- the current job, duty state and live ped proximity before presence is accepted
-- or counted. Cached claims are pruned as those facts change.

QbBusinesses = QbBusinesses or {}

local State = QbBusinesses.state
local Staff = {}
QbBusinesses.staff = Staff

---@type table<string, table<integer, true>> businessId -> set of sources
local present = {}

local function rawCounts()
    local result = {}
    for businessId, sources in pairs(present) do
        local total = 0
        for _ in pairs(sources) do total = total + 1 end
        if total > 0 then result[businessId] = total end
    end
    return result
end

local function publish()
    TriggerClientEvent('qbbusinesses:client:staff', -1, rawCounts())
end

---@param onlySource? integer
---@param onlyBusiness? string
---@return boolean changed
local function prune(onlySource, onlyBusiness)
    local changed = false
    for businessId, sources in pairs(present) do
        if not onlyBusiness or businessId == onlyBusiness then
            local business = State.get(businessId)
            for src in pairs(sources) do
                if (not onlySource or src == onlySource)
                    and (not business or not State.employeeAt(src, business, nil, true)) then
                    sources[src] = nil
                    changed = true
                end
            end
            if not next(sources) then present[businessId] = nil end
        end
    end
    return changed
end

---@return table<string, integer>
local function counts()
    if prune() then publish() end
    return rawCounts()
end

Staff.counts = counts
Staff.prune = prune

---@param businessId string
---@return integer
function Staff.countFor(businessId)
    if prune(nil, businessId) then publish() end
    local sources = present[businessId]
    if not sources then return 0 end
    local total = 0
    for _ in pairs(sources) do total = total + 1 end
    return total
end

---@param src integer
---@param businessId any
function Staff.enter(src, businessId)
    local business = State.get(businessId)
    if not business then return false end
    local allowed = State.employeeAt(src, business, nil, true)
    if not allowed then return false end
    present[business.id] = present[business.id] or {}
    if present[business.id][src] then return true end
    present[business.id][src] = true
    publish()
    return true
end

---@param src integer
---@param businessId any
function Staff.leave(src, businessId)
    local sources = type(businessId) == 'string' and present[businessId] or nil
    if not sources or not sources[src] then return false end
    sources[src] = nil
    if not next(sources) then present[businessId] = nil end
    publish()
    return true
end

---@param src integer
local function forget(src)
    local changed = false
    for businessId, sources in pairs(present) do
        if sources[src] then
            sources[src] = nil
            if not next(sources) then present[businessId] = nil end
            changed = true
        end
    end
    if changed then publish() end
end

AddEventHandler('playerDropped', function() forget(source) end)
AddEventHandler('QBCore:Server:OnPlayerUnload', function(src) forget(src) end)
AddEventHandler('QBCore:Server:OnJobUpdate', function(src)
    if prune(src) then publish() end
end)
AddEventHandler('QBCore:Server:SetDuty', function(src, onDuty)
    if onDuty ~= true then forget(src)
    elseif prune(src) then publish() end
end)
---Sent by a client that is stopping this resource: it is still connected, so
---nothing else would ever clear its presence.
RegisterNetEvent('qbbusinesses:server:leaveAll', function() forget(source) end)

-- A forged client never gets counted in the first place, and this sweep closes
-- stale position/lifecycle windows even if its matching leave event never came.
CreateThread(function()
    while true do
        Wait(5000)
        if prune() then publish() end
    end
end)

QB.callback.register('qbbusinesses:server:enter', function(src, businessId)
    return Staff.enter(src, businessId)
end, { rateLimit = { max = 20, window = 10000 } })

QB.callback.register('qbbusinesses:server:leave', function(src, businessId)
    return Staff.leave(src, businessId)
end, { rateLimit = { max = 20, window = 10000 } })

---Auto duty. The client decides WHEN (it owns the perimeter), the server
---decides WHETHER: it re-reads the caller's real job rather than trusting the
---business id to imply one.
QB.callback.register('qbbusinesses:server:setDuty', function(src, businessId, onDuty)
    if not Config.duty.enabled then return false, 'Automatic duty is disabled.' end
    local business = State.get(businessId)
    if not business then return false, 'Unknown business.' end
    local dutyZone
    for _, module in ipairs(business.modules or {}) do
        if module.moduleType == 'Zone' and module.controlDuty ~= false and State.nearModule(src, module) then
            dutyZone = module
            break
        end
    end
    if not dutyZone then return false, 'Automatic duty is not available here.' end
    local allowed, accessErr = State.employeeAt(src, business, dutyZone)
    if not allowed then return false, accessErr end

    local job = State.playerJob(src)
    if not job or job.onduty == (onDuty == true) then return false end

    local ok, err = exports.qbcore:setJobDuty(src, onDuty == true)
    if not ok then return false, err end
    if onDuty ~= true then forget(src) end
    QB.notify.send(src, {
        title = Config.notifyTitle,
        message = ('You are now %s duty.'):format(onDuty and 'on' or 'off'),
        type = 'info',
    })
    return true
end, { rateLimit = { max = 10, window = 10000 } })
