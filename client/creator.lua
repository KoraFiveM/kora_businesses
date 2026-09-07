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
        {
            id = 'recipes', label = 'Recipes', type = 'multiselect', required = true,
            description = 'Select every recipe this bench should offer.', options = recipes,
        },
    }, 'Crafting bench')
    if not values then return nil end
    return { label = values.label, public = values.public, recipes = values.recipes }
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
---@return boolean? saved
---@return integer? position
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

    local ok, result = QB.callback.trigger('qbbusinesses:server:saveModule', business.id, index, payload)
    Client.notify(ok and 'Module saved. It is live now.' or (result or 'That module was rejected.'), ok and 'success' or 'error')
    return ok == true, ok and tonumber(result) or nil
end

-- ---------------------------------------------------------------------------
-- Business management
-- ---------------------------------------------------------------------------

local APP_ID = 'qbbusinesses:management'
local openManagement
local currentState

local logTones = {
    admin = 'primary', sale = 'success', stock = 'success', payment = 'warning',
    craft = 'primary', panic = 'destructive',
}

---@param amount any
---@return string
local function money(amount)
    return ('$%d'):format(math.floor(tonumber(amount) or 0))
end

---@param businessId string
---@param previousRev? string
---@return table|nil business
local function awaitBusiness(businessId, previousRev)
    for _ = 1, 40 do
        local business = Client.definitions[businessId]
        if business and (not previousRev or business.rev ~= previousRev) then return business end
        Wait(50)
    end
    return Client.definitions[businessId]
end

---@param state table
local function loadBusinessSummary(state)
    state.balance, state.balanceError, state.logs, state.logsError = nil, nil, {}, nil
    if not state.businessId or not Client.definitions[state.businessId] then return end

    local balance, balanceError = QB.callback.trigger('qbbusinesses:server:balance', state.businessId)
    if balance ~= nil then state.balance = balance else state.balanceError = balanceError end

    local logs, logsError = QB.callback.trigger('qbbusinesses:server:logs', state.businessId, 50)
    if type(logs) == 'table' then state.logs = logs else state.logsError = logsError end
end

---@return table[] businesses
local function manageableBusinesses()
    local businesses = {}
    for _, business in pairs(Client.definitions) do
        if isAdmin or Client.isBoss(business) then businesses[#businesses + 1] = business end
    end
    table.sort(businesses, function(a, b) return a.label < b.label end)
    return businesses
end

---@param module table
---@return string
local function anchorLabel(module)
    local coords = module.zoneType and module.coords or (module.coords and module.coords[1])
    if not coords then return 'No world anchor' end
    return ('%.1f, %.1f, %.1f'):format(coords.x or 0.0, coords.y or 0.0, coords.z or 0.0)
end

---@param state table
---@return table definition
local function appDefinition(state)
    local businessCards = {}
    for _, business in ipairs(manageableBusinesses()) do
        businessCards[#businessCards + 1] = {
            id = business.id,
            label = business.label,
            description = business.job,
            icon = 'building-2',
            badge = #business.modules,
            tone = business.id == state.businessId and 'primary' or 'neutral',
            action = 'businesses:select',
            metadata = {
                { label = 'Job', value = business.job },
                { label = 'Modules', value = #business.modules },
                { label = 'Staff present', value = Client.staff[business.id] or 0,
                    tone = (Client.staff[business.id] or 0) > 0 and 'success' or 'neutral' },
            },
        }
    end

    local directoryActions = {}
    if isAdmin and #state.jobs > 0 then
        directoryActions[#directoryActions + 1] = {
            id = 'businesses:create', label = 'Create business', icon = 'plus',
            variant = 'primary', closeBeforeAction = true,
            fields = {
                { id = 'label', label = 'Business name', type = 'text', required = true, maxLength = 128 },
                { id = 'job', label = 'Job', type = 'select', required = true, options = state.jobs },
            },
            confirm = 'Create this business, then place its first module?',
        }
    end

    local navigation = {
        {
            id = 'businesses', label = 'Businesses', icon = 'building-2', badge = #businessCards,
            content = {
                title = 'Business directory',
                description = isAdmin and 'Open a business to manage its modules and activity.'
                    or 'Businesses where your current grade has management access.',
                actions = directoryActions,
                blocks = {
                    {
                        type = 'list', id = 'business-directory', layout = 'cards', searchable = true,
                        pageSize = 8, searchPlaceholder = 'Search businesses or jobs…', items = businessCards,
                        empty = isAdmin and 'No businesses exist yet.' or 'You do not manage any business.',
                    },
                },
            },
        },
    }

    local business = state.businessId and Client.definitions[state.businessId]
    if business and (isAdmin or Client.isBoss(business)) then
        local overviewActions = {
            { id = 'businesses:refresh', label = 'Refresh', icon = 'refresh-cw', variant = 'outline' },
        }
        if isAdmin and #state.jobs > 0 then
            overviewActions[#overviewActions + 1] = {
                id = 'businesses:edit', label = 'Rename or reassign', icon = 'pencil',
                fields = {
                    { id = 'label', label = 'Name', type = 'text', required = true,
                        default = business.label, maxLength = 128 },
                    { id = 'job', label = 'Job', type = 'select', required = true,
                        options = state.jobs, default = business.job },
                },
            }
            overviewActions[#overviewActions + 1] = {
                id = 'businesses:delete', label = 'Delete business', icon = 'trash-2',
                variant = 'destructive',
                confirm = ('Delete %s and every module it owns? Stashes and till stock are left untouched.'):format(business.label),
            }
        end

        local moduleCards = {}
        for index, module in ipairs(business.modules) do
            moduleCards[#moduleCards + 1] = {
                id = tostring(index),
                label = module.label,
                description = module.moduleType,
                icon = module.moduleType == 'Zone' and 'scan' or 'blocks',
                badge = index,
                tone = index == state.moduleIndex and 'primary' or 'neutral',
                action = 'businesses:select-module',
                metadata = {
                    { label = 'Anchor', value = anchorLabel(module) },
                    { label = 'Access', value = module.public and 'Public' or 'Job restricted' },
                    { label = 'Interaction', value = S.moduleType[module.moduleType].interaction },
                },
                actions = {
                    {
                        id = 'businesses:edit-module', label = 'Rebuild', icon = 'pencil-ruler',
                        closeBeforeAction = true,
                    },
                    {
                        id = 'businesses:remove-module', label = 'Delete', icon = 'trash-2',
                        variant = 'destructive', confirm = ('Delete "%s"?'):format(module.label),
                    },
                },
            }
        end

        local moduleBlocks = {
            {
                type = 'list', id = 'business-modules', layout = 'cards', searchable = true,
                pageSize = 8, searchPlaceholder = 'Search modules…', items = moduleCards,
                empty = 'No modules are configured. Add a perimeter first.',
            },
        }
        local selectedModule = business.modules[state.moduleIndex or 0]
        if selectedModule then
            moduleBlocks[#moduleBlocks + 1] = {
                type = 'details', title = ('Module %d · %s'):format(state.moduleIndex, selectedModule.label),
                columns = 2,
                items = {
                    { label = 'Type', value = selectedModule.moduleType, tone = 'primary' },
                    { label = 'Interaction', value = S.moduleType[selectedModule.moduleType].interaction },
                    { label = 'World anchor', value = anchorLabel(selectedModule) },
                    { label = 'Distance', value = selectedModule.distance or 'Default' },
                    { label = 'Access', value = selectedModule.public and 'Public' or business.job },
                    { label = 'Map blip', value = selectedModule.blip and 'Enabled' or 'None' },
                },
            }
        end

        local activity = {}
        for index, row in ipairs(state.logs or {}) do
            activity[#activity + 1] = {
                id = tostring(row.id or index),
                title = row.message or 'Business activity',
                timestamp = tostring(row.created_at or ''),
                tone = logTones[row.category] or 'neutral',
                icon = row.category == 'admin' and 'settings' or 'history',
                metadata = {
                    { label = 'Category', value = row.category or 'activity' },
                    { label = 'Amount', value = row.amount and money(row.amount) or '—' },
                },
            }
        end

        local tabs = {
            {
                id = 'overview', label = 'Overview', content = {
                    title = business.label, description = 'Live business status and ownership.',
                    actions = overviewActions,
                    blocks = {
                        { type = 'stats', items = {
                            { label = 'Balance', value = state.balance ~= nil and money(state.balance) or 'Unavailable',
                                description = state.balanceError, icon = 'wallet', tone = state.balance ~= nil and 'success' or 'warning' },
                            { label = 'Modules', value = #business.modules, icon = 'blocks', tone = 'primary' },
                            { label = 'Staff present', value = Client.staff[business.id] or 0, icon = 'users' },
                        } },
                        { type = 'details', title = 'Business details', columns = 2, items = {
                            { label = 'Business id', value = business.id },
                            { label = 'Job', value = business.job },
                            { label = 'Revision', value = business.rev or 'Pending' },
                            { label = 'Management', value = isAdmin and 'Administrator' or 'Job boss' },
                        } },
                    },
                },
            },
            {
                id = 'activity', label = 'Activity', badge = #activity, content = {
                    title = 'Recent activity', description = state.logsError,
                    blocks = { { type = 'timeline', title = 'Audit trail', items = activity,
                        empty = state.logsError or 'Nothing has happened here yet.' } },
                },
            },
        }
        if isAdmin then
            table.insert(tabs, 2, {
                id = 'modules', label = 'Modules', badge = #moduleCards, content = {
                    title = 'Module overview',
                    description = 'World editors close this console and reopen it on the same business and module.',
                    actions = {
                        {
                            id = 'businesses:add-module', label = 'Add module', icon = 'plus',
                            variant = 'primary', closeBeforeAction = true,
                        },
                    },
                    blocks = moduleBlocks,
                },
            })
        end

        navigation[#navigation + 1] = {
            id = 'management', label = business.label, description = business.job,
            icon = 'layout-dashboard', defaultTab = state.moduleIndex and 'modules' or 'overview', tabs = tabs,
        }
    end

    return {
        id = APP_ID,
        title = 'Business management',
        description = business and business.label or 'Live business directory',
        icon = 'building-2',
        width = 1200,
        height = 800,
        navigation = navigation,
        footer = 'Data, permissions, and mutations are validated by the qbbusinesses server.',
    }
end

---@param state table
---@return table update
local function appUpdate(state)
    local definition = appDefinition(state)
    return {
        title = definition.title,
        description = definition.description,
        navigation = definition.navigation,
        footer = definition.footer,
    }
end

---@param state table
---@param businessId string
---@param index? integer
---@param moduleType? string
local function launchModuleEditor(state, businessId, index, moduleType)
    CreateThread(function()
        local business = Client.definitions[businessId]
        if not business then
            Client.notify('That business no longer exists.', 'error')
            state.businessId, state.moduleIndex = nil, nil
            return openManagement(state, 'businesses')
        end

        local previousRev = business.rev
        local saved, position = editModule(business, index, moduleType)
        if saved then
            awaitBusiness(businessId, previousRev)
            state.moduleIndex = position or index
        else
            state.moduleIndex = index
        end
        state.businessId = businessId
        loadBusinessSummary(state)
        openManagement(state, 'management', 'modules')
    end)
end

---@param state table
---@param values table
local function createBusinessAndResume(state, values)
    CreateThread(function()
        local businessId, err = QB.callback.trigger('qbbusinesses:server:createBusiness', values)
        if not businessId then
            Client.notify(err or 'Could not create that business.', 'error')
            return openManagement(state, 'businesses')
        end

        local business = awaitBusiness(businessId)
        if not business then
            Client.notify('Business saved, but its live definition has not arrived yet.', 'warning')
            return openManagement(state, 'businesses')
        end

        state.businessId, state.moduleIndex = businessId, nil
        Client.notify('Business created. Add its perimeter next.', 'success')
        local previousRev = business.rev
        local saved, position = editModule(business)
        if saved then
            awaitBusiness(businessId, previousRev)
            state.moduleIndex = position
        end
        loadBusinessSummary(state)
        openManagement(state, 'management', 'modules')
    end)
end

---@param state table
---@return function
local function actionHandler(state)
    return function(actionId, context)
        local itemId = context and context.itemId
        local values = type(context and context.value) == 'table' and context.value or {}

        if actionId == 'businesses:select' then
            local business = itemId and Client.definitions[itemId]
            if not business or not (isAdmin or Client.isBoss(business)) then
                return { notice = { tone = 'destructive', message = 'That business is no longer available.' } }
            end
            state.businessId, state.moduleIndex = business.id, nil
            loadBusinessSummary(state)
            return { update = appUpdate(state), navigate = { viewId = 'management', tabId = 'overview' } }
        end

        if actionId == 'businesses:create' then
            createBusinessAndResume(state, { label = values.label, job = values.job })
            return
        end

        local business = state.businessId and Client.definitions[state.businessId]
        if not business or not (isAdmin or Client.isBoss(business)) then
            return { notice = { tone = 'destructive', message = 'That business is no longer available.' } }
        end

        if actionId == 'businesses:refresh' then
            loadBusinessSummary(state)
            return { update = appUpdate(state), notice = { tone = 'success', message = 'Business data refreshed.' } }
        elseif actionId == 'businesses:select-module' then
            local index = math.floor(tonumber(itemId) or 0)
            if not business.modules[index] then
                return { notice = { tone = 'destructive', message = 'That module no longer exists.' } }
            end
            state.moduleIndex = index
            return { update = appUpdate(state), navigate = { viewId = 'management', tabId = 'modules', replace = true } }
        elseif actionId == 'businesses:add-module' then
            launchModuleEditor(state, business.id)
            return
        elseif actionId == 'businesses:edit-module' then
            local index = math.floor(tonumber(itemId) or 0)
            local module = business.modules[index]
            if not module then error('That module no longer exists.') end
            launchModuleEditor(state, business.id, index, module.moduleType)
            return
        elseif actionId == 'businesses:remove-module' then
            local index = math.floor(tonumber(itemId) or 0)
            if not business.modules[index] then
                return { notice = { tone = 'destructive', message = 'That module no longer exists.' } }
            end
            local previousRev = business.rev
            local ok, err = QB.callback.trigger('qbbusinesses:server:removeModule', business.id, index)
            if not ok then return { notice = { tone = 'destructive', message = err or 'Could not delete that module.' } } end
            awaitBusiness(business.id, previousRev)
            state.moduleIndex = nil
            loadBusinessSummary(state)
            return { update = appUpdate(state), notice = { tone = 'success', message = 'Module deleted.' } }
        elseif actionId == 'businesses:edit' then
            local previousRev = business.rev
            local ok, err = QB.callback.trigger('qbbusinesses:server:editBusiness', business.id, {
                label = values.label, job = values.job,
            })
            if not ok then return { notice = { tone = 'destructive', message = err or 'That change was rejected.' } } end
            awaitBusiness(business.id, previousRev)
            loadBusinessSummary(state)
            return { update = appUpdate(state), notice = { tone = 'success', message = 'Business updated.' } }
        elseif actionId == 'businesses:delete' then
            local ok, err = QB.callback.trigger('qbbusinesses:server:deleteBusiness', business.id)
            if not ok then return { notice = { tone = 'destructive', message = err or 'Could not delete that business.' } } end
            state.businessId, state.moduleIndex, state.balance, state.logs = nil, nil, nil, {}
            return {
                update = appUpdate(state), navigate = { viewId = 'businesses', replace = true },
                notice = { tone = 'success', message = 'Business deleted.' },
            }
        end

        error('That business action is no longer available.')
    end
end

---@param state table
---@param viewId? string
---@param tabId? string
openManagement = function(state, viewId, tabId)
    local definition = appDefinition(state)
    definition.onAction = actionHandler(state)
    QB.nui.registerApp(definition)
    currentState = state
    QB.nui.openApp(APP_ID, { viewId = viewId, tabId = tabId })
    if currentState == state then currentState = nil end
end

---Refreshes an open console after the replicated business or staff snapshots
---change. It deliberately does not call the server from a net-event handler;
---the explicit Refresh action owns balance/log fetching.
---@return boolean updated
function Creator.refresh()
    if not currentState or not QB.nui.isAppOpen(APP_ID) then return false end
    local business = currentState.businessId and Client.definitions[currentState.businessId]
    if currentState.businessId and (not business or not (isAdmin or Client.isBoss(business))) then
        currentState.businessId, currentState.moduleIndex = nil, nil
    elseif business and currentState.moduleIndex and not business.modules[currentState.moduleIndex] then
        currentState.moduleIndex = nil
    end
    return QB.nui.updateApp(APP_ID, appUpdate(currentState))
end

function Creator.open()
    if QB.nui.isAppOpen(APP_ID) then return end

    local businesses = manageableBusinesses()
    if not isAdmin and #businesses == 0 then
        return Client.notify('You do not manage any business.', 'error')
    end

    CreateThread(function()
        local jobs = {}
        if isAdmin then
            local result, err = QB.callback.trigger('qbbusinesses:server:jobs')
            if type(result) == 'table' then jobs = result
            elseif err then Client.notify(err, 'error') end
        end
        local state = { jobs = jobs, logs = {} }
        openManagement(state, 'businesses')
    end)
end

---@param value boolean
function Creator.setAdmin(value)
    isAdmin = value == true
    Creator.refresh()
end

RegisterCommand(Config.command, function() Creator.open() end, false)
