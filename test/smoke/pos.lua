-- Focused runtime proof that restocking pays nothing and a commission can be
-- released only from qbinventory's post-commit purchase audit.
local H = dofile('test/harness.lua')

local business = { id = 'burgershot', label = 'Burger Shot', job = 'burgershot' }
local accountOps, employeePayments, logEntries = {}, {}, {}
local stashReads = 0
local shelfWritten

QbBusinesses = {
    state = {
        get = function(id) return id == business.id and business or nil end,
        worksFor = function() return true end,
        employeeAt = function() return true end,
        moduleBoundary = function(module) return { module.coords }, module.distance end,
    },
    logs = { record = function(_, entry) logEntries[#logEntries + 1] = entry end },
    staff = { countFor = function() return 0 end },
}
Config = {
    shopItems = { burgershot = { { item = 'burger', price = 100 } } },
    pos = { shopWeight = 10000, stockWeight = 10000, maxPrice = 1000 },
    notifyTitle = 'Business',
}

local events = {}
AddEventHandler = function(name, callback) events[name] = callback end
CreateThread = function(callback) callback() end
GetResourceState = function() return 'started' end
GetPlayerPed = function() return 1 end
GetEntityCoords = function() return { x = 0, y = 0, z = 0 } end
vector3 = function(x, y, z) return { x = x, y = y, z = z } end

exports = {
    qbinventory = {
        RegisterShop = function() return true end,
        RegisterStash = function() return true end,
        RegisterHook = function() return true end,
        GetStashItems = function()
            stashReads = stashReads + 1
            if stashReads <= 2 then
                return { [1] = { name = 'burger', label = 'Burger', amount = 2, info = {} } }
            end
            return {}
        end,
        GetShopItems = function() return {} end,
        SetShopItems = function(_, _, items) shelfWritten = items; return true end,
        SetStashItems = function() return true end,
    },
    qbcore = {
        getPlayerData = function() return { citizenid = 'CID-STOCKER' } end,
        getPlayerByCitizenId = function(_, citizenid)
            return citizenid == 'CID-STOCKER' and { source = 41 } or nil
        end,
        addMoney = function(_, src, account, amount, reason)
            employeePayments[#employeePayments + 1] = { src = src, account = account, amount = amount, reason = reason }
            return true
        end,
    },
    qbbossmenu = {
        addBusinessMoney = function(_, job, amount, reason)
            accountOps[#accountOps + 1] = { action = 'credit', job = job, amount = amount, reason = reason }
            return true
        end,
        removeBusinessMoney = function(_, job, amount, reason)
            accountOps[#accountOps + 1] = { action = 'debit', job = job, amount = amount, reason = reason }
            return true
        end,
    },
}
QB = {
    sql = { executeAsync = function() end, query = function() return {} end },
    callback = { register = function() end, trigger = function() return nil end },
    notify = { send = function() end },
}

dofile('server/pos.lua')
local Pos = QbBusinesses.pos
local module = {
    id = 'front_till', label = 'Front Till', items = { 'burgershot' },
    commission = 10, tax = 10, shopSlots = 10, stockSlots = 10,
    currency = 'cash', coords = { x = 0, y = 0, z = 0 }, distance = 2,
}
business.modules = { module }
Pos.register(business, module)

Pos.intake(41, module.id)
H.equal(#accountOps, 0, 'stock intake does not credit or debit money')
H.equal(#employeePayments, 0, 'stock intake pays no employee commission')
H.equal(shelfWritten[1].serverData.qbbusinesses.stocker, 'CID-STOCKER', 'stock carries server-only attribution')

events['qbinventory:server:audit']('purchase', 99, {
    shop = module.id, item = 'burger', amount = 1, price = 100,
    serverData = shelfWritten[1].serverData,
})
H.equal(accountOps[1].action, 'credit', 'committed sale revenue reaches the business first')
H.equal(accountOps[1].amount, 90, 'business is credited sale revenue after tax')
H.equal(accountOps[2].action, 'debit', 'commission is released only after sale credit')
H.equal(accountOps[2].amount, 10, 'commission uses the committed sale amount')
H.equal(employeePayments[1].src, 41, 'the authoritative stocker receives the commission')
H.equal(employeePayments[1].account, 'bank', 'sold-stock commission uses a durable player account')
H.equal(logEntries[#logEntries].amount, 80, 'sale log records the post-commission business share')

H.finish('pos')
