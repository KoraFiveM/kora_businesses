local sharedItems = exports['qb-core']:GetShared('Items')
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
local luckyItem = 'cryptostick' -- Item to be given as a lucky item
local maxRecieved = 5           -- Max items to be received
local LuckyItemChance = 20      -- 20% chance to get a lucky item
local maxSell = 500 -- sanity clamp on a single sell request
local coolDown = Recycle.DeliveryActionDuration or 3000 -- can't claim faster than the hand-in animation takes
local Sales, Stock = {}, {}
local lastCollection = {}

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

QB.callback.register('qb-recyclejob:server:getPriceList', function(source)
    local src = source
    if not QB.distance.player(src, Recycle.SellPed, 5.0) then return false end
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
    if Stock[item] >= amount then
        return true
    else
        return false
    end
end

local function getItem(source, item, amount)
    if Recycle.LimitedMaterials then
        if not checkStock(source, item, amount) then return end
        adjustStock(item, 'remove', amount)
    end
    exports.qbinventory:addItem(source, item, amount)
end

local function sellMaterials(src, item, amount)
    local Player = exports['qb-core']:GetPlayer(src)
    if not Player then return end
    local has = Player.GetItemByName(item)
    if not has or has.amount <= 0 then return end
    amount = tonumber(amount)
    if not amount or amount ~= math.floor(amount) or amount <= 0 then return end
    amount = math.min(amount, has.amount, maxSell)
    local price = Sales[item] * amount
    if exports['qb-inventory']:RemoveItem(src, item, amount) then
        Player.Functions.AddMoney('cash', price)
        adjustStock(item, 'add', amount)
    end
end

RegisterNetEvent('qb-recyclejob:server:getItem', function()
    local src = source
    local now = GetGameTimer()
    if lastCollection[src] and (now - lastCollection[src]) < coolDown then
        return
    end
    if not QB.distance.player(src, Recycle.DropLocation, 5.0) then return end
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
        exports.qbinventory:addItem(src, luckyItem, 1)
    end
end)

RegisterNetEvent('qb-recyclejob:server:sellItem', function(item, amount)
    local src = source
    if not Recycle.SellMaterials then return end
    if not Sales[item] then return end
    if not QB.distance.player(src, Recycle.SellPed, 5.0) then return end
    sellMaterials(src, item, amount)
end)

AddEventHandler('playerDropped', function()
    lastCollection[source] = nil
end)