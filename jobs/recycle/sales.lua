-- Total of an item across all inventory stacks, from the client's synced player data.
local function ownedCount(item)
    local data = exports.kora_core:getPlayerData() or {}
    local total = 0
    for _, entry in pairs(data.items or {}) do
        if entry.name == item then total = total + (entry.amount or 0) end
    end
    return total
end

local function maxPerSale(owned)
    return math.min(owned, Recycle.MaxSellPerRequest or 500)
end

local function sellMaterials()
    local itemList = Kora.callback.trigger('kora_businesses:recycle:getPriceList')
    if not itemList then
        Kora.notify.send({ title = 'Recycle Center', message = Kora.lang('recycle.error.too_far_to_sell'), type = 'error' })
        return
    end

    local appId, sellAction = 'kora_businesses:recycle:sell', 'kora_businesses:recycle:sellItem'

    local function buildItems()
        local items, names = {}, {}
        for itemName in pairs(itemList) do names[#names + 1] = itemName end
        table.sort(names)

        for _, itemName in ipairs(names) do
            local price = itemList[itemName]
            local owned = ownedCount(itemName)
            if owned > 0 or Recycle.SellHideEmpty == false then
                local item = exports.kora_core:getShared('items', itemName) or { name = itemName, label = itemName }

                local entry = {
                    id = 'material:' .. itemName,
                    label = item.label,
                    description = Kora.lang('recycle.text.owned', owned) .. ' · ' .. Kora.lang('recycle.text.price', price),
                    image = item.image and 'nui://kora_inventory/images/' .. item.image,
                }
                if owned > 0 then
                    local max = maxPerSale(owned)
                    entry.action = {
                        id = sellAction,
                        label = Kora.lang('recycle.text.sell'),
                        submitLabel = Kora.lang('recycle.text.sell_submit'),
                        fields = {
                            {
                                id = 'amount', label = Kora.lang('recycle.text.amount'), type = 'number',
                                min = 1, max = max, default = math.max(1, math.min(tonumber(Recycle.SellDefaultAmount) or 1, max)),
                                required = true,
                            },
                        },
                    }
                end
                items[#items + 1] = entry
            end
        end

        return items
    end

    local function buildNavigation(items)
        return {{
            id = 'materials',
            label = Kora.lang('recycle.text.sell_materials'),
            icon = 'DollarSign',
            content = {
                title = Kora.lang('recycle.text.sell_materials'),
                blocks = {{ type = 'list', id = 'items', items = items }},
            },
        }}
    end

    local items = buildItems()
    Kora.nui.registerApp({
        id = appId,
        title = 'Recycle Center',
        description = 'Sell your recyclable materials for cash.',
        icon = 'Recycle',
        layout = 'compact',
        width = 450,
        height = 700,
        placement = 'right',
        footer = 'Press Escape to close',
        navigation = buildNavigation(items),

        onAction = function(actionId, context)
            if actionId ~= sellAction then return end

            local itemName = (context.itemId or ''):match('^material:(.+)$')
            local amount = context.value and tonumber(context.value.amount)
            if not itemName or not amount or amount <= 0 or amount ~= math.floor(amount) then
                return { notice = { tone = 'destructive', message = Kora.lang('recycle.error.invalid_amount') } }
            end

            local owned = ownedCount(itemName)
            if owned <= 0 then
                return { notice = { tone = 'destructive', message = Kora.lang('recycle.error.nothing_to_sell') } }
            end
            if amount > maxPerSale(owned) then
                return { notice = { tone = 'destructive', message = Kora.lang('recycle.error.not_enough', maxPerSale(owned)) } }
            end

            TriggerServerEvent('kora_businesses:recycle:sellItem', itemName, amount)
            Kora.nui.closeApp(appId)
            Wait(500) -- let the inventory sync the sale before the counts are rebuilt

            itemList = Kora.callback.trigger('kora_businesses:recycle:getPriceList')
            if not itemList then return end

            local refreshedItems = buildItems()
            if #refreshedItems == 0 then
                Kora.notify.send({ title = 'Recycle Center', message = Kora.lang('recycle.error.nothing_to_sell'), type = 'error' })
                return
            end

            Kora.nui.updateApp(appId, { navigation = buildNavigation(refreshedItems) })
            Kora.nui.openApp(appId)
        end,
    })

    if #items == 0 then
        Kora.notify.send({ title = 'Recycle Center', message = Kora.lang('recycle.error.nothing_to_sell'), type = 'error' })
        return
    end

    Kora.nui.updateApp(appId, { navigation = buildNavigation(items) })
    Kora.nui.openApp(appId)
end

if Recycle.SellMaterials then
    local ped = Kora.entities.create('s_m_m_dockwork_01', vector4(
        Recycle.SellPed.x, Recycle.SellPed.y, Recycle.SellPed.z, Recycle.SellPed.w or 180.0
    ), { freeze = true, invincible = true })

    exports.kora_target:addEntity(ped, {{
        icon = 'fas fa-dollar-sign',
        label = Kora.lang('recycle.text.sell_materials'),
        onSelect = sellMaterials,
    }, {
        icon = 'fas fa-box-open',
        label = Kora.lang('recycle.text.hand_in_package'),
        onSelect = function() if RecycleClient then RecycleClient.handIn() end end,
        canInteract = function()
            return Recycle.HandInAtSellPed ~= false and RecycleClient ~= nil and RecycleClient.canHandIn()
        end,
    }})
end
