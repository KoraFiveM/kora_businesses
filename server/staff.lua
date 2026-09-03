-- Who is standing inside which business, and the automatic duty toggle.
--
-- The client reports entering and leaving its own perimeter, so this is claimed
-- presence, not proof -- it drives a convenience (auto-duty) and a soft policy
-- (a customer cannot self-serve at a staffed till). Both re-check the claimant
-- actually holds the job before acting on it, and nothing here moves money or
-- items, so a forged claim buys nothing beyond hiding a till from other people.

QbBusinesses = QbBusinesses or {}

local State = QbBusinesses.state
local Staff = {}
QbBusinesses.staff = Staff

---@type table<string, table<integer, true>> businessId -> set of sources
local present = {}

---@return table<string, integer>
local function counts()
    local result = {}
    for businessId, sources in pairs(present) do
        local total = 0
        for _ in pairs(sources) do total = total + 1 end
        if total > 0 then result[businessId] = total end
    end
    return result
end

Staff.counts = counts

local function publish()
    TriggerClientEvent('qbbusinesses:client:staff', -1, counts())
end

---@param businessId string
---@return integer
function Staff.countFor(businessId)
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
    if not business or not State.worksFor(src, business.job) then return false end
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
RegisterNetEvent('QBCore:Server:OnPlayerUnload', function() forget(source) end)
---Sent by a client that is stopping this resource: it is still connected, so
---nothing else would ever clear its presence.
RegisterNetEvent('qbbusinesses:server:leaveAll', function() forget(source) end)

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
    if not business or not State.worksFor(src, business.job) then return false, 'You do not work here.' end

    local job = State.playerJob(src)
    if not job or job.onduty == (onDuty == true) then return false end

    local ok, err = exports.qbcore:setJobDuty(src, onDuty == true)
    if not ok then return false, err end
    QB.notify.send(src, {
        title = Config.notifyTitle,
        message = ('You are now %s duty.'):format(onDuty and 'on' or 'off'),
        type = 'info',
    })
    return true
end, { rateLimit = { max = 10, window = 10000 } })
