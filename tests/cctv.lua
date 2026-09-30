local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'
local callbacks, api = {}, {}
local job, reads, charges = nil, 0, 0
local function noop() end
local env = setmetatable({
    Globals = {},
    QB = {
        shared = { get = function() return true end },
        callback = { register = function(name, fn) callbacks[name] = fn end },
        sql = { query = function() reads = reads + 1; return {} end },
    },
    exports = setmetatable({
        qbcore = { getJob = function() return job end },
        qbinventory = { CreateUsableItem = noop },
        qbbanking = {
            RemoveMoney = function() charges = charges + 1; return true end,
            AddMoney = function() return true end,
        },
    }, { __call = function(_, name, fn) api[name] = fn end }),
    GetCurrentResourceName = function() return 'qbbusinesses' end,
    AddEventHandler = noop, CreateThread = noop,
}, { __index = _G })
assert(loadfile(root .. 'jobs/cctv/shared.lua', 't', env))()
env.Cctv.minimumEngineerGrade = 2
assert(loadfile(root .. 'jobs/cctv/server.lua', 't', env))()
local callout = { id = 'test', status = 'open', issue = 'camera', business = 'shop', requester = 2, charge = 0 }
api.getCctvCallouts().test = callout
local function reject(candidate)
    job = candidate
    assert(callbacks['qbbusinesses:cctv:laptopData'](1) == nil, 'unauthorized jobs must not receive CCTV data')
    assert(next(callbacks['qbbusinesses:cctv:listCallouts'](1)) == nil)
    assert(callbacks['qbbusinesses:cctv:acceptCallout'](1, 'test') == false)
    assert(callbacks['qbbusinesses:cctv:beginRepairCheck'](1, {}) == false)
    assert(callout.status == 'open' and reads == 0 and charges == 0)
end
reject({ name = 'mechanic', onduty = true, grade = { level = 99 } })
reject(nil)
reject({ name = 'cctv', onduty = false, grade = { level = 2 } })
reject({ name = 'cctv', onduty = true, grade = { level = 1 } })
job = { name = 'cctv', onduty = true, grade = { level = 2 } }
assert(callbacks['qbbusinesses:cctv:laptopData'](1).company == 'cctv' and reads == 1)
assert(callbacks['qbbusinesses:cctv:acceptCallout'](1, 'test') == true and callout.engineer == 1)
job = { name = 'mechanic', onduty = true, grade = { level = 99 } }
assert(callbacks['qbbusinesses:cctv:completeCallout'](1, 'test') == false and charges == 0)
env.Cctv.requireOnDuty = false
job = { name = 'cctv', onduty = false, grade = { level = 2 } }
assert(callbacks['qbbusinesses:cctv:completeCallout'](1, 'test') == true)
assert(callout.status == 'completed' and charges == 1)
print('qbbusinesses CCTV: engineer authorization and billing regression passed')
