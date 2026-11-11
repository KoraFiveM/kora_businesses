local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'
local depot, pickupOptions, attachment, lookup
local vehicles, lookups, authorized = {}, 0, false
local function noop() end
local env = {}
for name, value in pairs(_G) do env[name] = value end
env.Globals, env.Tow = {}, nil
env.vector3 = function(x, y, z) return { x = x, y = y, z = z } end
env.Kora = {
    interact = { addBoxZone = function(_, _, _, options) depot = options end },
    stream = { loadModel = function() return true end },
    notify = { send = noop },
    callback = { trigger = function(name)
        if name == 'qb-tow:server:TakeOutVehicle' then return { location = 1 } end
        assert(name == 'qb-tow:server:pickUp')
        return authorized
    end },
}
env.exports = { kora_target = { addEntity = function(_, _, options) pickupOptions = options end } }
env.CreateVehicle = function(model)
    local handle = 700 + #vehicles + 1
    vehicles[#vehicles + 1] = { model = model, handle = handle }
    return handle
end
-- Record the lookup arguments without simulating native type conversion or errors.
env.GetEntityBoneIndexByName = function(entity, name)
    lookups = lookups + 1
    lookup = { entity = entity, name = name }
    return 17
end
env.AttachEntityToEntity = function(...) attachment = table.pack(...) end
env.PlayerPedId = function() return 1 end
env.AddBlipForEntity = function() return 900 end
env.RegisterNetEvent, env.SetTimeout = noop, noop
env.CreateThread = function(fn) fn() end
env.Wait = noop
for _, name in ipairs({ 'SetModelAsNoLongerNeeded', 'SetBlipSprite', 'SetBlipDisplay', 'SetBlipScale',
    'SetBlipAsShortRange', 'SetBlipColour', 'BeginTextCommandSetBlipName',
    'AddTextComponentSubstringPlayerName', 'EndTextCommandSetBlipName', 'SetNewWaypoint',
    'SetEntityHeading', 'TaskWarpPedIntoVehicle', 'SetVehicleNumberPlateText', 'SetVehicleFuelLevel',
    'SetVehicleEngineOn' }) do env[name] = noop end
assert(loadfile(root .. 'jobs/tow/shared.lua', 't', env))()
assert(loadfile(root .. 'jobs/tow/client.lua', 't', env))()
depot[1].action()
assert(#vehicles == 2 and vehicles[1].model == env.Tow.Vehicles)
assert(vehicles[2].model == env.Tow.Locations.towspots[1].model)
pickupOptions[1].onSelect()
assert(lookups == 0 and not attachment, 'server denial prevents bone lookup and attachment')
authorized = true
pickupOptions[1].onSelect()
assert(lookups == 1 and lookup.entity == vehicles[1].handle,
    'bone lookup must use the spawned attachment parent, not a model name')
assert(lookup.name == 'bodyshell')
assert(attachment[1] == vehicles[2].handle and attachment[2] == lookup.entity and attachment[3] == 17)
local expected = { 0, -1.5 - 0.85, 1.15, 0, 0, 0, 1, 1, 0, 1, 0, 1 }
assert(attachment.n == #expected + 3)
for index, value in ipairs(expected) do assert(attachment[index + 3] == value, 'attachment offsets and flags unchanged') end
print('tow client: attachment parent lookup and server denial checks passed; native geometry untested')
