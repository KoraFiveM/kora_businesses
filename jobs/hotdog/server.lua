local Stock = {}      -- Stock[citizenid] = { common = n, rare = n, exotic = n }
local Working = {}    -- Working[citizenid] = true while the deposit is held
local Preparing = {}  -- Preparing[citizenid] = true while a prepare round is live, blocks overlap
local function fail(msg)
    Kora.print.error(msg)
    return false
end
local function player(src) 
    return exports.kora_core:getPlayerData(src)
end
local function citizenId(src)
    local p = player(src)
    return p and p.citizenid
end

local function isHotdog(src)
    local p = player(src)
    return p and p.job.name == 'hotdog'
end
local function skillData(src)
    if GetResourceState('kora_skills') ~= 'started' then return nil end
    return exports.kora_skills:getRep(src, Hotdog.Skill)
end

local function levelFor(src)
    local data = skillData(src)
    return data and data.level or 1
end

local function clearWorkingState(cid)
    Working[cid] = nil
    Stock[cid] = nil
    Preparing[cid] = nil
end

AddEventHandler('playerDropped', function()
    local cid = citizenId(source)
    if cid then clearWorkingState(cid) end
end)

Kora.callback.register('qb-hotdogjob:startWorking', function(src)
    local p = player(src)
    local cid = citizenId(src)
    assert(p and cid, 'Player not found.')
    assert(isHotdog(src), 'You are not a hotdog vendor.')
    if Working[cid] then return fail('You are already working.') end
    local deposit = tonumber(Hotdog.StandDeposit) or 0
    if deposit > 0 then
        local paid, err = exports.kora_core:removeMoney(src, 'bank', Hotdog.StandDeposit, 'hot dog deposit')
        if not paid then return fail(err or Kora.lang('hotdog.error.no_money')) end
    end
    Working[cid] = true
    Stock[cid] = { common = 0, rare = 0, exotic = 0 }
    return true
end)

Kora.callback.register('qb-hotdogjob:stopWorking', function(src)
    local cid = citizenId(src)
    local p = player(src)
    if not cid or not p then return fail('Player not found.') end
    if not Working[cid] then return fail(Kora.lang('hotdog.error.no_stand_found')) end

    exports.kora_core:addMoney(src, 'bank', Hotdog.StandDeposit, 'hot dog deposit')
    clearWorkingState(cid)
    return true
end)

Kora.callback.register('qb-hotdogjob:beginPreparing', function(src)
    local cid = citizenId(src)
    if not cid or not Working[cid] then return fail(Kora.lang('hotdog.error.no_stand_found')) end
    if Preparing[cid] then return  end

    Preparing[cid] = true
    local authorization = Kora.minigames.authorizeProof(src, 'keys', { amount = Hotdog.PrepareMinigameKeys })
    return { authorization = authorization }
end)

Kora.callback.register('qb-hotdogjob:finishPreparing', function(src, proof, authorization)
    local cid = citizenId(src)
    if not cid or not Working[cid] then Preparing[cid] = nil; return end
    if not Preparing[cid] then return fail('Nothing to finish.') end
    Preparing[cid] = nil

    if type(proof) ~= 'string' or type(authorization) ~= 'string'
        or not Kora.minigames.consumeProof(src, proof, 'keys', authorization) then
        return fail('Minigame could not be verified.')
    end

    if not skillData(src) then return fail('qbskills is required.') end
    local won = Kora.rewards.generate(Hotdog.PrepareRewards)[1]
    local quality = won.name
    local amount = Hotdog.batchSize(levelFor(src), quality)

    local stock = Stock[cid]
    local capacity = Hotdog.Stock[quality].Max[4]
    local granted = math.min(amount, math.max(0, capacity - stock[quality]))
    stock[quality] = stock[quality] + granted

    local p = player(src)
    exports.kora_skills:addRep(src, Hotdog.Skill, Hotdog.PrepareXp[quality] * granted)

    return { quality = quality, amount = granted, label = Hotdog.Stock[quality].Label, full = granted < amount }
end)

Kora.callback.register('qb-hotdogjob:sell', function(src, netId, quality, amount)
    local cid = citizenId(src)
    if not cid or not Working[cid] then return fail(Kora.lang('hotdog.error.no_stand_found')) end

    local ped = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    local playerPed = GetPlayerPed(src)
    if ped == 0 or playerPed == 0 or #(GetEntityCoords(playerPed) - GetEntityCoords(ped)) > Hotdog.SaleDistance then
        return fail(Kora.lang('hotdog.error.too_far'))
    end
    amount = math.floor(tonumber(amount) or 0)
    local stock = Stock[cid]
    if type(quality) ~= 'string' or not Hotdog.Stock[quality] or not stock or amount <= 0 or stock[quality] < amount then
        return fail('Nothing to sell.')
    end

    local level = levelFor(src)
    local priceRange = Hotdog.Stock[quality].Price[math.min(level, 4)]
    local unitPrice = math.random(priceRange.min, priceRange.max)
    local total = unitPrice * amount

    stock[quality] = stock[quality] - amount

    exports.kora_core:addMoney(src, 'cash', total, 'sold hotdog')
    exports.kora_skills:addRep(src, Hotdog.Skill, Hotdog.SaleXp[quality] * amount)
    return { amount = amount, unitPrice = unitPrice, total = total }
end)

exports.kora_core:addCommand('removestand', Kora.lang('hotdog.info.command'), {}, false, function(source, _)
    TriggerClientEvent('qb-hotdogjob:staff:DeletStand', source)
end, 'admin')
