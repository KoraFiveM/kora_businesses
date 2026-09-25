local callouts = {}
local nextCalloutId = 0
local RESOURCE = GetCurrentResourceName()

if not QB.shared.get('items', Cctv.laptopItem) then
    local registered, err = QB.shared.register('items', Cctv.laptopItem, {
        label = 'CCTV Engineer Laptop',
        weight = 1500,
        type = 'item',
        image = 'laptop.png',
        unique = true,
        useable = true,
        shouldClose = true,
        description = 'Access the CCTV systems installed by your company.',
    })
    if not registered then print(('^1[qbbusinesses]^7 CCTV laptop registration failed: %s'):format(err or 'unknown error')) end
end

exports.qbinventory:CreateUsableItem(Cctv.laptopItem, function(src)
    local job = exports.qbcore:getJob(src)
    local grade = job and job.grade and (job.grade.level or job.grade)
    if not job or job.name ~= Cctv.job or (Cctv.requireOnDuty and not job.onduty)
        or tonumber(grade) < Cctv.minimumEngineerGrade then
        return false, 'You must be an on-duty CCTV engineer to use this laptop.'
    end
    TriggerClientEvent('qbbusinesses:cctv:openLaptop', src)
    return true
end)

CreateThread(function()
    if not QB.sql.ready(60000) then
        print('^1[qbbusinesses]^7 qbsql was not ready; CCTV persistence is disabled.')
        return
    end
    local migrated, err = QB.sql.migrateFiles(RESOURCE, { 'sql/001_cctv_callouts.sql' })
    if not migrated then print(('^1[qbbusinesses]^7 CCTV migration failed: %s'):format(err or 'unknown error')) end
end)

local function amount(value)
    value = tonumber(value)
    if not value or value < 0 or value % 1 ~= 0 or value > 1000000000 then return nil end
    return value
end

local function notify(src, message, kind)
    QB.notify.send(src, { title = 'CCTV', message = message, type = kind or 'error' })
end

local function playerJob(src)
    local job = exports.qbcore:getJob(src)
    if not job then return nil end
    if job.name == Cctv.job and Cctv.requireOnDuty and not job.onduty then return nil end
    local grade = job.grade and (job.grade.level or job.grade)
    if job.name == Cctv.job and tonumber(grade) < Cctv.minimumEngineerGrade then return nil end
    return job
end

local function engineerOnline()
    for _, src in ipairs(exports.qbcore:getPlayersByJob(Cctv.job, Cctv.requireOnDuty)) do
        local job = exports.qbcore:getJob(src)
        local grade = job and job.grade and (job.grade.level or job.grade)
        if job and (not Cctv.requireOnDuty or job.onduty) and tonumber(grade) >= Cctv.minimumEngineerGrade then
            return true
        end
    end
    return false
end

local function customerJob(src, business)
    local job = exports.qbcore:getJob(src)
    if not job or type(business) ~= 'string' or #business > 50 or job.name ~= business then return nil end
    return job
end

local function validIssue(issue)
    return issue == 'camera' or issue == 'nvr'
end

local function repairPrice(issue)
    return issue == 'camera' and amount(Cctv.repair.cameraPrice) or amount(Cctv.repair.nvrPrice)
end

local function calloutFor(src, id)
    local callout = callouts[id]
    if not callout then return nil, 'That CCTV call-out does not exist.' end
    if callout.business ~= (exports.qbcore:getJob(src) or {}).name and not playerJob(src) then
        return nil, 'You are not authorised to manage this call-out.'
    end
    return callout
end

QB.callback.register('qbbusinesses:cctv:requestCallout', function(src, data)
    if not Cctv.callouts.enabled then return false, 'Emergency CCTV call-outs are unavailable.' end
    if type(data) ~= 'table' or not validIssue(data.issue) then return false, 'Choose a valid CCTV issue.' end
    if not customerJob(src, data.business) then return false, 'You are not authorised for that business.' end
    if Cctv.callouts.requireEngineerOnline and not engineerOnline() then
        return false, 'No CCTV engineer is currently available.'
    end

    local charge = amount(Cctv.callouts.charge)
    if not charge then return false, 'The CCTV call-out charge is invalid.' end
    if charge > 0 and not exports.qbbanking:RemoveMoney(data.business, charge, 'cctv-emergency-callout') then
        return false, 'The business cannot afford the call-out charge.'
    end

    nextCalloutId = nextCalloutId + 1
    local id = ('cctv-%d-%d'):format(os.time(), nextCalloutId)
    callouts[id] = {
        id = id,
        business = data.business,
        issue = data.issue,
        cameraId = data.cameraId,
        nvrId = data.nvrId,
        coords = data.coords,
        requester = src,
        charge = charge,
        status = engineerOnline() and 'open' or 'pending',
        engineer = nil,
    }
    return true, callouts[id]
end, { rateLimit = { max = 3, window = 60000 } })

QB.callback.register('qbbusinesses:cctv:listCallouts', function(src)
    if not playerJob(src) then return {} end
    local result = {}
    for _, callout in pairs(callouts) do result[#result + 1] = callout end
    return result
end)

QB.callback.register('qbbusinesses:cctv:laptopData', function(src)
    if not playerJob(src) then return nil, 'You must be an on-duty CCTV engineer.' end
    local result = {}
    for _, callout in pairs(callouts) do result[#result + 1] = callout end
    local systems = {}
    local rows = QB.sql.query('SELECT `id`, `business`, `business_label`, `camera_count`, `status` FROM `qbbusinesses_cctv_systems` WHERE `installer_business` = ?', { Cctv.job })
    for _, system in ipairs(rows or {}) do systems[#systems + 1] = system end
    return { systems = systems, callouts = result, company = Cctv.job }
end)

QB.callback.register('qbbusinesses:cctv:acceptCallout', function(src, id)
    if not playerJob(src) then return false, 'You must be an on-duty CCTV engineer.' end
    local callout = callouts[id]
    if not callout or (callout.status ~= 'open' and callout.status ~= 'pending') then
        return false, 'That call-out is no longer available.'
    end
    callout.status, callout.engineer = 'accepted', src
    return true, callout
end)

QB.callback.register('qbbusinesses:cctv:completeCallout', function(src, id)
    if not playerJob(src) then return false, 'You must be an on-duty CCTV engineer.' end
    local callout = callouts[id]
    if not callout or callout.status ~= 'accepted' or callout.engineer ~= src then
        return false, 'That call-out is not assigned to you.'
    end
    local price = repairPrice(callout.issue)
    if not price then return false, 'The CCTV repair price is invalid.' end
    if price > 0 and not exports.qbbanking:RemoveMoney(callout.business, price, 'cctv-' .. callout.issue .. '-repair') then
        return false, 'The business cannot afford the repair.'
    end
    local paid = callout.charge + price
    if paid > 0 and not exports.qbbanking:AddMoney(Cctv.job, paid, 'cctv-callout-completed') then
        if price > 0 then exports.qbbanking:AddMoney(callout.business, price, 'cctv-repair-refund') end
        return false, 'The CCTV company account could not be credited.'
    end
    callout.status = 'completed'
    callout.repairPrice = price
    return true, callout
end)

QB.callback.register('qbbusinesses:cctv:declineCallout', function(src, id)
    if not playerJob(src) then return false, 'You must be an on-duty CCTV engineer.' end
    local callout = callouts[id]
    if not callout or callout.status ~= 'accepted' or callout.engineer ~= src then
        return false, 'That call-out is not assigned to you.'
    end
    callout.status, callout.engineer = 'open', nil
    return true, callout
end)

exports('getCctvCallouts', function()
    return callouts
end)
