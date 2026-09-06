-- The in-game business builder.
--
-- Everything an admin builds here goes straight to the database and out to
-- every connected client: there is no file to write, no snippet to paste and no
-- restart. The dialogs collect a module, the server validates and stores it, and
-- the sync that comes back rebuilds the world.
--
-- World anchors are never typed in. Zones come from qblib's in-world zone
-- creator, props from its placement tool, and "use what is already there" from
-- a camera raycast -- so a till sits exactly where the counter is.

QbBusinesses = QbBusinesses or {}

local S = QbBusinesses.schema
local Client = QbBusinesses.client

local Creator = {}
QbBusinesses.creator = Creator

local isAdmin = false

---@param items table[]
---@param title string
---@return string|nil selectedId
local function pick(items, title)
    local result = QB.nui.openMenu(items, title)
    if not result or result.cancelled then return nil end
    return result.selectedId
end

---@param fields table[]
---@param title string
---@param description? string
---@return table|nil values
local function form(fields, title, description)
    local result = QB.nui.openInputDialog(fields, title, description)
    if not result or result.cancelled then return nil end
    return result.values
end

-- ---------------------------------------------------------------------------
-- Anchors
-- ---------------------------------------------------------------------------

---Converts a `QB.zones.startCreator` result into the flat fields the schema
---stores. The creator speaks in constructor options; the schema speaks in
---plain JSON, and this is the only place the two meet.
---@param result table
---@return table|nil
local function zoneFields(result)
    local opts, fields = result.opts, { zoneType = result.type }
    if result.type == 'sphere' then
        fields.coords = { x = opts.coords.x, y = opts.coords.y, z = opts.coords.z }
        fields.radius = opts.radius
    elseif result.type == 'box' then
        fields.coords = { x = opts.coords.x, y = opts.coords.y, z = opts.coords.z }
        fields.size = { x = opts.size.x, y = opts.size.y, z = opts.size.z }
        fields.rotation = opts.rotation or 0.0
    elseif result.type == 'poly' then
        local points = {}
        for _, point in ipairs(opts.points) do points[#points + 1] = { x = point.x, y = point.y, z = point.z } end
        fields.points = points
        fields.thickness = opts.thickness
        -- A poly has no single centre, so the first point doubles as the
        -- anchor a blip or a distance check needs.
        fields.coords = points[1]
    end
    return fields
end

---Aim at something already in the world and press E. What comes back is a box
---zone sized to that object's own model, because a map prop's model NAME is not
---recoverable from its hash at runtime -- only its dimensions are.
---@return table|nil
local function pickExisting()
    local prompt = QB.textui.show('Look at the object and press ~b~E~s~ -- ~r~Backspace~s~ to cancel')
    local fields

    while true do
        Wait(0)
        local hit, coords, entity = QB.raycast.fromCamera(25.0)
        if hit and entity and entity ~= 0 then
            DrawMarker(28, coords.x, coords.y, coords.z, 0, 0, 0, 0, 0, 0, 0.2, 0.2, 0.2, 0, 200, 120, 120, false, false, 2, nil, nil, false)
        end

        if IsControlJustReleased(0, 202) then break end

        if IsControlJustReleased(0, 38) and hit and entity and entity ~= 0 then
            local min, max = GetModelDimensions(GetEntityModel(entity))
            local position = GetEntityCoords(entity)
            fields = {
                zoneType = 'box',
                coords = { x = position.x, y = position.y, z = position.z + ((max.z - min.z) / 2) },
                size = { x = max.x - min.x, y = max.y - min.y, z = max.z - min.z },
                rotation = GetEntityHeading(entity),
            }
            break
        end
    end

    QB.textui.hide(prompt)
    return fields
end

---@param modelType 'ped'|'object'|'vehicle'
---@return table|nil
local function pickEntity(modelType)
    local values = form({
        { id = 'model', label = 'Model name', type = 'text', required = true },
    }, ('Place a %s'):format(modelType))
    if not values then return nil end

    local model = tostring(values.model)
    if not IsModelValid(joaat(model)) then
        Client.notify(('"%s" is not a valid model.'):format(model), 'error')
        return nil
    end

    local placement = QB.placement.start(model)
    if not placement then return nil end

    return {
        model = { model = model, modelType = modelType },
        coords = { {
            x = placement.coords.x, y = placement.coords.y, z = placement.coords.z,
            w = placement.heading or 0.0,
        } },
    }
end

---@param allowed 'zone'|'model'|'any'
---@return table|nil fields
local function pickAnchor(allowed)
    local choices = {}
    if allowed ~= 'model' then
        choices[#choices + 1] = { id = 'sphere', label = 'Sphere zone', description = 'A radius around a point' }
        choices[#choices + 1] = { id = 'box', label = 'Box zone', description = 'A rotatable box' }
        choices[#choices + 1] = { id = 'poly', label = 'Poly zone', description = 'A drawn footprint' }
        choices[#choices + 1] = { id = 'existing', label = 'An object already here', description = 'Aim at it and press E' }
    end
    if allowed ~= 'zone' then
        choices[#choices + 1] = { id = 'object', label = 'Place a prop', description = 'Spawn and position an object' }
        choices[#choices + 1] = { id = 'ped', label = 'Place a ped' }
        choices[#choices + 1] = { id = 'vehicle', label = 'Place a vehicle' }
    end

    local kind = pick(choices, 'Where is it?')
    if not kind then return nil end

    if kind == 'existing' then return pickExisting() end
    if kind == 'object' or kind == 'ped' or kind == 'vehicle' then return pickEntity(kind) end

    local result = QB.zones.startCreator(kind)
    if not result then return nil end
    return zoneFields(result)
end

---@return table|nil
local function pickBlip()
    local values = form({
        { id = 'wanted', label = 'Add a map blip?', type = 'checkbox' },
    }, 'Map blip')
    if not values or not values.wanted then return nil end

    local blip = form({
        { id = 'label', label = 'Blip name', type = 'text' },
        { id = 'sprite', label = 'Sprite', type = 'number', default = 1, min = 0, max = 900 },
        { id = 'color', label = 'Colour', type = 'number', default = 1, min = 0, max = 90 },
        { id = 'scale', label = 'Scale', type = 'number', default = 0.7, min = 0.1, max = 3.0 },
    }, 'Map blip')
    if not blip then return nil end

    return {
        enabled = true, label = blip.label, sprite = blip.sprite,
        color = blip.color, scale = blip.scale,
    }
end

-- ---------------------------------------------------------------------------
-- Per-type field collection
-- ---------------------------------------------------------------------------

local fieldsFor = {}

fieldsFor.Zone = function()
    local values = form({
        { id = 'controlDuty', label = 'Clock staff on and off automatically', type = 'checkbox', default = true },
    }, 'Business perimeter')
    if not values then return nil end
    return { controlDuty = values.controlDuty }
end

fieldsFor.Blip = function()
    local values = form({
        { id = 'label', label = 'Blip name', type = 'text', required = true },
        { id = 'sprite', label = 'Sprite', type = 'number', default = 1, min = 0, max = 900 },
        { id = 'color', label = 'Colour', type = 'number', default = 1, min = 0, max = 90 },
        { id = 'scale', label = 'Scale', type = 'number', default = 0.7, min = 0.1, max = 3.0 },
    }, 'Map blip')
    if not values then return nil end
    local coords = GetEntityCoords(PlayerPedId())
    return {
        label = values.label, sprite = values.sprite, color = values.color, scale = values.scale,
        coords = { x = coords.x, y = coords.y, z = coords.z },
    }
end

fieldsFor.StaticEntity = function() return {} end
fieldsFor.BossMenu = function() return {} end

fieldsFor.Stash = function(business)
    local values = form({
        { id = 'label', label = 'Label', type = 'text', required = true, default = 'Stash' },
        { id = 'id', label = 'Stash id', type = 'text', required = true, default = business.id .. '_stash' },
        { id = 'slots', label = 'Slots', type = 'number', default = Config.stash.slots, min = 1, max = 500 },
        { id = 'weight', label = 'Max weight (grams)', type = 'number', default = Config.stash.weight, min = 1000 },
        { id = 'public', label = 'Anyone may open it', type = 'checkbox' },
    }, 'Stash')
    if not values then return nil end
    return values
end

fieldsFor.POS = function(business)
    local lists = {}
    for name in pairs(Config.shopItems) do lists[#lists + 1] = { value = name, label = name } end
    table.sort(lists, function(a, b) return a.label < b.label end)

    local values = form({
        { id = 'label', label = 'Label', type = 'text', required = true, default = 'Till' },
        { id = 'id', label = 'Till id', type = 'text', required = true, default = business.id .. '_till' },
        { id = 'items', label = 'Stock list', type = 'select', options = lists,
          placeholder = 'Leave empty to allow any item' },
        { id = 'commission', label = 'Sold-stock commission (%)', type = 'number', default = 0, min = 0, max = 100 },
        { id = 'tax', label = 'Sales tax (%)', type = 'number', default = 0, min = 0, max = 100 },
        { id = 'hideWhenStaffed', label = 'Customers cannot self-serve while staff are here', type = 'checkbox' },
        { id = 'panicButton', label = 'Panic button', type = 'checkbox' },
        { id = 'webhook', label = 'Discord webhook (optional)', type = 'text' },
    }, 'Point of sale')
    if not values then return nil end

    return {
        label = values.label, id = values.id,
        items = values.items ~= nil and values.items ~= '' and { values.items } or {},
        commission = values.commission, tax = values.tax,
        hideWhenStaffed = values.hideWhenStaffed, panicButton = values.panicButton,
        webhook = values.webhook ~= '' and values.webhook or nil,
    }
end

fieldsFor.Crafting = function()
    local recipes = {}
    for id, recipe in pairs(Config.recipes) do
        recipes[#recipes + 1] = { value = id, label = recipe.label or id }
    end
    table.sort(recipes, function(a, b) return a.label < b.label end)
    if #recipes == 0 then
        Client.notify('No recipes are configured. Add one in shared/recipes/ first.', 'error')
        return nil
    end

    local values = form({
        { id = 'label', label = 'Label', type = 'text', required = true, default = 'Crafting' },
        { id = 'public', label = 'Anyone may use it', type = 'checkbox' },
    }, 'Crafting bench')
    if not values then return nil end

    -- A multi-select field does not exist, so the bench is filled one recipe at
    -- a time. Cancelling the picker finishes the list rather than aborting.
    local chosen, taken = {}, {}
    while true do
        local options = {}
        for _, recipe in ipairs(recipes) do
            if not taken[recipe.value] then
                options[#options + 1] = { id = recipe.value, label = recipe.label }
            end
        end
        if #options == 0 then break end
        options[#options + 1] = { id = '__done', label = ('Done (%d selected)'):format(#chosen), icon = 'Check' }

        local choice = pick(options, 'Add a recipe')
        if not choice or choice == '__done' then break end
        taken[choice] = true
        chosen[#chosen + 1] = choice
    end

    if #chosen == 0 then
        Client.notify('A bench needs at least one recipe.', 'error')
        return nil
    end
    return { label = values.label, public = values.public, recipes = chosen }
end

fieldsFor.UseableItem = function()
    local values = form({
        { id = 'item', label = 'Item name', type = 'text', required = true },
        { id = 'useType', label = 'What happens', type = 'select', required = true, options = {
            { value = 'reward', label = 'Give a random reward' },
            { value = 'recipe', label = 'Run a recipe' },
        } },
        { id = 'consume', label = 'Items consumed per use', type = 'number', default = 1, min = 0, max = 100 },
    }, 'Useable item')
    if not values then return nil end

    if values.useType == 'recipe' then
        local recipes = {}
        for id, recipe in pairs(Config.recipes) do recipes[#recipes + 1] = { id = id, label = recipe.label or id } end
        table.sort(recipes, function(a, b) return a.label < b.label end)
        local recipe = pick(recipes, 'Which recipe?')
        if not recipe then return nil end
        return { item = values.item, useType = 'recipe', consume = values.consume, recipe = recipe }
    end

    local rewards = {}
    while true do
        local reward = form({
            { id = 'item', label = ('Reward item #%d'):format(#rewards + 1), type = 'text', required = #rewards == 0 },
            { id = 'amount', label = 'Amount', type = 'number', default = 1, min = 1, max = 1000 },
            { id = 'chance', label = 'Relative weight', type = 'number', default = 1, min = 0.01 },
        }, 'Rewards', 'Leave the item blank to finish.')
        if not reward or not reward.item or reward.item == '' then break end
        rewards[#rewards + 1] = { item = reward.item, amount = reward.amount, chance = reward.chance }
    end

    if #rewards == 0 then
        Client.notify('A reward item needs at least one reward.', 'error')
        return nil
    end
    return { item = values.item, useType = 'reward', consume = values.consume, rewards = rewards }
end

-- ---------------------------------------------------------------------------
-- Module editing
-- ---------------------------------------------------------------------------

---@param business table
---@param index? integer nil to append a new module
---@param moduleType? string
local function editModule(business, index, moduleType)
    if not moduleType then
        local options = {}
        for _, descriptor in ipairs(S.moduleTypes) do
            options[#options + 1] = { id = descriptor.type, label = descriptor.label }
        end
        moduleType = pick(options, 'Add a module')
        if not moduleType then return end
    end

    local descriptor = S.moduleType[moduleType]
    local payload = fieldsFor[moduleType](business)
    if not payload then return end
    payload.moduleType = moduleType

    if descriptor.interaction ~= 'none' then
        local anchor = pickAnchor(descriptor.interaction)
        if not anchor then return end
        for key, value in pairs(anchor) do payload[key] = value end
    end

    if descriptor.interaction ~= 'none' and moduleType ~= 'Zone' then
        local blip = pickBlip()
        if blip then payload.blip = blip end
    end

    local ok, err = QB.callback.trigger('qbbusinesses:server:saveModule', business.id, index, payload)
    Client.notify(ok and 'Module saved. It is live now.' or (err or 'That module was rejected.'), ok and 'success' or 'error')
end

---@param business table
local function manageModules(business)
    while true do
        local definition = Client.definitions[business.id]
        if not definition then return end

        local options = { { id = '__add', label = 'Add a module', icon = 'Plus' } }
        for index, module in ipairs(definition.modules) do
            options[#options + 1] = {
                id = tostring(index),
                label = ('%d. %s'):format(index, module.label),
                description = module.moduleType,
            }
        end

        local choice = pick(options, ('%s modules'):format(definition.label))
        if not choice then return end

        if choice == '__add' then
            editModule(definition)
        else
            local index = tonumber(choice)
            local module = definition.modules[index]
            local action = pick({
                { id = 'edit', label = 'Rebuild this module', description = 'Re-enter every field and reposition it' },
                { id = 'remove', label = 'Delete this module', icon = 'Trash2' },
            }, module.label)

            if action == 'edit' then
                editModule(definition, index, module.moduleType)
            elseif action == 'remove' then
                local confirm = QB.nui.openAlert({
                    title = 'Delete module', destructive = true,
                    message = ('Delete "%s" from %s?'):format(module.label, definition.label),
                    confirmLabel = 'Delete',
                })
                if confirm and confirm.confirmed then
                    local ok, err = QB.callback.trigger('qbbusinesses:server:removeModule', definition.id, index)
                    Client.notify(ok and 'Module deleted.' or (err or 'Could not delete that.'), ok and 'success' or 'error')
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Business management
-- ---------------------------------------------------------------------------

---@param businessId string
local function showLogs(businessId)
    local rows, err = QB.callback.trigger('qbbusinesses:server:logs', businessId, 50)
    if not rows then return Client.notify(err or 'You cannot read those logs.', 'error') end
    if #rows == 0 then return Client.notify('Nothing has happened here yet.', 'info') end

    local items = {}
    for _, row in ipairs(rows) do
        items[#items + 1] = {
            id = tostring(#items + 1),
            label = row.message,
            description = ('%s -- %s'):format(row.category, tostring(row.created_at)),
        }
    end
    QB.nui.openMenu(items, 'Recent activity')
end

---@param businessId string
local function manage(businessId)
    while true do
        local business = Client.definitions[businessId]
        if not business then return end

        local options = {
            { id = 'logs', label = 'Recent activity', icon = 'ScrollText' },
            { id = 'balance', label = 'Business balance', icon = 'Wallet' },
        }
        if isAdmin then
            options[#options + 1] = { id = 'modules', label = 'Modules', icon = 'Blocks', description = ('%d configured'):format(#business.modules) }
            options[#options + 1] = { id = 'details', label = 'Rename or reassign', icon = 'Pencil' }
            options[#options + 1] = { id = 'delete', label = 'Delete this business', icon = 'Trash2' }
        end

        local choice = pick(options, business.label)
        if not choice then return end

        if choice == 'logs' then
            showLogs(businessId)
        elseif choice == 'balance' then
            local balance, err = QB.callback.trigger('qbbusinesses:server:balance', businessId)
            Client.notify(balance and ('Business balance: $%d'):format(balance) or (err or 'No balance available.'),
                balance and 'info' or 'error')
        elseif choice == 'modules' then
            manageModules(business)
        elseif choice == 'details' then
            local jobs = QB.callback.trigger('qbbusinesses:server:jobs')
            local options2 = {}
            for _, job in ipairs(jobs or {}) do options2[#options2 + 1] = { value = job.value, label = job.label } end
            local values = form({
                { id = 'label', label = 'Name', type = 'text', required = true, default = business.label },
                { id = 'job', label = 'Job', type = 'select', required = true, options = options2, default = business.job },
            }, 'Business details')
            if values then
                local ok, err = QB.callback.trigger('qbbusinesses:server:editBusiness', businessId, values)
                Client.notify(ok and 'Business updated.' or (err or 'That change was rejected.'), ok and 'success' or 'error')
            end
        elseif choice == 'delete' then
            local confirm = QB.nui.openAlert({
                title = 'Delete business', destructive = true,
                message = ('Delete %s and every module it owns? Stashes and till stock are left untouched.'):format(business.label),
                confirmLabel = 'Delete',
            })
            if confirm and confirm.confirmed then
                local ok, err = QB.callback.trigger('qbbusinesses:server:deleteBusiness', businessId)
                Client.notify(ok and 'Business deleted.' or (err or 'Could not delete it.'), ok and 'success' or 'error')
                if ok then return end
            end
        end
    end
end

local function createBusiness()
    local jobs = QB.callback.trigger('qbbusinesses:server:jobs')
    if not jobs or #jobs == 0 then return Client.notify('No jobs are available.', 'error') end

    local options = {}
    for _, job in ipairs(jobs) do options[#options + 1] = { value = job.value, label = job.label } end

    local values = form({
        { id = 'label', label = 'Business name', type = 'text', required = true },
        { id = 'job', label = 'Job', type = 'select', required = true, options = options },
    }, 'New business', 'The id is derived from the name and cannot be changed later.')
    if not values then return end

    local id, err = QB.callback.trigger('qbbusinesses:server:createBusiness', values)
    if not id then return Client.notify(err or 'Could not create that business.', 'error') end

    Client.notify('Business created. Add its perimeter next.', 'success')
    -- Straight into the module builder: a business with no modules does nothing
    -- at all, and the very next thing anyone wants is its zone.
    local business = Client.definitions[id]
    if business then manageModules(business) end
end

function Creator.open()
    local options = {}
    if isAdmin then
        options[#options + 1] = { id = '__new', label = 'Create a business', icon = 'Plus' }
    end

    local sorted = {}
    for _, business in pairs(Client.definitions) do sorted[#sorted + 1] = business end
    table.sort(sorted, function(a, b) return a.label < b.label end)

    for _, business in ipairs(sorted) do
        if isAdmin or Client.isBoss(business) then
            options[#options + 1] = {
                id = business.id, label = business.label,
                description = ('%s -- %d module(s)'):format(business.job, #business.modules),
            }
        end
    end

    if #options == 0 then return Client.notify('You do not manage any business.', 'error') end

    local choice = pick(options, 'Businesses')
    if not choice then return end
    if choice == '__new' then return createBusiness() end
    manage(choice)
end

---@param value boolean
function Creator.setAdmin(value) isAdmin = value == true end

RegisterCommand(Config.command, function() Creator.open() end, false)
