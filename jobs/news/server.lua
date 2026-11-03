-- netId -> { src, entity, location, plate, filled } for every garage vehicle this job has spawned.
local spawnedVehicles = {}
local equipment = { newscam = true, newsmic = true, newsbmic = true }
local cooldownMs = math.max(0, Config.jobs.news.equipmentCooldownSeconds) * 1000
local equipmentCooldown = Kora.timers.cooldown(cooldownMs)
local trunkCooldown = Kora.timers.cooldown(cooldownMs)

local function notify(src, message, kind)
    Kora.notify.send(src, { title = 'Weazel News', message = message, type = kind or 'error' })
end

local function isNews(src)
    return exports.kora_core:getPlayerData(src, { 'job', 'name' }) == News.jobName()
end

local function normalisePlate(plate)
    if type(plate) ~= 'string' then return nil end
    plate = plate:gsub('^%s+', ''):gsub('%s+$', ''):upper()
    return plate ~= '' and plate or nil
end

local function drop(netId)
    spawnedVehicles[netId] = nil
end

local function alive(record)
    return record.entity and DoesEntityExist(record.entity)
end

-- Forget vehicles that were destroyed or deleted elsewhere, so the table never grows without bound.
local function prune()
    for netId, record in pairs(spawnedVehicles) do
        if not alive(record) then drop(netId) end
    end
end

local function activeCount(src)
    local count = 0
    for _, record in pairs(spawnedVehicles) do
        if record.src == src then count = count + 1 end
    end
    return count
end

local function plateInUse(plate)
    for _, record in pairs(spawnedVehicles) do
        if record.plate == plate then return true end
    end
    return false
end

local function newPlate()
    local plate
    repeat plate = 'WZNW' .. math.random(1000, 9999) until not plateInUse(plate)
    return plate
end

local function removeVehicle(netId, record)
    drop(netId)
    if record.plate then exports.kora_vehiclekeys:removeKeys(record.src, record.plate) end
    if alive(record) then DeleteEntity(record.entity) end
end

Kora.callback.register('qb-newsjob:server:spawnVehicle', function(src, location, index)
    if location ~= 'vehicle' and location ~= 'heli' then return false end
    if type(index) ~= 'number' and type(index) ~= 'string' then return false end
    if not isNews(src) then return false end
    local garage = News.Locations[location]
    local vehicle = garage and garage.vehicles and garage.vehicles[index]
    if not vehicle or not Kora.distance.player(src, garage.coords, News.GarageDistance) then return false end

    prune()
    if activeCount(src) >= Config.jobs.news.maxActiveVehicles then
        notify(src, 'You already have a news vehicle out. Store it at the garage first.')
        return false
    end

    -- Model and coordinates come from this resource, never the client's spawn request.
    local coords = garage.coords
    local netId = Kora.entities.createVehicle(vehicle.name,
        { x = coords.x, y = coords.y, z = coords.z, w = coords.w },
        location == 'heli' and 'heli' or 'automobile')
    if not netId or netId == 0 then return false end
    local entity = NetworkGetEntityFromNetworkId(netId)
    SetEntityRoutingBucket(entity, GetPlayerRoutingBucket(src))
    local plate = newPlate()
    SetVehicleNumberPlateText(entity, plate)
    spawnedVehicles[netId] = { src = src, entity = entity, location = location, plate = plate, filled = false }
    return netId, plate
end, { rateLimit = { max = 4, window = 10000 } })

-- Takes the vehicle back: deletes it, drops its keys and frees the player's slot for another one.
Kora.callback.register('qb-newsjob:server:storeVehicle', function(src, netId)
    local record = type(netId) == 'number' and spawnedVehicles[netId]
    if not record or record.src ~= src then return false end
    if not isNews(src) then return false end
    if not alive(record) then
        drop(netId)
        return true
    end
    local garage = News.Locations[record.location]
    if not Kora.distance.player(src, garage.coords, News.StoreDistance)
        or not Kora.distance.entity(src, record.entity, News.StoreDistance) then
        notify(src, 'Bring the vehicle back to the garage to store it.')
        return false
    end
    removeVehicle(netId, record)
    return true
end, { rateLimit = { max = 4, window = 10000 } })

local function removeVehiclesOf(src)
    for netId, record in pairs(spawnedVehicles) do
        if record.src == src then removeVehicle(netId, record) end
    end
end

-- A reporter who leaves does not leave their garage vehicle behind.
AddEventHandler('playerDropped', function()
    local src = source
    removeVehiclesOf(src)
    for item in pairs(equipment) do equipmentCooldown.reset(src .. ':' .. item) end
    trunkCooldown.reset(src)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for netId, record in pairs(spawnedVehicles) do
        if NetworkGetEntityFromNetworkId(netId) == record.entity and alive(record) then
            DeleteEntity(record.entity)
        end
    end
end)

-- Stocks the trunk of a vehicle this player spawned here, once per vehicle and cooldown window.
RegisterNetEvent('qb-newsjob:server:addVehicleItems', function(plate)
    local src = source
    plate = normalisePlate(plate)
    if not plate or not isNews(src) then return end

    local record
    for _, candidate in pairs(spawnedVehicles) do
        if candidate.src == src and candidate.plate == plate and candidate.location == 'vehicle' then record = candidate end
    end
    if not record or record.filled or not alive(record) then return end
    if not Kora.distance.entity(src, record.entity, News.VehicleDistance) then return end
    if not exports['qb-vehiclekeys']:HasKeys(src, plate) then return end
    if not trunkCooldown.use(src) then return end
    record.filled = true

    exports['qb-inventory']:CreateInventory('trunk-' .. plate)

    for slot, item in pairs(News.VehicleItems) do
        exports['qb-inventory']:AddItem('trunk-' .. plate, item.name, item.amount, slot, item.info, 'qb-newsjob:vehicleItems')
    end
end)

RegisterNetEvent('qb-newsjob:server:requestedEquipment', function(item)
    local src = source
    if type(item) ~= 'string' or not equipment[item] or not isNews(src) then return end
    if not Kora.distance.player(src, News.Locations.shop, News.ShopDistance) then return end
    if exports.kora_inventory:getItemCount(src, item) > 0 then
        return notify(src, 'You already have that.', 'info')
    end

    local key = src .. ':' .. item
    if not equipmentCooldown.use(key) then
        return notify(src, ('Wait %d seconds before taking that again.'):format(math.ceil(equipmentCooldown.remaining(key) / 1000)))
    end
    local added = exports['qb-inventory']:AddItem(src, item, 1, nil, nil, 'qb-newsjob:equipment-shop')
    if not added then equipmentCooldown.reset(key) end
end)

local function createNewsUseable(item, clientEvent)
    exports.kora_core:createUseable(item, function(source)
        if not isNews(source) then return end
        TriggerClientEvent(clientEvent, source)
    end)
end

createNewsUseable('newscam', 'Cam:ToggleCam')
createNewsUseable('newsmic', 'Mic:ToggleMic')
createNewsUseable('newsbmic', 'Mic:ToggleBMic')
