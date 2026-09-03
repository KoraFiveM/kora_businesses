-- Client-side shared state and helpers.

QbBusinesses = QbBusinesses or {}

local Client = {}
QbBusinesses.client = Client

---@type table<string, table> businessId -> definition as replicated
Client.definitions = {}
---@type table<string, integer> businessId -> staff currently inside
Client.staff = {}

---@param message string
---@param kind? QBNotifyType
function Client.notify(message, kind)
    QB.notify.send({ title = Config.notifyTitle, message = message, type = kind or 'info' })
end

---@param coords table
---@return vector3
function Client.vec3(coords)
    return vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
end

---@param coords table
---@return vector4
function Client.vec4(coords)
    return vector4(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0, (coords.w or 0.0) + 0.0)
end

---@return table job
function Client.job()
    -- The path is an ARRAY of keys, not a dotted string: qbcore walks it with
    -- `for i = 1, #path`, so a bare string silently resolves to nil.
    local data = exports.qbcore:getPlayerData({ 'job' })
    return type(data) == 'table' and data or {}
end

---@param business table
---@return boolean
function Client.worksFor(business)
    return Client.job().name == business.job
end

---@param business table
---@return boolean
function Client.isBoss(business)
    local job = Client.job()
    if job.name ~= business.job then return false end
    local definition = QB.shared.get('jobs', business.job)
    local grade = definition and definition.grades and definition.grades[job.grade and job.grade.level]
    return grade ~= nil and grade.isboss == true
end

---A module's own anchor point: a zone's centre, or the first entity position.
---@param module table
---@return table|nil
function Client.anchor(module)
    if module.zoneType then return module.coords end
    return module.coords and module.coords[1] or nil
end
