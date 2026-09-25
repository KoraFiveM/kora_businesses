local sharedItems = exports['qb-core']:GetShared('Items')

local function hasItem(item)
    return exports['qb-inventory']:HasItem(item)
end

local function sellMaterials()
    local itemList = QB.callback.trigger('qb-recyclejob:server:getPriceList')
    if not itemList then
        QB.notify.send({ title = 'Recycle Center', message = QB.lang('recycle.error.too_far_to_sell'), type = 'error' })
        return
    end

    local appId, sellAction = 'qb-recyclejob:sell', 'qb-recyclejob:sellItem'

    local function buildItems()
        local items = {}

        for itemName, price in pairs(itemList) do
            if hasItem(itemName) then
                local item = sharedItems[itemName] or { name = itemName, label = itemName }

                items[#items + 1] = {
                    id = 'material:' .. itemName,
                    label = item.label,
                    description = QB.lang('recycle.text.price', price),
                    image = 'nui://qbinventory/images/' .. item.image,
                    action = {
                        id = sellAction,
                        label = QB.lang('recycle.text.sell'),
                        fields = {
                            { id = 'amount', label = QB.lang('recycle.text.amount'), type = 'number', min = 1, required = true },
                        },
                    },
                }
            end
        end

        return items
    end

    local function buildNavigation()
        return {{
            id = 'materials',
            label = QB.lang('recycle.text.sell_materials'),
            icon = 'DollarSign',
            content = {
                title = QB.lang('recycle.text.sell_materials'),
                blocks = {{ type = 'list', id = 'items', items = buildItems() }},
            },
        }}
    end

    QB.nui.registerApp({
        id = appId,
        title = 'Recycle Center',
        description = 'Sell your recyclable materials for cash.',
        icon = 'Recycle',
        layout = 'compact',
        width = 450,
        height = 700,
        placement = 'right',
        footer = 'Press Escape to close',
        navigation = buildNavigation(),

        onAction = function(actionId, context)
            if actionId ~= sellAction then return end

            local itemName = (context.itemId or ''):match('^material:(.+)$')
            local amount = context.value and tonumber(context.value.amount)
            if not itemName or not amount or amount <= 0 then
                return { notice = { tone = 'destructive', message = QB.lang('recycle.error.invalid_amount') or 'Enter a valid amount.' } }
            end

            TriggerServerEvent('qb-recyclejob:server:sellItem', itemName, amount)
            QB.nui.closeApp(appId)

            itemList = QB.callback.trigger('qb-recyclejob:server:getPriceList')
            if not itemList then return end

            if #buildItems() == 0 then
                QB.notify.send({ title = 'Recycle Center', message = QB.lang('recycle.error.nothing_to_sell'), type = 'error' })
                return
            end

            QB.nui.updateApp(appId, { navigation = buildNavigation() })
            QB.nui.openApp(appId)
        end,
    })

    if #buildItems() == 0 then
        QB.notify.send({ title = 'Recycle Center', message = QB.lang('recycle.error.nothing_to_sell'), type = 'error' })
        return
    end

    QB.nui.updateApp(appId, { navigation = buildNavigation() })
    QB.nui.openApp(appId)
end

if Recycle.SellMaterials then
    QB.stream.loadModel('s_m_m_dockwork_01')

    local ped = QB.entities.create('s_m_m_dockwork_01', vector4(
        Recycle.SellPed.x, Recycle.SellPed.y, Recycle.SellPed.z, Recycle.SellPed.w or 180.0
    ), { freeze = true, invincible = true })

    exports.qbtarget:addEntity(ped, {{
        icon = 'fas fa-dollar-sign',
        label = QB.lang('recycle.text.sell_materials'),
        onSelect = sellMaterials,
    }})
end
