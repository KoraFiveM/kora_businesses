-- Legacy qb-mechanicjob:server:SaveVehicleProps. Vehicle owners may persist wear (never healthier than
-- what is stored); whoever just completed a respray/bumper service through the permit flow (server.lua,
-- which checks job, duty, distance and shop zone) may additionally persist that result, and nothing else.
local lastSave, grants = {}, {}

local WEAR = {
    dirtLevel = 'level', oilLevel = 'level', tankHealth = 'health', tireHealth = 'tyreMap',
    tireBurstState = 'tyreFlags', tireBurstCompletely = 'tyreFlags', windowStatus = 'statusMap', doorStatus = 'statusMap',
}
-- Validation rule for the cosmetic keys a service grant can carry.
local COSMETIC = { color1 = 'colour', color2 = 'colour', modFrontBumper = { -1, 200 }, modRearBumper = { -1, 200 } }

local function int(value, min, max)
    if type(value) ~= 'number' or value % 1 ~= 0 or value < min or value > max then return nil end
    return value
end

local function num(value, min, max)
    if type(value) ~= 'number' or value ~= value or value < min or value > max then return nil end
    return value
end

local function rgb(value)
    if type(value) ~= 'table' then return nil end
    local out = {}
    for index, key in ipairs({ 'r', 'g', 'b' }) do
        local channel = int(value[key] or value[index], 0, 255)
        if channel == nil then return nil end
        out[key] = channel
    end
    return out
end

local function keyedMap(value, validate, maxKeys)
    if type(value) ~= 'table' then return nil end
    local out, count = {}, 0
    for key, item in pairs(value) do
        local index = tonumber(key)
        count = count + 1
        if not index or index % 1 ~= 0 or index < 0 or index > 20 or count > maxKeys then return nil end
        local checked = validate(item)
        if checked == nil then return nil end
        out[tostring(index)] = checked
    end
    return out
end

local function boolean(v) if type(v) == 'boolean' then return v end end

local KINDS = {
    colour = function(v) if type(v) == 'table' then return rgb(v) end return int(v, 0, 255) end,
    level = function(v) return num(v, 0, 15) end,
    health = function(v) return num(v, 0, 1000) end,
    tyreMap = function(v) return keyedMap(v, function(x) return num(x, 0, 1000) end, 10) end,
    tyreFlags = function(v) return keyedMap(v, boolean, 10) end,
    statusMap = function(v) return keyedMap(v, boolean, 10) end,
}

local function checkField(rule, value)
    if type(rule) == 'table' then return int(value, rule[1], rule[2]) end
    return KINDS[rule](value)
end

-- `granted` maps the cosmetic keys this caller may persist to the exact value the service produced.
local function sanitizeProps(props, granted)
    if type(props) ~= 'table' then return nil, 'invalid properties' end
    local out, count = {}, 0
    for key, value in pairs(props) do
        count = count + 1
        if type(key) ~= 'string' or count > 160 then return nil, 'invalid properties' end
        if WEAR[key] then
            local checked = checkField(WEAR[key], value)
            if checked == nil then return nil, ('invalid value for %s'):format(key) end
            out[key] = checked
        elseif granted and granted[key] ~= nil then
            local checked = checkField(COSMETIC[key], value)
            if checked ~= nil and checked == granted[key] then out[key] = checked end
        end
    end
    if next(out) == nil then return nil, 'nothing to save' end
    if #json.encode(out) > Mechanic.propsSave.maxBytes then return nil, 'properties too large' end
    return out
end

local function at(map, index)
    if type(map) ~= 'table' then return nil end
    local value = map[index]
    if value == nil then value = map[tonumber(index)] end
    return value
end

-- Worse of (stored, incoming) per entry; an absent stored entry counts as undamaged.
local WORSE = {
    tankHealth = function(new, old) return math.min(new, tonumber(old) or 1000) end,
    tireHealth = function(new, old) return math.min(new, tonumber(old) or 1000) end,
    tireBurstState = function(new, old) return new or old == true end,
    tireBurstCompletely = function(new, old) return new or old == true end,
    windowStatus = function(new, old) return new and old ~= false end, -- true means intact
    doorStatus = function(new, old) return new or old == true end,     -- true means damaged
}

-- Owners must not be able to "repair" tyres, windows, doors or the tank through the database.
local function clampWear(sanitized, stored)
    for key, worse in pairs(WORSE) do
        local value = sanitized[key]
        if value ~= nil then
            if type(value) == 'table' then
                for index, entry in pairs(value) do value[index] = worse(entry, at(stored[key], index)) end
            else
                sanitized[key] = worse(value, stored[key])
            end
        end
    end
end

local function normalisePlate(plate)
    if type(plate) ~= 'string' or #plate > 12 then return nil end
    plate = plate:gsub('^%s+', ''):gsub('%s+$', ''):upper()
    return plate ~= '' and plate or nil
end

local function vehicleNear(src, plate)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local origin, limit = GetEntityCoords(ped), Mechanic.propsSave.distance
    for _, vehicle in ipairs(GetAllVehicles()) do
        if normalisePlate(GetVehicleNumberPlateText(vehicle)) == plate and #(GetEntityCoords(vehicle) - origin) <= limit then
            return vehicle
        end
    end
end

local function isMechanic(src)
    local job = exports.kora_core:getJob(src)
    return job ~= nil and (not Mechanic.roles.requireOnDuty or job.onduty) and Mechanic.roles.roadsideJobs[job.name] ~= true
        and (job.name == Mechanic.roles.fullRepairJob or job.type == Mechanic.roles.automotiveType)
end

local function persistCosmetics()
    local jobs = Config and Config.jobs
    local entry = jobs and jobs.mechanic
    return entry == nil or entry.persistCosmetics ~= false
end

-- Called by server.lua when a respray/bumper service has been paid for and applied: the result of
-- that service (and only that) may then be saved by the same mechanic for a short while.
function Mechanic.grantCosmetics(src, vehicle, action, payload)
    if not persistCosmetics() then return end
    local plate = normalisePlate(GetVehicleNumberPlateText(vehicle))
    if not plate then return end
    local values
    if action == 'paint' then
        values = { color1 = payload.primary, color2 = payload.secondary }
    elseif action == 'bumpers' then
        values = { modFrontBumper = payload.front, modRearBumper = payload.rear }
    else
        return
    end
    local grant = grants[src]
    if not grant or grant.plate ~= plate then
        grant = { plate = plate, values = {} }
        grants[src] = grant
    end
    for key, value in pairs(values) do grant.values[key] = value end
    grant.expires = GetGameTimer() + Mechanic.propsSave.grantLifetime
end

local function grantedFor(src, plate, now)
    local grant = grants[src]
    if not grant then return nil end
    if grant.expires < now then
        grants[src] = nil
        return nil
    end
    return grant.plate == plate and grant.values or nil
end

local function saveProps(src, props)
    if type(src) ~= 'number' or src < 1 or type(props) ~= 'table' then return false end
    local now = GetGameTimer()
    if lastSave[src] and now - lastSave[src] < Mechanic.propsSave.cooldown then return false end
    lastSave[src] = now

    local plate = normalisePlate(props.plate)
    if not plate then return false end
    local citizenid = exports.kora_core:getPlayerData(src, { 'citizenid' })
    if type(citizenid) ~= 'string' then return false end
    local row = exports.kora_core:getByPlate(plate)
    if not row then return false end
    local mechanic = isMechanic(src)
    local granted = persistCosmetics() and grantedFor(src, plate, now) or nil
    if not mechanic and not granted and row.citizenid ~= citizenid then return false end
    local vehicle = vehicleNear(src, plate)
    if not vehicle then return false end

    local sanitized = sanitizeProps(props, granted)
    if not sanitized then return false end

    local stored = type(row.mods) == 'table' and row.mods or {}
    if not mechanic then clampWear(sanitized, stored) end
    local merged = {}
    for key, value in pairs(stored) do merged[key] = value end
    for key, value in pairs(sanitized) do merged[key] = value end
    merged.engineHealth = math.max(0, math.min(1000, GetVehicleEngineHealth(vehicle)))
    merged.bodyHealth = math.max(0, math.min(1000, GetVehicleBodyHealth(vehicle)))
    if exports.kora_core:saveVehicleProperties(row.plate, merged) ~= true then return false end

    if granted then
        local used = false
        for key in pairs(granted) do
            if sanitized[key] ~= nil then granted[key], used = nil, true end
        end
        if used then
            print(('[kora_businesses:mechanic] %d saved serviced cosmetics on %s'):format(src, row.plate))
            if next(granted) == nil then grants[src] = nil end
        end
    end
    return true
end

RegisterNetEvent('qb-mechanicjob:server:SaveVehicleProps', function(props)
    saveProps(source, props)
end)

AddEventHandler('playerDropped', function()
    local src = source
    lastSave[src], grants[src] = nil, nil
end)
