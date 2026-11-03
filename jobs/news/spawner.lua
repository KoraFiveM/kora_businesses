function storeCurrentVehicle()
    local veh = GetVehiclePedIsIn(Kora.cache.ped(), false)
    if veh == 0 then return end

    local plate = Kora.vehicle.plate(veh)
    if not CurrentPlate[plate] then return end

    local netId = NetworkGetNetworkIdFromEntity(veh)
    if not netId or netId == 0 then return end
    -- The server deletes the vehicle and its keys once it agrees the player is at the garage.
    if Kora.callback.trigger('qb-newsjob:server:storeVehicle', netId) then
        CurrentPlate[plate] = nil
    end
end

local function spawnReporterVehicle(args)
    if not News.isEmployee() then return end
    local coords = News.Locations[args.location].coords

    local netId, serverPlate = Kora.callback.trigger('qb-newsjob:server:spawnVehicle', args.location, args.index)
    if not netId or netId == 0 then return end
    local veh = Kora.loops.controlled(function()
        local entity = NetToVeh(netId)
        if entity ~= 0 and DoesEntityExist(entity) then return entity end
    end, false, 5000, 25)
    if not veh or not Kora.vehicle.requestControl(veh) then return end

    -- The server picks the plate (it must know it to stock the trunk later); fall back for old servers.
    local plate = serverPlate or ('WZNW' .. math.random(1000, 9999))
    SetVehicleNumberPlateText(veh, plate)
    CurrentPlate[plate] = true
    SetEntityHeading(veh, coords.w)
    exports.kora_fuel:SetFuel(veh, 100.0)
    TaskWarpPedIntoVehicle(Kora.cache.ped(), veh, -1)
    TriggerEvent('vehiclekeys:client:SetOwner', plate)
    SetVehicleEngineOn(veh, true, true, false)
    if args.modLivery then
        local livery = GetVehicleLiveryCount(veh) < 0 and args.modLivery - 1 or args.modLivery
        Kora.vehicle.setProperties(veh, { modLivery = livery })
    end
    if News.VehicleItems and args.location == 'vehicle' then
        TriggerServerEvent('qb-newsjob:server:addVehicleItems', plate)
    end
end

local garageAppId = 'qb-newsjob:garage'
local spawnVehicleAction = 'qb-newsjob:spawn-vehicle'
local vehicleChoices = {}

local function buildGarageNavigation()
    local navigation = {}

    for _, location in ipairs({ 'vehicle', 'heli' }) do
        local garage = News.Locations[location]
        local vehicles = garage and garage.vehicles or {}
        local items = {}

        for index, vehicle in pairs(vehicles) do
            local id = ('%s:%s'):format(location, index)
            vehicleChoices[id] = { index = index, location = location, modLivery = vehicle.modLivery }
            items[#items + 1] = {
                id = id,
                label = vehicle.label,
                action = { id = spawnVehicleAction, label = 'Take vehicle' },
            }
        end

        navigation[#navigation + 1] = {
            id = location,
            label = Kora.lang('news.text.' .. location),
            icon = location == 'vehicle' and 'Car' or 'Helicopter',
            content = {
                title = Kora.lang('news.text.' .. location),
                blocks = #items > 0 and { { type = 'list', id = location, items = items } }
                    or { { type = 'empty', title = 'No vehicles available', icon = 'CircleOff' } },
            },
        }
    end

    return navigation
end

Kora.nui.registerApp({
    id = garageAppId,
    title = 'Weazel News Garage',
    icon = 'Newspaper',
    layout = 'compact',
    navigation = buildGarageNavigation(),
    onAction = function(actionId, context)
        if actionId ~= spawnVehicleAction then return end

        local vehicle = vehicleChoices[context and context.itemId]
        if vehicle then spawnReporterVehicle(vehicle) end
    end,
})

function menuGarage(location)
    if not News.Locations[location] or not News.Locations[location].vehicles then return end
    Kora.nui.openApp(garageAppId, { viewId = location })
end
