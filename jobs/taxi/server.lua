local currentTaxis = {}

local function taxiPlayer(source)
    local player = exports.qbcore:getPlayer(source)
    if not player or not player.PlayerData.job or player.PlayerData.job.name ~= Taxi.jobRequired then
        return nil
    end
    return player
end



QB.callback.register('qb-taxi:getPickupLocation', function(source)
    if not taxiPlayer(source) then return nil end
    if not currentTaxis[source] then
        currentTaxis[source] = {}
    end
    local pickup, dropoff = Taxi.PickUp[math.random(1, #Taxi.PickUp)], Taxi.DropOffs[math.random(1, #Taxi.DropOffs)]
    currentTaxis[source].pickup = pickup
    currentTaxis[source].dropoff = dropoff
    currentTaxis[source].distance = QB.util.vecDistance(pickup, dropoff)
    return {pickup = pickup, dropoff = dropoff}
end)

RegisterNetEvent('qb-taxi:pickup', function()
    if not taxiPlayer(source) then return end
    assert(currentTaxis[source], "No current taxi found for this source")
    assert(QB.distance.player(source, currentTaxis[source].pickup, 5.0), "Player is too far from the pickup location")
    currentTaxis[source].pickupComplete = true
end)
RegisterNetEvent('qb-taxi:dropOff', function()
    if not taxiPlayer(source) then return end
    assert(currentTaxis[source], "No current taxi found for this source")
    assert(QB.distance.player(source, currentTaxis[source].dropoff, 5.0), "Player is too far from the dropoff location")
    assert(currentTaxis[source].pickupComplete, "Pickup has not been completed yet")
    local pay = math.floor(currentTaxis[source].distance * 0.2)
    exports.qbcore:addMoney(source, 'cash', pay)
    currentTaxis[source] = nil
    TriggerClientEvent('qb-taxi:client:spawnPickup', source)
end)

AddEventHandler('playerDropped', function()
    currentTaxis[source] = nil
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(source)
    currentTaxis[source] = nil
end)
