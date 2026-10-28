-- Exercise the real deposit callbacks against the sibling core's money implementation.
-- Set QB_CORE_ROOT if kora_core is checked out somewhere else.
local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'
local coreRoot = os.getenv('QB_CORE_ROOT') or root .. '../kora_core'
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
env.exports = { kora_core = {
    getPlayerData = function(_, src) return src == 1 and handle.PlayerData or nil end,
    removeMoney = function(_, src, ...) assert(src == 1); return legacy.RemoveMoney(...) end,
    addMoney = function(_, src, ...) assert(src == 1); return legacy.AddMoney(...) end,
    addCommand = function() end,
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
-- The actual client closure reads its cached skill level; no cart/native loop is run.
local clientEvents = {}
local clientData = { job = { name = 'hotdog' }, skills = { cooking = { level = 1, xp = 0 } } }
env.exports.kora_core.getPlayerData = function() return clientData end
env.RegisterNetEvent = function(name, fn) clientEvents[name] = fn end
local clientThreads = {}
env.CreateThread = function(fn) clientThreads[#clientThreads + 1] = fn end
env.QB.nui = { registerApp = function() end }
env.QB.keybind = { add = function() end }
env.QB.blips = { create = function() return 1 end, remove = function() end }
assert(loadfile(root .. 'jobs/hotdog/client.lua', 't', env))()
local function upvalue(fn, wanted)
    for index = 1, debug.getinfo(fn, 'u').nups do
        local name, value = debug.getupvalue(fn, index)
        if name == wanted then return value end
    end
    error('missing actual client closure: ' .. wanted)
end
local startSelling = upvalue(assert(clientEvents['qb-hotdogjob:client:ToggleSell']), 'startSelling')
local sellToPed = upvalue(startSelling, 'sellToPed')
local offerRange = upvalue(sellToPed, 'offerRange')
local getLevel = upvalue(offerRange, 'getLevel')
for _, case in ipairs({
    { level = 1, tier = 1 }, { level = 2, tier = 2 }, { level = 3, tier = 3 },
    { level = 4, tier = 4 }, { level = 5, tier = 4 }, { level = 15, tier = 4 },
    { level = 30, tier = 4 }, { level = 70, tier = 4 }, { level = 90, tier = 4 },
    { level = 99, tier = 4 },
}) do
    local level = case.level
    clientData.skills.cooking.level = level
    clientEvents['QBCore:Client:OnPlayerLoaded']()
    equal(getLevel(), level, 'price selection preserves the cooking level')
    for _, quality in ipairs({ 'common', 'rare', 'exotic' }) do
        for _, amount in ipairs({ 1, 3 }) do
            local price = config.Stock[quality].Price[case.tier]
            equal(offerRange(quality, amount), ('%d-%d'):format(price.min * amount, price.max * amount),
                'offer range matches authoritative price tier and unchanged amount format')
        end
    end
end
clientData.skills = nil
clientEvents['QBCore:Client:OnPlayerLoaded']()
local price = config.Stock.common.Price[1]
equal(offerRange('common', 1), ('%d-%d'):format(price.min, price.max), 'missing skills preserve the level-one fallback')

-- Locale values must reach the real formatter, not a key-only fixture.
local libraryRoot = os.getenv('QB_LIB_ROOT') or root .. '../kora_lib'
env.QB.locale = {}
env.GetInvokingResource = function() return 'kora_businesses' end
env.GetCurrentResourceName = function() return 'kora_businesses' end
env.LoadResourceFile = function(resource, path)
    if resource ~= 'kora_businesses' then return nil end
    local file = io.open(root .. path, 'rb')
    if not file then return nil end
    local value = file:read('*a'); file:close()
    return value
end
assert(loadfile(libraryRoot .. '/modules/locales/shared.lua', 't', env))()
local addCustomerTarget = upvalue(sellToPed, 'addCustomerTarget')
local completeSale = upvalue(upvalue(addCustomerTarget, 'acceptOffer'), 'completeSale')
local lastTarget, lastNotice, workOptions
local saleCalls = {}
env.QB.interact = {
    addEntity = function(ped, options) lastTarget = { ped = ped, options = options }; return 17 end,
    removeEntity = function() end,
    addBoxZone = function(_, _, _, options) workOptions = options end,
}
env.QB.notify = { send = function(data) lastNotice = data end }
env.QB.nui.updateApp = function() end
env.QB.nui.isAppOpen = function() return false end
env.QB.cache = { ped = function() return 10 end }
env.QB.anim = { play = function() end, clear = function() end }
env.QB.entities = { delete = function() end }
env.DoesEntityExist = function(entity) return entity == 101 end
env.NetworkGetNetworkIdFromEntity = function(ped) return ped + 1000 end
env.QB.callback.trigger = function(name, ...)
    if name ~= 'qb-hotdogjob:sell' then return true end
    saleCalls[#saleCalls + 1] = { ... }
    return { amount = 3, total = 27 }
end
for _, case in ipairs({ { amount = 1, range = '4-6' }, { amount = 3, range = '21-27' } }) do
    addCustomerTarget(201, 'common', case.amount, case.range)
    equal(lastTarget.ped, 201, 'offer target retains its customer')
    equal(lastTarget.options[1].label, ('Sell %d x HotDogs for $%s'):format(case.amount, case.range),
        'offer text interpolates the configured amount and price range')
    equal(type(lastTarget.options[1].action), 'function', 'accept callback remains available')
    equal(lastTarget.options[2].label, 'Decline offer', 'decline option remains unchanged')
end
upvalue(completeSale, 'stock').common = 3
completeSale(201, 'common', 3)
equal(lastNotice.message, "3 x Hotdog('s) sold for $27", 'sale result formats the configured values')
equal(lastNotice.type, 'success', 'sale notification type remains unchanged')
equal(saleCalls[1][1], 1201, 'sale passes the same network customer')
equal(saleCalls[1][2], 'common', 'sale passes the same quality')
equal(saleCalls[1][3], 3, 'sale passes the same amount')
equal(upvalue(completeSale, 'stock').common, 0, 'successful sale retains stock consumption')
-- Run only the captured startup registration and explicit work actions, never its watch loop.
config.StandDeposit = 250
env.vector3 = function(x, y, z) return { x = x, y = y, z = z } end
env.QB.stream = { loadModel = function(_, callback) callback(1); return true end }
env.CreateObject = function() return 101 end
env.PlaceObjectOnGroundProperly = function() end
env.SetEntityHeading = function() end
env.FreezeEntityPosition = function() end
clientThreads[1]()
workOptions[1].action(); clientThreads[#clientThreads]()
equal(lastNotice.message, 'You paid a $250 deposit!', 'paid start formats the existing deposit')
workOptions[2].action(); clientThreads[#clientThreads]()
equal(lastNotice.message, 'Your $250 deposit has been returned!', 'stand return formats the existing deposit')
equal(lastNotice.type, 'success', 'return notification type remains unchanged')
equal(env.QB.lang('hotdog.' .. 'success.made_luck_hotdog', 2, 'Rare (B)'), 'You made 2 x Rare (B) Hot Dogs',
    'unrelated positional hotdog phrases retain their contract')

print('qbbusinesses hotdog: ' .. checks .. ' deposit and offer-price checks passed')
