-- The client half of a business: zones, blips, props and target options built
-- from the replicated definition.
--
-- A business owns two scopes. The STATIC scope holds its perimeter and map
-- blips and exists for as long as the business does. The DYNAMIC scope holds
-- everything you can actually interact with -- tills, stashes, benches, props --
-- and is built when the player walks into the perimeter and torn down when they
-- leave. A server with fifty businesses therefore holds fifty zones, not fifty
-- businesses' worth of props and target registrations.
--
-- A business with no perimeter has nothing to trigger that, so all of its
-- modules live in the static scope instead.

QbBusinesses = QbBusinesses or {}

local S = QbBusinesses.schema
local Client = QbBusinesses.client

local Business = {}
Business.__index = Business
QbBusinesses.Business = Business

local target = exports.qbtarget

local function newScope()
    return { zones = {}, blips = {}, entities = {}, targets = {} }
end

---@param scope table
local function clearScope(scope)
    for _, zone in ipairs(scope.zones) do pcall(zone.remove) end
    for _, blip in ipairs(scope.blips) do QB.blips.remove(blip) end
    for _, registration in ipairs(scope.targets) do
        if registration.kind == 'zone' then target:removeZone(registration.id)
        else target:removeEntity(registration.entity, registration.id) end
    end
    -- Entities last: a target registration still points at them.
    for _, entity in ipairs(scope.entities) do QB.entities.remove(entity) end
    scope.zones, scope.blips, scope.entities, scope.targets = {}, {}, {}, {}
end

---@param name string
---@return integer
local function itemCount(name)
    -- An array path, not a dotted string -- see Client.job().
    local items = exports.qbcore:getPlayerData({ 'items' }) or {}
    local total = 0
    for _, item in pairs(items) do
        if item and item.name == name then total = total + (item.amount or 0) end
    end
    return total
end

---@param name string
---@return string
local function itemLabel(name)
    local definition = QB.shared.get('items', name)
    return (definition and definition.label) or name
end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------

---@param definition table
---@return table
function Business.new(definition)
    local self = setmetatable({
        id = definition.id, label = definition.label, job = definition.job,
        definition = definition,
        hasPerimeter = S.hasPerimeter(definition),
        static = newScope(), dynamic = newScope(), inside = false,
    }, Business)
    self:build(self.static, true)
    return self
end

---@param stopping? boolean Skip the server round-trip (the resource is stopping).
function Business:destroy(stopping)
    if self.inside then self:leave(stopping) end
    clearScope(self.dynamic)
    clearScope(self.static)
end

---@param scope table
---@param startup boolean
function Business:build(scope, startup)
    for index, module in ipairs(self.definition.modules) do
        if S.isStartupModule(self.definition, module) == startup then
            local ok, err = pcall(self.setup, self, scope, index, module)
            if not ok then
                print(('^3[qbbusinesses]^7 %s module #%d (%s) failed: %s'):format(self.id, index, module.moduleType, tostring(err)))
            end
        end
    end
end

---Entering yields -- props stream in and the server is told who arrived -- and
---`onEnter` runs on qblib's shared zone tick thread, which every zone in every
---resource shares. So the flag flips synchronously (that is what makes a second
---`onEnter` a no-op) and the actual work is handed to a thread of our own.
---
---`generation` is what makes that safe: walking back out while the props are
---still streaming bumps it, and the build thread cleans up after itself instead
---of leaving orphaned entities and targets behind a player who already left.
function Business:enter()
    if self.inside then return end
    self.inside = true
    self.generation = (self.generation or 0) + 1

    local generation = self.generation
    CreateThread(function()
        self:build(self.dynamic, false)
        if self.generation ~= generation then return clearScope(self.dynamic) end

        if Client.worksFor(self) then
            if self.controlDuty and Config.duty.enabled then self:setDuty(true) end
            -- Presence means on-duty staff. Auto-duty therefore commits first;
            -- the following callback is independently revalidated server-side.
            QB.callback.trigger('qbbusinesses:server:enter', self.id)
        end
    end)
end

---@param teardownOnly? boolean Skip the server round-trip (resource stopping).
function Business:leave(teardownOnly)
    if not self.inside then return end
    self.inside = false
    self.generation = (self.generation or 0) + 1
    clearScope(self.dynamic)
    if teardownOnly then return end

    if Client.worksFor(self) then
        CreateThread(function()
            QB.callback.trigger('qbbusinesses:server:leave', self.id)
            if self.controlDuty and Config.duty.enabled then self:setDuty(false) end
        end)
    end
end

---@param onDuty boolean
function Business:setDuty(onDuty)
    local job = Client.job()
    if job.onduty == onDuty then return end

    -- Leaving in a company vehicle is going out on a job, not clocking off.
    if not onDuty and Config.duty.keepDutyInJobVehicle then
        local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
        if vehicle ~= 0 then
            local plate = GetVehicleNumberPlateText(vehicle) or ''
            if plate:sub(1, 3):lower() == self.job:sub(1, 3):lower() then return end
        end
    end

    QB.callback.trigger('qbbusinesses:server:setDuty', self.id, onDuty)
end

-- ---------------------------------------------------------------------------
-- Anchors
-- ---------------------------------------------------------------------------

---@param scope table
---@param module table
---@return integer[] entities
function Business:spawn(scope, module)
    local entities = {}
    for _, coords in ipairs(module.coords) do
        if module.model.existing then
            -- The mapper already placed this prop; adopt whatever is standing
            -- there rather than spawning a second copy on top of it.
            local existing = GetClosestObjectOfType(coords.x, coords.y, coords.z, 1.5, joaat(module.model.model), false, false, false)
            if existing ~= 0 then entities[#entities + 1] = existing end
        else
            local entity = QB.entities.create(module.model.model, Client.vec4(coords), {
                preset = 'static',
                freeze = module.model.freeze ~= false,
            })
            if entity then
                scope.entities[#scope.entities + 1] = entity
                entities[#entities + 1] = entity
                if module.model.anim and module.model.modelType == 'ped' then
                    QB.anim.play(entity, module.model.anim.dict, module.model.anim.clip, { flag = module.model.anim.flag })
                end
            end
        end
    end
    return entities
end

---Wraps every option's `canInteract` with the module's job gate, then registers
---them against whichever anchor the module has.
---@param scope table
---@param module table
---@param entities integer[]
---@param options table[]
function Business:attach(scope, module, entities, options)
    local job = (not module.public) and self.job or nil

    for _, option in ipairs(options) do
        option.distance = option.distance or module.distance

        -- qbtarget invokes a single-candidate onSelect on its own tick thread.
        -- Nearly everything here yields (a callback, a dialog, a progress bar),
        -- which would stall targeting for as long as the menu is open -- and
        -- QB.callback.trigger has to be inside a coroutine anyway.
        local select_ = option.onSelect
        option.onSelect = function(...)
            local args = table.pack(...)
            CreateThread(function() select_(table.unpack(args, 1, args.n)) end)
        end

        local base, ignoreLock = option.canInteract, option.ignoreJobLock
        option.ignoreJobLock = nil
        if job and not ignoreLock then
            option.canInteract = function(entity, distance, data)
                if Client.job().name ~= job then return false end
                if base then return base(entity, distance, data) end
                return true
            end
        end
    end

    if #entities > 0 then
        for _, entity in ipairs(entities) do
            scope.targets[#scope.targets + 1] = {
                kind = 'entity', entity = entity, id = target:addEntity(entity, options, module.distance),
            }
        end
        return
    end

    local id
    if module.zoneType == 'sphere' then
        id = target:addSphereZone({
            coords = Client.vec3(module.coords), radius = module.radius,
            options = options, distance = module.distance, debug = Config.debug,
        })
    elseif module.zoneType == 'box' then
        id = target:addBoxZone({
            coords = Client.vec3(module.coords),
            size = vector3(module.size.x, module.size.y, module.size.z),
            rotation = module.rotation, options = options, distance = module.distance, debug = Config.debug,
        })
    elseif module.zoneType == 'poly' then
        local points = {}
        for _, point in ipairs(module.points) do points[#points + 1] = Client.vec3(point) end
        id = target:addPolyZone({
            points = points, thickness = module.thickness,
            options = options, distance = module.distance, debug = Config.debug,
        })
    end
    if id then scope.targets[#scope.targets + 1] = { kind = 'zone', id = id } end
end

---@param scope table
---@param blip table
local function addBlip(scope, blip)
    local handle = QB.blips.create(vector3(blip.coords.x, blip.coords.y, blip.coords.z), {
        sprite = blip.sprite, color = blip.color, scale = blip.scale,
        shortRange = blip.shortRange, label = blip.label,
    })
    if handle then scope.blips[#scope.blips + 1] = handle end
end

-- ---------------------------------------------------------------------------
-- Module builders
-- ---------------------------------------------------------------------------

local builders = {}

function Business:setup(scope, index, module)
    local builder = builders[module.moduleType]
    if not builder then return end

    local entities = module.model and self:spawn(scope, module) or {}
    if module.blip then addBlip(scope, module.blip) end

    local options = builder(self, scope, index, module, entities)
    if options and #options > 0 then self:attach(scope, module, entities, options) end
end

builders.Zone = function(self, scope, _, module)
    self.controlDuty = module.controlDuty
    local opts = {
        onEnter = function() self:enter() end,
        onExit = function() self:leave() end,
        debug = Config.debug,
    }
    if module.zoneType == 'sphere' then
        opts.coords, opts.radius = Client.vec3(module.coords), module.radius
    elseif module.zoneType == 'box' then
        opts.coords = Client.vec3(module.coords)
        opts.size = vector3(module.size.x, module.size.y, module.size.z)
        opts.rotation = module.rotation
    else
        local points = {}
        for _, point in ipairs(module.points) do points[#points + 1] = Client.vec3(point) end
        opts.points, opts.thickness = points, module.thickness
    end
    scope.zones[#scope.zones + 1] = QB.zones[module.zoneType](opts)
end

builders.Blip = function(_, scope, _, module)
    addBlip(scope, {
        coords = module.coords, sprite = module.sprite, color = module.color,
        scale = module.scale, shortRange = module.shortRange, label = module.label,
    })
end

builders.StaticEntity = function() return nil end

builders.BossMenu = function(self, _, _, module)
    return { {
        label = module.label,
        icon = module.icon or 'Briefcase',
        canInteract = function() return Client.isBoss(self) end,
        onSelect = function()
            if GetResourceState('qbbossmenu') ~= 'started' then
                return Client.notify('The boss menu is unavailable.', 'error')
            end
            exports.qbbossmenu:openBossMenu()
        end,
    } }
end

builders.Stash = function(_, _, _, module)
    return { {
        label = module.label,
        icon = module.icon or 'Archive',
        onSelect = function()
            local ok, err = QB.callback.trigger('qbbusinesses:server:openStash', module.id)
            if not ok then Client.notify(err or 'You cannot open that.', 'error') end
        end,
    } }
end

builders.POS = function(self, _, _, module)
    local options = {}

    options[#options + 1] = {
        label = ('Buy from %s'):format(module.label),
        icon = module.icon or 'ShoppingCart',
        -- Customers are the point of a till, so this option is never job-gated.
        ignoreJobLock = true,
        canInteract = function()
            if not module.hideWhenStaffed then return true end
            if Client.worksFor(self) then return true end
            return (Client.staff[self.id] or 0) == 0
        end,
        onSelect = function()
            local ok, err = QB.callback.trigger('qbbusinesses:server:openShop', module.id)
            if not ok then Client.notify(err or 'The till is closed.', 'error') end
        end,
    }

    -- These three gate themselves rather than leaning on the module-wide job
    -- lock, so marking a till `public` (which only ever means "customers may
    -- walk up to it") cannot accidentally hand its restock and pricing to them.
    options[#options + 1] = {
        label = 'Restock',
        icon = 'PackagePlus',
        canInteract = function() return Client.worksFor(self) end,
        onSelect = function()
            local ok, err = QB.callback.trigger('qbbusinesses:server:openStock', module.id)
            if not ok then Client.notify(err or 'You cannot restock this till.', 'error') end
        end,
    }

    options[#options + 1] = {
        label = 'Set prices',
        icon = 'DollarSign',
        canInteract = function() return Client.isBoss(self) end,
        onSelect = function() QbBusinesses.openPriceEditor(module.id) end,
    }

    options[#options + 1] = {
        label = 'Take a payment',
        icon = 'CreditCard',
        canInteract = function() return Client.worksFor(self) end,
        onSelect = function() QbBusinesses.takePayment() end,
    }

    if module.panicButton then
        options[#options + 1] = {
            label = 'Panic button',
            icon = 'Siren',
            canInteract = function() return Client.worksFor(self) end,
            onSelect = function()
                local ok, err = QB.callback.trigger('qbbusinesses:server:panic', self.id, module.id)
                Client.notify(ok and 'Silent alarm sent.' or (err or 'The alarm did not go through.'), ok and 'success' or 'error')
            end,
        }
    end

    return options
end

---Renders one bench's recipe list, with live ingredient counts.
---@param self table
---@param index integer
---@param module table
local function openCraftingMenu(self, index, module)
    local items = {}
    for _, recipeId in ipairs(module.recipes) do
        local recipe = Config.recipes[recipeId]
        if recipe then
            local parts, ready = {}, true
            for _, ingredient in ipairs(recipe.ingredients or {}) do
                local name = ingredient.item or ingredient.name
                local needed = math.max(math.floor(tonumber(ingredient.amount or ingredient.count) or 1), 1)
                local have = itemCount(name)
                if have < needed then ready = false end
                parts[#parts + 1] = ('%s %d/%d'):format(itemLabel(name), have, needed)
            end
            items[#items + 1] = {
                id = recipeId,
                label = recipe.label or recipeId,
                description = #parts > 0 and table.concat(parts, ', ') or 'No ingredients required',
                icon = recipe.icon,
                disabled = not ready,
            }
        end
    end

    if #items == 0 then return Client.notify('There is nothing to make here.', 'error') end

    local choice = QB.nui.openMenu(items, module.label)
    if not choice or choice.cancelled or not choice.selectedId then return end

    local recipe = Config.recipes[choice.selectedId]
    if not recipe then return end

    if recipe.time then
        local completed = QB.progressbar.start({
            label = recipe.progressLabel or ('Making %s'):format(recipe.label or choice.selectedId),
            duration = math.floor(recipe.time),
            canCancel = true,
            disable = { move = true, combat = true, car = true },
            anim = recipe.anim,
        })
        if not completed then return end
    end

    local ok, message = QB.callback.trigger('qbbusinesses:server:craft', self.id, index, choice.selectedId)
    Client.notify(message or (ok and 'Done.' or 'That did not work.'), ok and 'success' or 'error')
end

builders.Crafting = function(self, _, index, module)
    return { {
        label = module.label,
        icon = module.icon or 'Hammer',
        onSelect = function() openCraftingMenu(self, index, module) end,
    } }
end
