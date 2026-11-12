-- Sell menu: owned counts, amount limits, hide-empty option and post-sale refresh.
local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'

local app, opened, sent, notifications = nil, 0, {}, {}
local playerItems = {
    { name = 'metalscrap', amount = 8 }, { name = 'metalscrap', amount = 4 },
    { name = 'glass', amount = 900 },
}
local sellOption

local Kora = {
    lang = function(key, ...) return (select('#', ...) > 0) and (key .. ':' .. table.concat({ ... }, ',')) or key end,
    callback = { trigger = function() return { metalscrap = 2, glass = 2, plastic = 2 } end },
    notify = { send = function(n) notifications[#notifications + 1] = n end },
    entities = { create = function() return 7 end },
    nui = {
        registerApp = function(def) app = def end,
        updateApp = function(_, patch) app.navigation = patch.navigation end,
        openApp = function() opened = opened + 1 end,
        closeApp = function() end,
    },
}
local env = setmetatable({
    Kora = Kora, Kora = Kora,
    Recycle = { SellMaterials = true, SellPed = { x = 0, y = 0, z = 0, w = 0 }, SellDefaultAmount = 1, MaxSellPerRequest = 500 },
    vector4 = function(x, y, z, w) return { x = x, y = y, z = z, w = w } end,
    exports = setmetatable({
        kora_target = { addEntity = function(_, _, opts) sellOption = opts[1] end },
        kora_core = {
            getPlayerData = function() return { items = playerItems } end,
            getShared = function(_, _, name) return { name = name, label = name:upper() } end,
        },
    }, {}),
    TriggerServerEvent = function(name, ...) sent[#sent + 1] = { name = name, args = { ... } } end,
    Wait = function() end,
}, { __index = _G })
assert(loadfile(root .. 'jobs/recycle/sales.lua', 't', env))()
assert(sellOption, 'sell ped registered')

local function rows()
    local out = {}
    for _, row in ipairs(app.navigation[1].content.blocks[1].items) do out[row.id] = row end
    return out
end

sellOption.onSelect()
local list = rows()
assert(list['material:metalscrap'] and list['material:glass'], 'owned materials are listed')
assert(not list['material:plastic'], 'materials with none owned are hidden by default')
assert(list['material:metalscrap'].description:find('recycle.text.owned:12', 1, true), 'row shows total owned across stacks')
assert(list['material:metalscrap'].description:find('recycle.text.price:2', 1, true), 'row keeps the price')
local field = list['material:metalscrap'].action.fields[1]
assert(field.min == 1 and field.max == 12 and field.default == 1, 'amount limited to 1..owned, defaulting to 1')
assert(list['material:glass'].action.fields[1].max == 500, 'form maximum honours MaxSellPerRequest')
assert(list['material:metalscrap'].action.submitLabel == 'recycle.text.sell_submit', 'sell form submit button is labelled from the locale')

local function act(id, amount)
    return app.onAction('kora_businesses:recycle:sellItem', { itemId = id, value = { amount = amount } })
end
for _, bad in ipairs({ 0, -1, 1.5, 'x' }) do
    local result = act('material:metalscrap', bad)
    assert(result and result.notice, 'invalid amount rejected: ' .. tostring(bad))
end
local over = act('material:metalscrap', 13)
assert(over and over.notice and over.notice.message:find('not_enough:12', 1, true), 'amount above owned is refused with the owned count')
assert(act('material:glass', 501).notice, 'amount above the per-sale cap is refused')
assert(act('material:plastic', 1).notice, 'unowned material is refused')
assert(#sent == 0, 'nothing is sent to the server for rejected amounts')

-- Valid sale: server event sent, then the list is rebuilt with fresh counts.
playerItems = { { name = 'metalscrap', amount = 2 } }
opened = 0
act('material:metalscrap', 2)
assert(#sent == 1 and sent[1].args[1] == 'metalscrap' and sent[1].args[2] == 2, 'valid sale reaches the server')
list = rows()
assert(opened == 1 and list['material:metalscrap'].description:find('recycle.text.owned:2', 1, true), 'counts refresh after a sale')
assert(not list['material:glass'], 'sold-out/absent materials drop from the list')

-- SellHideEmpty = false lists empty materials without a sell form.
env.Recycle.SellHideEmpty = false
sellOption.onSelect()
list = rows()
assert(list['material:plastic'] and list['material:plastic'].action == nil, 'empty materials shown without an action when SellHideEmpty is false')
assert(list['material:plastic'].description:find('recycle.text.owned:0', 1, true))

-- Default amount is clamped into 1..owned.
env.Recycle.SellDefaultAmount = 50
sellOption.onSelect()
assert(rows()['material:metalscrap'].action.fields[1].default == 2, 'default amount never exceeds what is owned')

print('kora_businesses recycle sell menu: owned counts, limits, hide-empty and refresh passed')
