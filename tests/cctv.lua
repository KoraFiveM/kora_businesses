local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'
local callbacks, api = {}, {}
local job, reads, charges = nil, 0, 0
local function noop() end
local handlers, threads, buckets, notices, clock = {}, {}, { [1] = 42 }, {}, 0
local env = setmetatable({
    Globals = {},
    Kora = {
        shared = { get = function() return true end },
        callback = { register = function(name, fn) callbacks[name] = fn end },
        sql = { NULL = {}, query = function() reads = reads + 1; return {} end },
    },
    exports = setmetatable({
        kora_core = { getJob = function() return job end },
        kora_inventory = { CreateUsableItem = noop },
        kora_banking = {
            RemoveMoney = function() charges = charges + 1; return true end,
            AddMoney = function() return true end,
        },
    }, { __call = function(_, name, fn) api[name] = fn end }),
    GetCurrentResourceName = function() return 'kora_businesses' end,
    AddEventHandler = function(name, fn) handlers[name] = fn end,
    CreateThread = function(fn) threads[#threads + 1] = coroutine.create(fn) end,
    Wait = function() coroutine.yield() end,
    GetGameTimer = function() return clock end,
    GetPlayerRoutingBucket = function(src) return buckets[src] end,
    SetPlayerRoutingBucket = function(src, bucket) buckets[src] = bucket end,
    TriggerEvent = function(name, src)
        if name == 'qbvoice:server:bucketChanged' then notices[#notices + 1] = { src = src, bucket = buckets[src] } end
    end,
}, { __index = _G })
assert(loadfile(root .. 'jobs/cctv/shared.lua', 't', env))()
env.Cctv.minimumEngineerGrade = 2
assert(loadfile(root .. 'jobs/cctv/server.lua', 't', env))()
env.Kora.sql.ready = function() return true end
local ensured
env.Kora.sql.ensureTables = function(specs)
    ensured = specs
    return {}
end
assert(coroutine.resume(threads[1]))
assert(coroutine.status(threads[1]) == 'dead', 'CCTV schema setup must finish')
assert(ensured == env.QBBusinessesCctvSchema and #ensured == 2, 'CCTV schema must be ensured')
assert(ensured[1].name == 'kora_businesses_cctv_callouts' and ensured[2].name == 'kora_businesses_cctv_systems')
local business
for _, column in ipairs(ensured[1].columns) do if column.name == 'business' then business = column end end
assert(business and business.modify == true and business.null == true, 'callout business column must stay nullable')
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
env.Kora.sql.single = function() return nil end
env.Kora.sql.update = function() return true end
env.Kora.minigames = { authorizeSkillCheck = function() return 'authorization' end, consumeProof = function() return true end }
env.Kora.skills = { get = function() return { level = 10 } end }
env.Kora.notify = { send = noop }
local function noticed(bucket)
    assert(#notices == 1 and notices[1].src == 1 and notices[1].bucket == bucket, 'exact notice must follow the raw bucket native')
    assert(buckets[1] == bucket)
    notices = {}
end
local function beginHack()
    assert(callbacks['qbbusinesses:cctv:beginHack'](1, { targetId = 'system' }) == true)
    noticed(env.Cctv.hacking.privateBucketBase + 1)
end
beginHack()
assert(callbacks['qbbusinesses:cctv:finishHack'](1, { proof = 'proof' }) == true)
noticed(42)
beginHack()
clock = clock + env.Cctv.hacking.duration + 1
assert(callbacks['qbbusinesses:cctv:finishHack'](1, {}) == false)
noticed(42)
beginHack()
clock = clock + env.Cctv.hacking.duration + 1
assert(coroutine.resume(threads[2]))
assert(coroutine.resume(threads[2]))
noticed(42)
beginHack()
env.source = 1
handlers.playerDropped()
noticed(42)
env.SetPlayerRoutingBucket = function() error('controlled native failure') end
assert(not pcall(callbacks['qbbusinesses:cctv:beginHack'], 1, { targetId = 'system' }))
assert(#notices == 0, 'failed native does not notify')
print('qbbusinesses CCTV: engineer authorization, billing and bucket notices passed')
