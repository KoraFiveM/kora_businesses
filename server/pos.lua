-- Point of sale: the customer-facing shop, the employee-facing intake stash,
-- pricing policy, and where the money from a sale ends up.
--
-- Stock itself is NOT stored by this resource. qbinventory already owns a shop
-- inventory and persists it durably, so duplicating it here would create two
-- sources of truth for the same shelf. What this file owns is policy: which
-- items a till accepts, what they cost, who may open it, and the payout split.

QbBusinesses = QbBusinesses or {}

local State = QbBusinesses.state
local Logs = QbBusinesses.logs
local Staff = QbBusinesses.staff

local Pos = {}
QbBusinesses.pos = Pos

---@type table<string, table> shopId -> { businessId, module }
local shops = {}
Pos.shops = shops

---@type table<string, table<string, integer>> shopId -> item -> remembered price
local remembered = {}

---@type table<string, true> shops with an intake in flight
local intaking = {}

---The stash goods are dropped into before they reach the shelf.
---@param shopId string
---@return string
local function stockId(shopId) return shopId .. '_stock' end
Pos.stockId = stockId

---@param key any
---@return string|nil shopId
local function shopIdFromStockKey(key)
    if type(key) ~= 'string' then return nil end
    local id = key:match('^stash:(.+)_stock$')
    return id and shops[id] and id or nil
end

-- ---------------------------------------------------------------------------
-- Pricing
-- ---------------------------------------------------------------------------

---Items whose price is fixed by a `Config.shopItems` list this till references.
---@param module table
---@return table<string, integer> fixed, boolean restricted
local function fixedPrices(module)
    -- `false` means "this till stocks the item but does not fix its price";
    -- `nil` means "this till does not stock it at all". Both are meaningful,
    -- which is why the absent case is never written as `false` by accident.
    local fixed, restricted = {}, false
    for _, listName in ipairs(module.items or {}) do
        local list = Config.shopItems[listName]
        if list then
            restricted = true
            for _, entry in ipairs(list) do
                local name = type(entry) == 'table' and entry.item or entry
                local price = type(entry) == 'table' and tonumber(entry.price) or nil
                if type(name) == 'string' then
                    fixed[name:lower()] = price and math.floor(price) or false
                end
            end
        else
            print(('^3[qbbusinesses]^7 till %s references unknown shop-item list "%s"'):format(module.id, listName))
        end
    end
    return fixed, restricted
end

---@param shopId string
---@param itemName string
---@return integer|nil price, boolean isFixed
function Pos.priceFor(shopId, itemName)
    local record = shops[shopId]
    if not record then return nil, false end
    local fixed = record.fixed[itemName]
    if type(fixed) == 'number' then return fixed, true end
    local stored = remembered[shopId] and remembered[shopId][itemName]
    return stored, false
end

---@param shopId string
---@param itemName string
---@return boolean
function Pos.accepts(shopId, itemName)
    local record = shops[shopId]
    if not record then return false end
    if not record.restricted then return true end
    return record.fixed[itemName] ~= nil
end

---@param shopId string
---@param itemName string
---@param price integer
local function rememberPrice(shopId, itemName, price)
    remembered[shopId] = remembered[shopId] or {}
    remembered[shopId][itemName] = price
    QB.sql.executeAsync([[INSERT INTO `qbbusinesses_prices` (`shop`,`item`,`price`) VALUES (?,?,?)
        ON DUPLICATE KEY UPDATE `price` = VALUES(`price`)]], { shopId, itemName, price }, function() end)
end

local function loadPrices()
    local rows = QB.sql.query('SELECT `shop`, `item`, `price` FROM `qbbusinesses_prices`')
    remembered = {}
    for _, row in ipairs(rows or {}) do
        remembered[row.shop] = remembered[row.shop] or {}
        remembered[row.shop][row.item] = math.floor(tonumber(row.price) or 0)
    end
end
Pos.loadPrices = loadPrices

-- ---------------------------------------------------------------------------
-- Society payouts
-- ---------------------------------------------------------------------------

local function bossMenuReady()
    return GetResourceState('qbbossmenu') == 'started'
end

---@param job string
---@param amount number
---@param reason string
---@return boolean ok, string|nil err
function Pos.credit(job, amount, reason)
    amount = math.floor(amount or 0)
    if amount <= 0 then return true end
    if not bossMenuReady() then return false, 'no business account resource is running' end
    return exports.qbbossmenu:addBusinessMoney(job, amount, reason)
end

---@param job string
---@param amount number
---@param reason string
---@return boolean ok, string|nil err
function Pos.debit(job, amount, reason)
    amount = math.floor(amount or 0)
    if amount <= 0 then return true end
    if not bossMenuReady() then return false, 'no business account resource is running' end
    return exports.qbbossmenu:removeBusinessMoney(job, amount, reason)
end

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------

---Two till modules may deliberately share one shop id (a row of registers).
---The first registration owns the policy; a later one that disagrees is a
---config mistake worth naming rather than silently resolving.
---@param business table
---@param module table
function Pos.register(business, module)
    local existing = shops[module.id]
    if existing then
        if existing.businessId ~= business.id then
            print(('^3[qbbusinesses]^7 till id "%s" is used by both %s and %s; keeping %s'):format(
                module.id, existing.businessId, business.id, existing.businessId))
        elseif existing.module.commission ~= module.commission or existing.module.tax ~= module.tax then
            print(('^3[qbbusinesses]^7 till id "%s" has conflicting commission/tax across modules'):format(module.id))
        end
        return
    end

    local fixed, restricted = fixedPrices(module)
    shops[module.id] = {
        businessId = business.id, module = module, fixed = fixed, restricted = restricted,
    }

    local function shopAccess(src)
        local record = shops[module.id]
        if not record then return false, 'this till is closed' end
        if not record.module.hideWhenStaffed then return true end
        if State.worksFor(src, business.job) then return true end
        if Staff.countFor(business.id) > 0 then return false, 'a member of staff will serve you' end
        return true
    end

    exports.qbinventory:RegisterShop(module.id, {
        label = module.label or business.label,
        slots = module.shopSlots,
        maxWeight = Config.pos.shopWeight,
        currency = module.currency,
        access = shopAccess,
    })

    -- Job-locked: the intake stash is where unsold company goods sit, so it is
    -- staff-only regardless of the till's own `public` flag.
    exports.qbinventory:RegisterStash(stockId(module.id), (module.label or business.label) .. ' Stock',
        module.stockSlots, Config.pos.stockWeight, false, { [business.job] = 0 })
end

---@param shopId any
---@return table|nil record
function Pos.record(shopId)
    return type(shopId) == 'string' and shops[shopId] or nil
end

---@param shopId string
---@return table|nil business, table|nil module
function Pos.context(shopId)
    local record = shops[shopId]
    if not record then return nil end
    return State.get(record.businessId), record.module
end

-- ---------------------------------------------------------------------------
-- Stock intake
-- ---------------------------------------------------------------------------

---@param items table
---@param name string
---@param info table
---@param price integer
---@param slots integer
---@return integer|nil slot
local function sameInfo(a, b)
    a, b = a or {}, b or {}
    for key, value in pairs(a) do if b[key] ~= value then return false end end
    for key, value in pairs(b) do if a[key] ~= value then return false end end
    return true
end

local function slotFor(items, name, info, price, slots)
    for slot = 1, slots do
        local existing = items[slot]
        if existing and existing.name == name and existing.price == price and sameInfo(existing.info, info) then
            return slot
        end
    end
    for slot = 1, slots do
        if not items[slot] then return slot end
    end
    return nil
end

---Moves everything in a till's intake stash onto its shelf.
---
---Prices are resolved FIRST, because asking the employee for one yields, and
---anything can happen to a stash across a yield. The stash is then re-read and
---the move itself runs to completion without yielding, so an item can never be
---both left in the stash and put on the shelf.
---@param src integer
---@param shopId string
function Pos.intake(src, shopId)
    local record = shops[shopId]
    if not record or intaking[shopId] then return end
    local business, module = Pos.context(shopId)
    if not business then return end
    -- Closing an inventory by disconnecting also fires sessionClosed. Asking a
    -- player who is gone for a price would just burn the callback timeout.
    if not exports.qbcore:getPlayerData(src) then return end

    local staged = exports.qbinventory:GetStashItems(stockId(shopId)) or {}
    if not next(staged) then return end

    intaking[shopId] = true

    local prices, rejected = {}, {}
    for _, item in pairs(staged) do
        local name = item.name
        if prices[name] == nil and rejected[name] == nil then
            if not Pos.accepts(shopId, name) then
                rejected[name] = true
            else
                local price, isFixed = Pos.priceFor(shopId, name)
                if not price and not isFixed then
                    local answer = QB.callback.trigger(src, 'qbbusinesses:client:setPrice', {
                        item = name, label = item.label or name, max = Config.pos.maxPrice,
                    })
                    price = tonumber(answer)
                    price = price and math.floor(price) or nil
                    if price and (price < 0 or price > Config.pos.maxPrice) then price = nil end
                    if price then rememberPrice(shopId, name, price) end
                end
                if price then prices[name] = price else rejected[name] = true end
            end
        end
    end

    -- No yields past this point until the move is committed.
    local remaining = exports.qbinventory:GetStashItems(stockId(shopId)) or {}
    local shelf = exports.qbinventory:GetShopItems(shopId) or {}
    local moved, commissionBase = {}, 0

    for slot, item in pairs(remaining) do
        local price = prices[item.name]
        if price then
            local target = slotFor(shelf, item.name, item.info, price, module.shopSlots)
            if target then
                local existing = shelf[target]
                shelf[target] = {
                    name = item.name,
                    amount = (existing and existing.amount or 0) + item.amount,
                    info = item.info, price = price,
                }
                remaining[slot] = nil
                moved[item.name] = (moved[item.name] or 0) + item.amount
                commissionBase = commissionBase + (price * item.amount)
            end
        end
    end

    if not next(moved) then
        intaking[shopId] = nil
        if next(rejected) then
            QB.notify.send(src, { title = Config.notifyTitle, message = 'This till does not stock those items.', type = 'error' })
        end
        return
    end

    local ok, err = exports.qbinventory:SetShopItems(shopId, shelf)
    if not ok then
        intaking[shopId] = nil
        QB.notify.send(src, { title = Config.notifyTitle, message = 'The shelf is full.', type = 'error' })
        print(('^3[qbbusinesses]^7 could not stock %s: %s'):format(shopId, tostring(err)))
        return
    end
    local cleared, clearErr = exports.qbinventory:SetStashItems(stockId(shopId), remaining)
    if not cleared then
        -- The shelf already has the goods, so leaving them in the stash too
        -- would duplicate them. Nothing can undo the shelf write from here;
        -- say so loudly rather than letting it pass unnoticed.
        print(('^1[qbbusinesses]^7 stocked %s but could not clear its intake stash: %s')
            :format(shopId, tostring(clearErr)))
    end
    intaking[shopId] = nil

    local summary = {}
    for name, amount in pairs(moved) do summary[#summary + 1] = ('%dx %s'):format(amount, name) end
    table.sort(summary)

    local commission = math.floor(commissionBase * (module.commission / 100))
    if commission > 0 then
        local paid = Pos.debit(business.job, commission, 'stocking commission')
        if paid then
            exports.qbcore:addMoney(src, 'cash', commission, 'qbbusinesses-stock-commission')
            QB.notify.send(src, {
                title = Config.notifyTitle,
                message = ('Stocked %s. Commission: $%d'):format(table.concat(summary, ', '), commission),
                type = 'success',
            })
        else
            commission = 0
            QB.notify.send(src, {
                title = Config.notifyTitle,
                message = ('Stocked %s. The business could not cover your commission.'):format(table.concat(summary, ', ')),
                type = 'warning',
            })
        end
    else
        QB.notify.send(src, {
            title = Config.notifyTitle,
            message = ('Stocked %s.'):format(table.concat(summary, ', ')),
            type = 'success',
        })
    end

    if next(rejected) then
        QB.notify.send(src, { title = Config.notifyTitle, message = 'Some items were left behind: this till does not stock them.', type = 'warning' })
    end

    Logs.record(business, {
        category = 'stock', src = src, amount = commission, webhook = module.webhook,
        message = ('Stocked %s into %s.'):format(table.concat(summary, ', '), module.label or shopId),
        fields = {
            { name = 'Retail value', value = ('$%d'):format(commissionBase), inline = true },
            { name = 'Commission', value = ('$%d'):format(commission), inline = true },
        },
    })
end

---Intake runs when the employee closes the stash, not on every item they drop
---in, so a restock is one price prompt per item type instead of one per drag.
AddEventHandler('qbinventory:server:sessionClosed', function(src, session)
    local shopId = shopIdFromStockKey(session and session.secondary)
    if not shopId then return end
    CreateThread(function() Pos.intake(src, shopId) end)
end)

---Instant feedback at drag time for an item the till will never accept, so an
---employee is not left wondering why it stayed in the stash.
exports.qbinventory:RegisterHook('swapItems', function(payload)
    local shopId = shopIdFromStockKey(payload.toInventory)
    if not shopId then return end
    if Pos.accepts(shopId, payload.itemName) then return end
    return false
end, { typeFilter = { stash = true } })

-- ---------------------------------------------------------------------------
-- Sales
-- ---------------------------------------------------------------------------

---Sales are credited from qbinventory's own post-commit audit event, not from a
---`buyItem` hook: a hook fires BEFORE the purchase is locked and committed, so
---crediting there would pay the business for a sale that could still fail on
---weight, funds or a stale revision.
AddEventHandler('qbinventory:server:audit', function(action, src, details)
    if action ~= 'purchase' or type(details) ~= 'table' then return end
    local business, module = Pos.context(details.shop)
    if not business then return end

    local gross = math.floor(tonumber(details.price) or 0)
    local tax = math.floor(gross * (module.tax / 100))
    local net = gross - tax

    local ok, err = Pos.credit(business.job, net, 'till sale')
    if not ok then
        print(('^3[qbbusinesses]^7 could not credit %s for a sale: %s'):format(business.job, tostring(err)))
    end

    Logs.record(business, {
        category = 'sale', src = src, amount = net, webhook = module.webhook,
        message = ('Sold %dx %s for $%d.'):format(details.amount or 1, details.item or '?', gross),
        fields = {
            { name = 'Tax', value = ('$%d'):format(tax), inline = true },
            { name = 'To business', value = ('$%d'):format(net), inline = true },
        },
    })
end)

-- ---------------------------------------------------------------------------
-- Player-facing actions
-- ---------------------------------------------------------------------------

local function tillContext(src, shopId, requireBoss)
    local record = shops[shopId]
    if not record then return nil, nil, 'Unknown till.' end
    local business = State.get(record.businessId)
    if not business then return nil, nil, 'Unknown business.' end
    if requireBoss then
        if not State.canManage(src, business) then return nil, nil, 'Only a boss can do that.' end
    elseif not State.worksFor(src, business.job) and not record.module.public then
        return nil, nil, 'You do not work here.'
    end
    return business, record.module
end

QB.callback.register('qbbusinesses:server:openShop', function(src, shopId)
    local record = shops[shopId]
    if not record then return false, 'Unknown till.' end
    return exports.qbinventory:OpenInventory(src, record.module.id, { type = 'shop', id = record.module.id })
end, { rateLimit = { max = 10, window = 10000 } })

QB.callback.register('qbbusinesses:server:openStock', function(src, shopId)
    local _, _, err = tillContext(src, shopId)
    if err then return false, err end
    return exports.qbinventory:stashOpen(src, stockId(shopId))
end, { rateLimit = { max = 10, window = 10000 } })

---The current shelf, as a boss-facing price list.
QB.callback.register('qbbusinesses:server:tillPrices', function(src, shopId)
    local _, module, err = tillContext(src, shopId, true)
    if err then return nil, err end
    local shelf = exports.qbinventory:GetShopItems(shopId) or {}
    local rows = {}
    for slot, item in pairs(shelf) do
        local _, isFixed = Pos.priceFor(shopId, item.name)
        rows[#rows + 1] = {
            slot = slot, name = item.name, label = item.label or item.name,
            amount = item.amount, price = item.price, fixed = isFixed,
        }
    end
    table.sort(rows, function(a, b) return a.slot < b.slot end)
    return { shop = shopId, label = module.label, max = Config.pos.maxPrice, items = rows }
end, { rateLimit = { max = 10, window = 10000 } })

QB.callback.register('qbbusinesses:server:setTillPrice', function(src, shopId, slot, price)
    local business, module, err = tillContext(src, shopId, true)
    if err then return false, err end

    slot = math.floor(tonumber(slot) or 0)
    price = math.floor(tonumber(price) or -1)
    if price < 0 or price > Config.pos.maxPrice then return false, 'That price is out of range.' end

    local shelf = exports.qbinventory:GetShopItems(shopId) or {}
    local item = shelf[slot]
    if not item then return false, 'That slot is empty.' end

    local _, isFixed = Pos.priceFor(shopId, item.name)
    if isFixed then return false, 'That item has a fixed price.' end

    item.price = price
    local ok, writeErr = exports.qbinventory:SetShopItems(shopId, shelf)
    if not ok then return false, writeErr or 'Could not update the price.' end
    rememberPrice(shopId, item.name, price)

    Logs.record(business, {
        category = 'admin', src = src, amount = price, webhook = module.webhook,
        message = ('Set the price of %s to $%d at %s.'):format(item.name, price, module.label or shopId),
    })
    return true
end, { rateLimit = { max = 20, window = 10000 } })

QB.callback.register('qbbusinesses:server:panic', function(src, businessId, shopId)
    local record = shops[shopId]
    local business = State.get(businessId)
    if not business or not record or record.businessId ~= business.id then return false, 'Unknown till.' end
    if not record.module.panicButton then return false, 'This till has no panic button.' end

    if GetResourceState('qbdispatch') ~= 'started' then
        return false, 'No dispatch service is available.'
    end

    local anchor = record.module.zoneType and record.module.coords or (record.module.coords and record.module.coords[1])
    local coords = anchor and vector3(anchor.x, anchor.y, anchor.z) or GetEntityCoords(GetPlayerPed(src))

    local callId, recipients = exports.qbdispatch:createCall({
        jobTypes = Config.panic.jobTypes,
        code = Config.panic.code,
        priority = Config.panic.priority,
        icon = Config.panic.icon,
        title = ('Panic alarm: %s'):format(business.label),
        message = ('A silent alarm was triggered at %s.'):format(business.label),
        coords = coords,
        data = { business = business.id, job = business.job },
    })
    if not callId then return false, recipients or 'Dispatch refused the call.' end

    Logs.record(business, {
        category = 'panic', src = src, webhook = record.module.webhook,
        message = ('Panic alarm triggered at %s.'):format(record.module.label or shopId),
    })
    return true, recipients
end, { rateLimit = { max = 3, window = 30000 } })
