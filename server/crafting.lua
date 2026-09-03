-- Crafting benches and useable items.
--
-- The client never sends a recipe. It sends a business id, a module index and a
-- recipe id, and the server looks the recipe up in the same shared config the
-- client rendered from. A client that lies about any of the three gets a
-- rejection, not a recipe of its own design -- the progress bar it just played
-- is a presentation detail, and the ingredient check happens here regardless.

QbBusinesses = QbBusinesses or {}

local State = QbBusinesses.state
local Logs = QbBusinesses.logs

local Crafting = {}
QbBusinesses.crafting = Crafting

---@param id any
---@return table|nil recipe
function Crafting.recipe(id)
    if type(id) ~= 'string' then return nil end
    local recipe = Config.recipes[id]
    return type(recipe) == 'table' and recipe or nil
end

---@param list any
---@param field 'ingredients'|'give'
---@return table[]
local function entries(recipe, field)
    local out = {}
    for _, raw in ipairs(recipe[field] or {}) do
        local name = type(raw) == 'table' and (raw.item or raw.name) or nil
        if type(name) == 'string' then
            out[#out + 1] = {
                item = name:lower(),
                amount = math.max(math.floor(tonumber(raw.amount or raw.count) or 1), 1),
                info = type(raw.info or raw.metadata) == 'table' and (raw.info or raw.metadata) or nil,
            }
        end
    end
    return out
end
Crafting.entries = entries

---@param src integer
---@param recipe table
---@return boolean ok, string|nil err
local function meetsSkills(src, recipe)
    if not Config.skills.enabled then return true end
    for _, requirement in ipairs(recipe.levelRequired or {}) do
        local skill = requirement.skill
        local needed = tonumber(requirement.level) or 0
        local have = tonumber(Config.skills.getLevel(src, skill)) or 0
        if have < needed then
            return false, ('You need %s level %d.'):format(tostring(skill), needed)
        end
    end
    return true
end

---Runs one craft. Callers must have already established that `src` is entitled
---to this recipe (a bench they are standing at, or an item they just used).
---@param src integer
---@param recipe table
---@param business? table
---@return boolean ok, string|nil err
function Crafting.craft(src, recipe, business)
    local ok, err = meetsSkills(src, recipe)
    if not ok then return false, err end

    local needed, produced = entries(recipe, 'ingredients'), entries(recipe, 'give')
    if #produced == 0 then return false, 'That recipe produces nothing.' end

    for _, ingredient in ipairs(needed) do
        if exports.qbcore:getItemCount(src, ingredient.item) < ingredient.amount then
            return false, 'You are missing ingredients.'
        end
    end

    for _, product in ipairs(produced) do
        if not exports.qbcore:canCarry(src, product.item, product.amount) then
            return false, 'You do not have room for that.'
        end
    end

    -- Removals are rolled back item by item if one fails, so a partial
    -- consumption can never happen: everything is taken, or nothing is.
    local removed = {}
    for _, ingredient in ipairs(needed) do
        local taken = exports.qbcore:removeItem(src, ingredient.item, ingredient.amount)
        if not taken then
            for _, undo in ipairs(removed) do
                exports.qbcore:addItem(src, undo.item, undo.amount, nil, undo.info)
            end
            return false, 'You are missing ingredients.'
        end
        removed[#removed + 1] = ingredient
    end

    local given = {}
    for _, product in ipairs(produced) do
        local added = exports.qbcore:addItem(src, product.item, product.amount, nil, product.info)
        if added then given[#given + 1] = ('%dx %s'):format(product.amount, product.item) end
    end

    if Config.skills.enabled then
        for _, gain in ipairs(recipe.xpGained or {}) do
            local amount = tonumber(gain.xp) or 0
            if gain.skill and amount > 0 then Config.skills.addXp(src, gain.skill, amount) end
        end
    end

    if business then
        Logs.record(business, {
            category = 'craft', src = src,
            message = ('Crafted %s.'):format(table.concat(given, ', ')),
        })
    end
    return true, recipe.completeLabel or ('You made %s.'):format(table.concat(given, ', '))
end

QB.callback.register('qbbusinesses:server:craft', function(src, businessId, moduleIndex, recipeId)
    local business = State.get(businessId)
    if not business then return false, 'Unknown business.' end

    local module = State.module(business, moduleIndex)
    if not module or module.moduleType ~= 'Crafting' then return false, 'Unknown crafting bench.' end
    if not module.public and not State.worksFor(src, business.job) then return false, 'You do not work here.' end

    -- The recipe must be one THIS bench offers, not merely a recipe that exists.
    local offered = false
    for _, id in ipairs(module.recipes) do
        if id == recipeId then offered = true; break end
    end
    if not offered then return false, 'That is not made here.' end

    local recipe = Crafting.recipe(recipeId)
    if not recipe then return false, 'Unknown recipe.' end

    local anchor = module.zoneType and module.coords or (module.coords and module.coords[1])
    if anchor and not QB.distance.player(src, anchor, 8.0) then
        return false, 'You are not at the bench.'
    end

    return Crafting.craft(src, recipe, business)
end, { rateLimit = { max = 20, window = 10000 } })

-- ---------------------------------------------------------------------------
-- Useable items
-- ---------------------------------------------------------------------------

---@param business table
---@param module table
function Crafting.registerUseable(business, module)
    exports.qbinventory:createUseable(module.item, function(src)
        local consume = module.consume
        if consume > 0 and not exports.qbcore:removeItem(src, module.item, consume) then
            return QB.notify.send(src, { title = Config.notifyTitle, message = 'You do not have that.', type = 'error' })
        end

        local ok, message
        if module.useType == 'recipe' then
            local recipe = Crafting.recipe(module.recipe)
            if not recipe then
                ok, message = false, 'That recipe no longer exists.'
            else
                ok, message = Crafting.craft(src, recipe, business)
            end
        else
            local rewards = QB.rewards.generate(module.rewards, { mode = 'weighted', rolls = module.rolls })
            local given = {}
            for _, reward in ipairs(rewards) do
                local name = reward.item or reward.name
                local amount = math.max(math.floor(tonumber(reward.amount) or 1), 1)
                if name and exports.qbcore:addItem(src, name, amount) then
                    given[#given + 1] = ('%dx %s'):format(amount, name)
                end
            end
            ok = #given > 0
            message = ok and ('You got %s.'):format(table.concat(given, ', ')) or 'You could not carry the contents.'
        end

        -- The item is refunded when the outcome failed, so a full inventory or a
        -- broken recipe never silently eats it.
        if not ok and consume > 0 then
            exports.qbcore:addItem(src, module.item, consume)
        end

        QB.notify.send(src, {
            title = Config.notifyTitle, message = message or 'Nothing happened.',
            type = ok and 'success' or 'error',
        })

        if ok then
            Logs.record(business, { category = 'craft', src = src, message = ('Used %s: %s'):format(module.item, message) })
        end
    end)
end
