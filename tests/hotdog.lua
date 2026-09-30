-- Exercise the real deposit callbacks against the sibling core's money implementation.
-- Set QB_CORE_ROOT if qbcore is checked out somewhere else.
local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'
local coreRoot = os.getenv('QB_CORE_ROOT') or root .. '../qbcore'
local env = {}
for name, value in pairs(_G) do env[name] = value end
env.Config, env.Hotdog, env.Globals = nil, nil, {}
env.vector4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end
env.GetConvar = function(_, default) return default end
env.AddEventHandler = function() end
env.TriggerEvent = function() end
env.TriggerClientEvent = function() end
env.Player = function() return { state = { set = function() end } } end
local callbacks, logs = {}, {}
local authorizations, debits, refunds = 0, 0, 0
env.QB = {
    callback = { register = function(name, fn) callbacks[name] = fn end },
    print = { error = function(message) logs[#logs + 1] = message end },
    lang = function(key) return key end,
    minigames = { authorizeProof = function()
        authorizations = authorizations + 1
        return 'proof-authorization'
    end },
}
env.Lang = { t = function(_, key) return key end }
assert(loadfile(coreRoot .. '/config.lua', 't', env))()
local handle = { PlayerData = {
    citizenid = 'CID1', job = { name = 'hotdog' }, money = { bank = env.Config.money.minusLimit },
} }
env.CoreInternal = { player = { handle = function(src) return src == 1 and handle or nil end } }
env.Core = { money = {}, player = {} }
env.Core.player.setPath = function(_, path, value)
    handle.PlayerData[path[1]][path[2]] = value
    return true
end
assert(loadfile(coreRoot .. '/modules/money/server.lua', 't', env))()
local legacy = { PlayerData = handle.PlayerData }
local lastDebit, lastDebitError
legacy.RemoveMoney = function(account, amount, reason)
    debits = debits + 1
    lastDebit, lastDebitError = env.Core.money.removeMoney(1, account, amount, reason)
    return lastDebit, lastDebitError
end
legacy.AddMoney = function(account, amount, reason)
    refunds = refunds + 1
    return env.Core.money.addMoney(1, account, amount, reason)
end
env.exports = { ['qb-core'] = {
    GetCoreObject = function() return { Commands = { Add = function() end } } end,
    GetPlayer = function(_, src) return src == 1 and legacy or nil end,
} }
assert(loadfile(root .. 'jobs/hotdog/config.lua', 't', env))()
assert(loadfile(root .. 'jobs/hotdog/server.lua', 't', env))()
local config = env.Hotdog or env.Config
local start = assert(callbacks['qb-hotdogjob:startWorking'])
local stop = assert(callbacks['qb-hotdogjob:stopWorking'])
local prepare = assert(callbacks['qb-hotdogjob:beginPreparing'])
local checks = 0
local function equal(actual, expected, message)
    checks = checks + 1
    assert(actual == expected, ('%s: expected %s, got %s'):format(message, tostring(expected), tostring(actual)))
end

local floor = handle.PlayerData.money.bank
local rejected, reason = start(1)
equal(rejected, false, 'a rejected deposit cannot start work')
equal(reason, nil, 'deposit failure preserves the false-only client callback contract')
equal(lastDebit, false, 'the actual core debit returns boolean false')
equal(lastDebitError, 'insufficient funds', 'the configured bank floor refuses the deposit')
equal(handle.PlayerData.money.bank, floor, 'a rejected debit does not change the balance')
equal(prepare(1), false, 'unpaid work cannot authorize preparation')
equal(authorizations, 0, 'a rejected deposit creates no preparation authority')
equal(stop(1), false, 'unpaid work cannot request a deposit refund')
equal(refunds, 0, 'a rejected deposit never reaches AddMoney')
equal(handle.PlayerData.money.bank, floor, 'a rejected start and stop cannot create money')

handle.PlayerData.money.bank = 1000
equal(start(1), true, 'a paid deposit starts work')
equal(lastDebit, true, 'the actual core success is boolean true, not numeric one')
equal(handle.PlayerData.money.bank, 1000 - config.StandDeposit, 'a paid start removes the configured deposit')
local paidDebits = debits
equal(start(1), false, 'a duplicate start is refused')
equal(debits, paidDebits, 'a duplicate start cannot debit again')
equal(type(prepare(1)), 'table', 'paid work may authorize preparation')
equal(stop(1), true, 'returning a paid stand succeeds')
equal(handle.PlayerData.money.bank, 1000, 'successful start and return balance exactly')
local returnedRefunds = refunds
equal(stop(1), false, 'a duplicate return is refused')
equal(refunds, returnedRefunds, 'a duplicate return cannot refund twice')
equal(prepare(1), false, 'returned work has no preparation authority')

equal(start(1), true, 'a new stand can start after return')
equal(stop(1), true, 'the existing spawn-failure cancellation callback refunds a paid deposit')
equal(handle.PlayerData.money.bank, 1000, 'spawn cancellation balances its deposit')
returnedRefunds = refunds
equal(stop(1), false, 'a repeated spawn cancellation is refused')
equal(refunds, returnedRefunds, 'spawn cancellation refunds only once')

config.StandDeposit = 0
local freeDebits = debits
equal(start(1), true, 'a zero-deposit stand remains free')
equal(debits, freeDebits, 'free stands skip the core zero-amount debit')
equal(type(prepare(1)), 'table', 'free work may authorize preparation')
equal(stop(1), true, 'a free stand keeps the existing successful return contract')
equal(handle.PlayerData.money.bank, 1000, 'a free stand never changes the balance')
equal(stop(1), false, 'a free stand still cannot be returned twice')

config.StandDeposit = '250'
handle.PlayerData.money.bank = floor
equal(start(1), false, 'a positive numeric-string deposit still requires payment')
equal(handle.PlayerData.money.bank, floor, 'a failed numeric-string deposit cannot change the balance')
equal(stop(1), false, 'a failed numeric-string deposit cannot authorize a refund')
handle.PlayerData.money.bank = 1000
equal(start(1), true, 'a payable numeric-string deposit remains supported')
equal(lastDebit, true, 'a numeric-string deposit keeps the core boolean success contract')
equal(handle.PlayerData.money.bank, 750, 'a numeric-string deposit debits its numeric value')
equal(stop(1), true, 'a numeric-string deposit can be returned')
equal(handle.PlayerData.money.bank, 1000, 'numeric-string start and return balance exactly')
config.StandDeposit = '0'
freeDebits = debits
equal(start(1), true, 'a string-zero deposit remains free')
equal(debits, freeDebits, 'string-zero stands skip the debit')
equal(stop(1), true, 'a string-zero stand retains its successful return contract')
equal(handle.PlayerData.money.bank, 1000, 'a string-zero stand never changes the balance')
print('qbbusinesses hotdog: ' .. checks .. ' deposit checks passed')
