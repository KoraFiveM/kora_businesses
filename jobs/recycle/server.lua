local Recieve = {
    { item = 'metalscrap', min = 1, max = 5 },
    { item = 'plastic',    min = 1, max = 5 },
    { item = 'copper',     min = 1, max = 5 },
    { item = 'rubber',     min = 1, max = 5 },
    { item = 'iron',       min = 1, max = 5 },
    { item = 'aluminum',   min = 1, max = 5 },
    { item = 'steel',      min = 1, max = 5 },
    { item = 'glass',      min = 1, max = 5 },
}
local luckyItem = 'cryptostick'
local maxRecieved = 5
local LuckyItemChance = 20
local maxSell = 500 -- sanity clamp on a single sell request
local coolDown = Recycle.DeliveryActionDuration or 3000 -- can't claim faster than the hand-in animation takes
local Sales, Stock = {}, {}
local lastCollection = {}
local pendingPackages = {}

if Recycle.SellMaterials then
    Sales = {
        metalscrap = 2,
        plastic = 2,
        copper = 2,
        rubber = 2,
        iron = 2,
        aluminum = 2,
        steel = 2,
        glass = 2,
    }
end

if Recycle.LimitedMaterials then
    Stock = {
        metalscrap = 3000,
        plastic = 3000,
        copper = 3000,
        rubber = 3000,
        iron = 3000,
        aluminum = 3000,
        steel = 3000,
        glass = 3000,
    }
end

Kora.callback.register('kora_businesses:recycle:getPriceList', function(source)
    local src = source
    if not Kora.distance.player(src, Recycle.SellPed, 5.0) then return false end
    return Sales
end)

local function adjustStock(item, change, amount)
    if not Recycle.LimitedMaterials then return end
    if change == 'add' then
        Stock[item] = Stock[item] + amount
    elseif change == 'remove' then
        Stock[item] = Stock[item] - amount
    end
end

local function checkStock(source, item, amount)
    if not Recycle.LimitedMaterials then return true end
    if not Stock[item] then return false end
    return Stock[item] >= amount
end

local function getItem(source, item, amount)
    if Recycle.LimitedMaterials then
        if not checkStock(source, item, amount) then return end
        adjustStock(item, 'remove', amount)
    end
    exports.kora_inventory:addItem(source, item, amount)
end

-- Total owned across every stack of the item (falls back to the first stack if the full list is unavailable).
local function ownedAmount(src, item)
    local ok, stacks = pcall(function() return exports.kora_core:getItemsByName(src, item) end)
    if ok and type(stacks) == 'table' then
        local total = 0
        for _, stack in pairs(stacks) do total = total + (tonumber(stack.amount) or 0) end
        return total
    end
    local has = exports.kora_core:getItemByName(src, item)
    return has and tonumber(has.amount) or 0
end

local function sellMaterials(src, item, amount)
    local owned = ownedAmount(src, item)
    if owned <= 0 then return end
    amount = tonumber(amount)
    if not amount or amount ~= math.floor(amount) or amount <= 0 then return end
    local limit = math.min(owned, Recycle.MaxSellPerRequest or maxSell)
    if amount > limit then
        if Recycle.SellOverAmount == 'reject' then return end
        amount = limit
    end
    local price = Sales[item] * amount
    if not exports.kora_inventory:removeItem(src, item, amount) then return end
    exports.kora_core:addMoney(src, 'cash', price)
    adjustStock(item, 'add', amount)
end

-- Hand-in is accepted at the drop location, the configured hand-in zone or the drop-off ped.
local function nearHandIn(src)
    local distance = Recycle.HandInDistance or 5.0
    local zone = Recycle.HandInZone or {}
    if Kora.distance.player(src, Recycle.DropLocation, distance) then return true end
    if zone.coords and Kora.distance.player(src, zone.coords, distance) then return true end
    return Recycle.HandInAtSellPed ~= false and Kora.distance.player(src, Recycle.SellPed, distance) or false
end

Kora.callback.register('kora_businesses:recycle:pickupPackage', function(src, index)
    if type(index) ~= 'number' or index % 1 ~= 0 then return false end
    local pickup = Recycle.PickupLocations[index]
    if not pickup then return false end
    local pending = pendingPackages[src]
    -- A live authorization means the player already has a box; a stale one (lost client) is replaced.
    if pending and GetGameTimer() - pending < (Recycle.PendingPickupTimeout or 600000) then return false end
    if not Kora.distance.player(src, pickup.loc, 3.0) then return false end
    pendingPackages[src] = GetGameTimer()
    return true
end)

RegisterNetEvent('kora_businesses:recycle:cancelPickup', function()
    pendingPackages[source] = nil
end)

RegisterNetEvent('kora_businesses:recycle:getItem', function()
    local src = source
    local now = GetGameTimer()
    local pickedUpAt = pendingPackages[src]
    if not pickedUpAt or now - pickedUpAt < coolDown then return end
    if lastCollection[src] and (now - lastCollection[src]) < coolDown then return end
    if not nearHandIn(src) then return end
    -- Consume before inventory operations yield so one pickup cannot be redeemed twice.
    pendingPackages[src] = nil
    lastCollection[src] = now

    local itemAmountRecieved = math.random(1, maxRecieved)
    repeat
        Wait(1)
        local item = Recieve[math.random(1, #Recieve)]
        local itemAmount = math.random(item.min, item.max)
        itemAmountRecieved = itemAmountRecieved - 1
        getItem(src, item.item, itemAmount)
    until itemAmountRecieved == 0

    local luckyChance = math.random(1, 100)
    if luckyChance <= LuckyItemChance then
        exports.kora_inventory:addItem(src, luckyItem, 1)
    end
end)

RegisterNetEvent('kora_businesses:recycle:sellItem', function(item, amount)
    local src = source
    if not Recycle.SellMaterials then return end
    if not Sales[item] then return end
    if not Kora.distance.player(src, Recycle.SellPed, 5.0) then return end
    sellMaterials(src, item, amount)
end)

AddEventHandler('playerDropped', function()
    lastCollection[source] = nil
    pendingPackages[source] = nil
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    lastCollection[src] = nil
    pendingPackages[src] = nil
end)
