KoraBusinessesCctvSchema = {
    {
        name = 'kora_businesses_cctv_callouts',
        columns = {
            { name = 'id', type = 'varchar(40)' },
            { name = 'business', type = 'varchar(50)', null = true, default = Kora.sql.NULL, modify = true },
            { name = 'customer_type', type = 'varchar(20)', default = 'business' },
            { name = 'citizenid', type = 'varchar(50)', null = true, default = Kora.sql.NULL },
            { name = 'issue', type = 'enum', values = { 'camera', 'nvr' } },
            { name = 'camera_id', type = 'varchar(80)', null = true, default = Kora.sql.NULL },
            { name = 'nvr_id', type = 'varchar(80)', null = true, default = Kora.sql.NULL },
            { name = 'requester', type = 'int' },
            { name = 'engineer', type = 'int', null = true, default = Kora.sql.NULL },
            { name = 'charge', type = 'int', default = 0 },
            { name = 'repair_price', type = 'int', null = true, default = Kora.sql.NULL },
            { name = 'status', type = 'varchar(20)' },
            { name = 'coords', type = 'text', null = true, default = Kora.sql.NULL },
            { name = 'created_at', type = 'timestamp', default = { raw = 'CURRENT_TIMESTAMP' } },
            { name = 'completed_at', type = 'timestamp', null = true, default = Kora.sql.NULL },
        },
        primary = { 'id' },
        indexes = {
            { name = 'kora_businesses_cctv_callouts_business', columns = { 'business' } },
            { name = 'kora_businesses_cctv_callouts_status', columns = { 'status' } },
        },
    },
    {
        name = 'kora_businesses_cctv_systems',
        columns = {
            { name = 'id', type = 'varchar(80)' },
            { name = 'installer_business', type = 'varchar(50)' },
            { name = 'business', type = 'varchar(50)' },
            { name = 'business_label', type = 'varchar(100)', null = true, default = Kora.sql.NULL },
            { name = 'camera_count', type = 'int', default = 0 },
            { name = 'status', type = 'varchar(20)', default = 'online' },
            { name = 'security_level', type = 'int', default = 1 },
            { name = 'intrusion_level', type = 'int', default = 0 },
            { name = 'created_at', type = 'timestamp', default = { raw = 'CURRENT_TIMESTAMP' } },
        },
        primary = { 'id' },
        indexes = {
            { name = 'kora_businesses_cctv_systems_installer', columns = { 'installer_business' } },
        },
    },
}

local callouts = {}
local nextCalloutId = 0
local hackSessions = {}
local repairSessions = {}

local function setBucket(src, bucket)
    SetPlayerRoutingBucket(src, bucket)
    TriggerEvent('kora_voice:server:bucketChanged', src)
end

if not Kora.shared.get('items', Cctv.laptopItem) then
    local registered, err = Kora.shared.register('items', Cctv.laptopItem, {
        label = 'CCTV Engineer Laptop',
        weight = 1500,
        type = 'item',
        image = 'laptop.png',
        unique = true,
        useable = true,
        shouldClose = true,
        description = 'Access the CCTV systems installed by your company.',
    })
    if not registered then print(('^1[kora_businesses]^7 CCTV laptop registration failed: %s'):format(err or 'unknown error')) end
end

local function playerJob(src)
    local job = exports.kora_core:getJob(src)
    if not job or job.name ~= Cctv.job then return nil end
    if Cctv.requireOnDuty and not job.onduty then return nil end
    local grade = job.grade and (job.grade.level or job.grade)
    if tonumber(grade) < Cctv.minimumEngineerGrade then return nil end
    return job
end

exports.kora_inventory:CreateUsableItem(Cctv.laptopItem, function(src)
    if not playerJob(src) then
        return false, 'You must be an on-duty CCTV engineer to use this laptop.'
    end
    TriggerClientEvent('kora_businesses:cctv:openLaptop', src)
    return true
end)

CreateThread(function()
    if not Kora.sql.ready(60000) then
        print('^1[kora_businesses]^7 kora_sql was not ready; CCTV persistence is disabled.')
        return
    end
    local reports, err = Kora.sql.ensureTables(KoraBusinessesCctvSchema)
    if err then
        print(('^1[kora_businesses]^7 CCTV schema failed: %s'):format(err))
        return
    end
    for _, report in ipairs(reports or {}) do
        for _, warning in ipairs(report.warnings or {}) do
            print(('^3[kora_businesses]^7 CCTV schema %s: %s'):format(report.table, warning))
        end
    end
end)

local function amount(value)
    value = tonumber(value)
    if not value or value < 0 or value % 1 ~= 0 or value > 1000000000 then return nil end
    return value
end

local function notify(src, message, kind)
    Kora.notify.send(src, { title = 'CCTV', message = message, type = kind or 'error' })
end

local function engineerOnline()
    for _, src in ipairs(exports.kora_core:getPlayersByJob(Cctv.job, Cctv.requireOnDuty)) do
        local job = exports.kora_core:getJob(src)
        local grade = job and job.grade and (job.grade.level or job.grade)
        if job and (not Cctv.requireOnDuty or job.onduty) and tonumber(grade) >= Cctv.minimumEngineerGrade then
            return true
        end
    end
    return false
end

local function customerJob(src, business)
    local job = exports.kora_core:getJob(src)
    if not job or type(business) ~= 'string' or #business > 50 or job.name ~= business then return nil end
    return job
end

local function customer(src, data)
    if type(data) ~= 'table' then return nil, 'Invalid customer data.' end
    if data.customerType == 'residential' then
        local player = exports.kora_core:getPlayer(src)
        if not player or type(data.citizenid) ~= 'string' or data.citizenid ~= player.citizenid then
            return nil, 'You are not authorised for that home.'
        end
        return { type = 'residential', citizenid = player.citizenid }
    end
    if data.customerType ~= 'business' or not customerJob(src, data.business) then
        return nil, 'You are not authorised for that business.'
    end
    return { type = 'business', business = data.business }
end

local function debitCustomer(src, account, value, reason)
    if value <= 0 then return true end
    if account.type == 'residential' then
        return exports.kora_core:removeMoney(src, 'bank', value, reason)
    end
    return exports.kora_banking:RemoveMoney(account.business, value, reason)
end

local function refundCustomer(src, account, value, reason)
    if value <= 0 then return true end
    if account.type == 'residential' then
        return exports.kora_core:addMoney(src, 'bank', value, reason)
    end
    return exports.kora_banking:AddMoney(account.business, value, reason)
end

local function accountKey(account)
    return account.type == 'residential' and account.citizenid or account.business
end

local function systemSecurity(targetId)
    local row = Kora.sql.single('SELECT `security_level`, `intrusion_level` FROM `kora_businesses_cctv_systems` WHERE `id` = ?', { targetId })
    if not row then return 1 end
    return math.max(1, math.min(10, (tonumber(row.security_level) or 1) + (tonumber(row.intrusion_level) or 0)))
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
    if callout.business ~= (exports.kora_core:getJob(src) or {}).name and not playerJob(src) then
        return nil, 'You are not authorised to manage this call-out.'
    end
    return callout
end

Kora.callback.register('kora_businesses:cctv:requestCallout', function(src, data)
    if not Cctv.callouts.enabled then return false, 'Emergency CCTV call-outs are unavailable.' end
    if type(data) ~= 'table' or not validIssue(data.issue) then return false, 'Choose a valid CCTV issue.' end
    local account, customerError = customer(src, data)
    if not account then return false, customerError end
    if Cctv.callouts.requireEngineerOnline and not engineerOnline() then
        return false, 'No CCTV engineer is currently available.'
    end

    local charge = amount(Cctv.callouts.charge)
    if not charge then return false, 'The CCTV call-out charge is invalid.' end
    if charge > 0 and not debitCustomer(src, account, charge, 'cctv-emergency-callout') then
        return false, 'The business cannot afford the call-out charge.'
    end

    nextCalloutId = nextCalloutId + 1
    local id = ('cctv-%d-%d'):format(os.time(), nextCalloutId)
    callouts[id] = {
        id = id,
        customerType = account.type,
        business = account.business,
        citizenid = account.citizenid,
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

Kora.callback.register('kora_businesses:cctv:listCallouts', function(src)
    if not playerJob(src) then return {} end
    local result = {}
    for _, callout in pairs(callouts) do result[#result + 1] = callout end
    return result
end)

Kora.callback.register('kora_businesses:cctv:laptopData', function(src)
    if not playerJob(src) then return nil, 'You must be an on-duty CCTV engineer.' end
    local result = {}
    for _, callout in pairs(callouts) do result[#result + 1] = callout end
    local systems = Kora.sql.query('SELECT `id`, `business`, `business_label`, `camera_count`, `status` FROM `kora_businesses_cctv_systems` WHERE `installer_business` = ?', { Cctv.job }) or {}
    return { systems = systems, callouts = result, company = Cctv.job }
end)

Kora.callback.register('kora_businesses:cctv:acceptCallout', function(src, id)
    if not playerJob(src) then return false, 'You must be an on-duty CCTV engineer.' end
    local callout = callouts[id]
    if not callout or (callout.status ~= 'open' and callout.status ~= 'pending') then
        return false, 'That call-out is no longer available.'
    end
    callout.status, callout.engineer = 'accepted', src
    return true, callout
end)

Kora.callback.register('kora_businesses:cctv:completeCallout', function(src, id)
    if not playerJob(src) then return false, 'You must be an on-duty CCTV engineer.' end
    local callout = callouts[id]
    if not callout or callout.status ~= 'accepted' or callout.engineer ~= src then
        return false, 'That call-out is not assigned to you.'
    end
    local price = repairPrice(callout.issue)
    if not price then return false, 'The CCTV repair price is invalid.' end
    local account = { type = callout.customerType, business = callout.business, citizenid = callout.citizenid }
    local payer = callout.requester
    if price > 0 and not debitCustomer(payer, account, price, 'cctv-' .. callout.issue .. '-repair') then
        return false, 'The business cannot afford the repair.'
    end
    local paid = callout.charge + price
    if paid > 0 and not exports.kora_banking:AddMoney(Cctv.job, paid, 'cctv-callout-completed') then
        if price > 0 then refundCustomer(payer, account, price, 'cctv-repair-refund') end
        return false, 'The CCTV company account could not be credited.'
    end
    callout.status = 'completed'
    callout.repairPrice = price
    return true, callout
end)

Kora.callback.register('kora_businesses:cctv:beginHack', function(src, data)
    if not Cctv.hacking.enabled then return false, 'CCTV hacking is disabled.' end
    if type(data) ~= 'table' or type(data.targetId) ~= 'string' or #data.targetId > 80 then
        return false, 'Invalid CCTV target.'
    end
    if hackSessions[src] then return false, 'You are already hacking a CCTV system.' end
    local level = systemSecurity(data.targetId)
    local options = {}
    for key, value in pairs(Cctv.hacking.options) do options[key] = value end
    options.solutionsize = (options.solutionsize or 4) + math.max(0, level - 1)
    local authorised = Kora.minigames.authorizeSkillCheck(src, Cctv.hacking.skill, Cctv.hacking.game, options)
    local previousBucket = GetPlayerRoutingBucket(src)
    local bucket = Cctv.hacking.privateBucketBase + src
    setBucket(src, bucket)
    hackSessions[src] = {
        authorization = authorised,
        targetId = data.targetId,
        previousBucket = previousBucket,
        expires = GetGameTimer() + Cctv.hacking.duration,
    }
    return true, { authorization = authorised, bucket = bucket }
end)

Kora.callback.register('kora_businesses:cctv:finishHack', function(src, data)
    local session = hackSessions[src]
    hackSessions[src] = nil
    if not session or session.expires < GetGameTimer() then
        if session then setBucket(src, session.previousBucket) end
        return false, 'That hacking session expired.'
    end
    setBucket(src, session.previousBucket)
    local proof = type(data) == 'table' and data.proof or nil
    if type(proof) ~= 'string' or not Kora.minigames.consumeProof(src, proof, Cctv.hacking.game, session.authorization) then
        return false, 'The CCTV hack failed.'
    end
    local hacking = Kora.skills.get(src, Cctv.hacking.skill)
    local intrusion = hacking and math.max(1, math.floor((tonumber(hacking.level) or 1) / 10)) or 1
    Kora.sql.update('UPDATE `kora_businesses_cctv_systems` SET `intrusion_level` = LEAST(10, ?) WHERE `id` = ?', { intrusion, session.targetId })
    return true, { targetId = session.targetId }
end)

Kora.callback.register('kora_businesses:cctv:beginRepairCheck', function(src, data)
    if not playerJob(src) then return false, 'You must be an on-duty CCTV engineer.' end
    if not Cctv.repairChecks.enabled or type(data) ~= 'table' then return false, 'Repair checks are unavailable.' end
    local level = systemSecurity(data.targetId)
    if repairSessions[src] then return false, 'You are already repairing a CCTV system.' end
    local options = {
        nodeCount = Cctv.repairChecks.baseNodes + (level - 1) * Cctv.repairChecks.nodesPerSecurityLevel,
        timeLimit = 30000,
    }
    local authorization = Kora.minigames.authorizeSkillCheck(src, Cctv.repairChecks.skill, Cctv.repairChecks.game, options)
    repairSessions[src] = { authorization = authorization, targetId = data.targetId, expires = GetGameTimer() + Cctv.repairChecks.duration }
    return true, { authorization = authorization }
end)

Kora.callback.register('kora_businesses:cctv:finishRepairCheck', function(src, data)
    local session = repairSessions[src]
    repairSessions[src] = nil
    if not session or session.expires < GetGameTimer() then return false, 'That repair check expired.' end
    local proof = type(data) == 'table' and data.proof or nil
    if type(proof) ~= 'string' or not Kora.minigames.consumeProof(src, proof, Cctv.repairChecks.game, session.authorization) then
        return false, 'The repair check failed.'
    end
    return true, { targetId = session.targetId }
end)

AddEventHandler('playerDropped', function()
    local src = source
    local session = hackSessions[src]
    hackSessions[src] = nil
    if session then setBucket(src, session.previousBucket) end
    repairSessions[src] = nil
end)

CreateThread(function()
    while true do
        Wait(10000)
        local now = GetGameTimer()
        for src, session in pairs(hackSessions) do
            if session.expires < now then
                setBucket(src, session.previousBucket)
                hackSessions[src] = nil
                notify(src, 'Your CCTV hacking session expired.', 'error')
            end
        end
        for src, session in pairs(repairSessions) do
            if session.expires < now then repairSessions[src] = nil end
        end
    end
end)

Kora.callback.register('kora_businesses:cctv:declineCallout', function(src, id)
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

-- /cctvhack and /cctvrepair are client commands, and the client cannot publish chat suggestions
-- reliably at load (the chat UI is not ready). Publish from the server when the chat UI reports in.
local function suggestCommands(src)
    if not src or src <= 0 then return end
    TriggerClientEvent('chat:addSuggestion', src, '/cctvhack', 'Hack a CCTV system', { { name = 'targetId', help = 'CCTV system ID' } })
    TriggerClientEvent('chat:addSuggestion', src, '/cctvrepair', 'Run a CCTV repair check', { { name = 'targetId', help = 'CCTV system ID' } })
end

AddEventHandler('chat:init', function()
    suggestCommands(source)
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, playerId in ipairs(GetPlayers()) do suggestCommands(tonumber(playerId)) end
end)
