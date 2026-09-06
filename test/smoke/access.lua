-- Runtime coverage for the shared employee/presence boundary. The server files
-- are otherwise FXServer-loaded, so this supplies only the natives they need.
local H = dofile('test/harness.lua')

local players = {
    [1] = { job = { name = 'burgershot', onduty = true }, coords = { x = 9, y = 0, z = 0 } },
    [2] = { job = { name = 'burgershot', onduty = false }, coords = { x = 0, y = 0, z = 0 } },
    [3] = { job = { name = 'police', onduty = true }, coords = { x = 0, y = 0, z = 0 } },
}

QbBusinesses = { schema = {} }
Config = { duty = { enabled = true } }
GetCurrentResourceName = function() return 'qbbusinesses' end
GetPlayerPed = function(src) return players[src] and src or 0 end
exports = {
    qbcore = {
        getPlayerData = function(_, src) return players[src] end,
        setJobDuty = function(_, src, value) players[src].job.onduty = value; return true end,
    },
}
QB = {
    distance = {
        player = function(src, point, distance)
            local p = players[src].coords
            local x, y, z = p.x - point.x, p.y - point.y, p.z - point.z
            return math.sqrt(x * x + y * y + z * z) <= distance
        end,
    },
    callback = { register = function() end },
    notify = { send = function() end },
}
json = { encode = function() return '' end, decode = function() return {} end }

dofile('server/state.lua')
local State = QbBusinesses.state
local business = {
    id = 'burgershot', job = 'burgershot', modules = {
        { moduleType = 'Zone', controlDuty = true, zoneType = 'sphere', coords = { x = 0, y = 0, z = 0 }, radius = 10, distance = 2 },
    },
}
State.businesses[business.id] = business

H.ok(State.employeeAt(1, business, nil, true), 'on-duty staff near the perimeter edge are accepted')
H.rejects(State.employeeAt(2, business, nil, true), 'off-duty staff are rejected')
H.rejects(State.employeeAt(3, business, nil, true), 'another job is rejected')
players[1].coords.x = 50
H.rejects(State.employeeAt(1, business, nil, true), 'server position rejects a remote claim')
players[1].coords.x = 9

local handlers = {}
AddEventHandler = function(name, callback) handlers[name] = callback end
RegisterNetEvent = function(name, callback) handlers[name] = callback end
TriggerClientEvent = function() end
CreateThread = function() end -- do not execute the production periodic loop here
Wait = function() end

dofile('server/staff.lua')
local Staff = QbBusinesses.staff
H.ok(Staff.enter(1, business.id), 'validated on-duty staff can enter presence')
H.equal(Staff.countFor(business.id), 1, 'validated presence is counted')
players[1].job.onduty = false
H.equal(Staff.countFor(business.id), 0, 'a stale off-duty presence is pruned on read')

players[1].job.onduty = true
H.ok(Staff.enter(1, business.id), 'staff can re-enter after returning to duty')
handlers['QBCore:Server:OnPlayerUnload'](1)
H.equal(Staff.countFor(business.id), 0, 'character unload clears the explicit source')

H.finish('access')
