-- The portable card machine and the two price dialogs the server drives.
--
-- Every dialog here is registered as a CLIENT callback, so the server owns the
-- flow and only asks the client for the one piece of information a person has
-- to supply. Nothing in this file decides an outcome -- it collects an answer.

QbBusinesses = QbBusinesses or {}

local Client = QbBusinesses.client

---Asked when an employee restocks an item this till has no fixed price for.
QB.callback.register('qbbusinesses:client:setPrice', function(request)
    local result = QB.nui.openInputDialog({
        {
            id = 'price', label = ('Price for %s'):format(request.label or request.item),
            type = 'number', required = true, min = 0, max = request.max, default = 0,
        },
    }, 'Set a price', 'This price is remembered for future restocks of this item.')
    if not result or result.cancelled then return nil end
    return tonumber(result.values.price)
end)

---Asked of the employee taking a card payment.
QB.callback.register('qbbusinesses:client:billAmount', function(request)
    local result = QB.nui.openInputDialog({
        { id = 'amount', label = 'Amount', type = 'number', required = true, min = 1, max = request.max },
    }, 'Take a payment')
    if not result or result.cancelled then return nil end
    return tonumber(result.values.amount)
end)

---Asked of the customer being billed.
QB.callback.register('qbbusinesses:client:approveBill', function(request)
    local result = QB.nui.openAlert({
        title = request.business or 'Payment',
        message = ('Pay $%d?'):format(request.amount),
        confirmLabel = 'Pay',
        cancelLabel = 'Decline',
    })
    return result ~= nil and result.confirmed == true
end)

-- ---------------------------------------------------------------------------
-- Taking a payment
-- ---------------------------------------------------------------------------

---@param target? integer Server id; asked for when not supplied.
function QbBusinesses.takePayment(target)
    if not target then
        local result = QB.nui.openInputDialog({
            { id = 'id', label = 'Player ID', type = 'number', required = true, min = 1 },
        }, 'Take a payment', 'Who are you billing?')
        if not result or result.cancelled then return end
        target = tonumber(result.values.id)
    end
    if not target then return end

    local ok, err = QB.callback.trigger('qbbusinesses:server:requestPayment', target)
    if not ok then Client.notify(err or 'The payment did not go through.', 'error') end
end

---The card machine works anywhere, on anyone -- it is an item, not a fixture,
---so it is registered once globally rather than per business.
CreateThread(function()
    exports.qbtarget:addGlobalType('player', { {
        label = 'Take a payment',
        icon = 'CreditCard',
        distance = Config.payment.distance,
        canInteract = function(entity)
            if not exports.qbinventory:HasItem(Config.payment.item) then return false end
            return NetworkGetPlayerIndexFromPed(entity) ~= -1
        end,
        onSelect = function(entity)
            local index = NetworkGetPlayerIndexFromPed(entity)
            if index == -1 then return end
            QbBusinesses.takePayment(GetPlayerServerId(index))
        end,
    } }, Config.payment.distance)
end)

-- ---------------------------------------------------------------------------
-- Price editor
-- ---------------------------------------------------------------------------

---@param shopId string
function QbBusinesses.openPriceEditor(shopId)
    local till, err = QB.callback.trigger('qbbusinesses:server:tillPrices', shopId)
    if not till then return Client.notify(err or 'You cannot set prices here.', 'error') end
    if #till.items == 0 then return Client.notify('There is nothing on the shelf to price.', 'info') end

    local items = {}
    for _, item in ipairs(till.items) do
        items[#items + 1] = {
            id = tostring(item.slot),
            label = ('%s -- $%d'):format(item.label, item.price or 0),
            description = item.fixed and ('%dx in stock -- price is fixed by config'):format(item.amount)
                or ('%dx in stock'):format(item.amount),
            disabled = item.fixed,
        }
    end

    local choice = QB.nui.openMenu(items, ('%s prices'):format(till.label or shopId))
    if not choice or choice.cancelled or not choice.selectedId then return end

    local slot = tonumber(choice.selectedId)
    local current
    for _, item in ipairs(till.items) do if item.slot == slot then current = item end end
    if not current then return end

    local result = QB.nui.openInputDialog({
        { id = 'price', label = ('Price for %s'):format(current.label), type = 'number', required = true, min = 0, max = till.max, default = current.price or 0 },
    }, 'Set a price')
    if not result or result.cancelled then return end

    local ok, setErr = QB.callback.trigger('qbbusinesses:server:setTillPrice', shopId, slot, tonumber(result.values.price))
    Client.notify(ok and 'Price updated.' or (setErr or 'Could not update that price.'), ok and 'success' or 'error')
end
