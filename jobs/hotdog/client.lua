local playerData = exports.kora_core:getPlayerData()

local standModel = 'prop_hotdogstand_01'
local genericError = 'Something went wrong, try again.'

local hotdogBlip = nil
local standObject = nil
local standTargetId = nil
local pushLease = nil
local spatulaProp = nil
local pushPromptId = nil

local isWorking = false
local isBusy = false
local isPushing = false
local isPreparing = false
local workRun = 0
local stock = { common = 0, rare = 0, exotic = 0 }

local selling = {
    enabled = false,
    run = 0,
    target = nil,
    hasTarget = false,
    targetId = nil,
    targetPed = nil,
    recentPeds = {},
}

local standOffset = { x = 0.0, y = -0.8, z = 1.0, distance = 2.0 }

-- Local mirrors of the kora_lib cache so the polling loops below read an
-- upvalue instead of making an export call per iteration.
local myPed = Kora.cache.ped()
local myDead = Kora.cache.isDead()
Kora.cache.onChange('ped', function(ped) myPed = ped end)
Kora.cache.onChange('isDead', function(dead) myDead = dead end)
local pushAnim = { dict = 'missfinale_c2ig_11', clip = 'pushcar_offcliff_f' }
local detachKeys = { 157, 158, 160, 164, 165, 73, 36, 44 }
local pushBlockedControls = { 244, 23 }

local STOCK_APP_ID = 'qb-hotdogjob:stock'

local HOTDOG_ICON = 'nui://kora_businesses/jobs/hotdog/icon.png'

local QUALITY_META = {
    common = { label = 'Common', image = HOTDOG_ICON, color = '#d62828' },
    rare = { label = 'Rare', image = HOTDOG_ICON, color = '#f77f00' },
    exotic = { label = 'Exotic', image = HOTDOG_ICON, color = '#2a9d5b' },
}

local function notify(message, notifyType)
    Kora.notify.send({ message = message, type = notifyType or 'info' })
end

local function runExclusive(fn)
    if isBusy then return end
    isBusy = true
    local ok, err = pcall(fn)
    isBusy = false
    if not ok then print(('[qb-hotdogjob] %s'):format(tostring(err))) end
end

local function isHotdogJob()
    return playerData.job ~= nil and playerData.job.name == 'hotdog'
end

local function standExists()
    return standObject ~= nil and DoesEntityExist(standObject)
end

local function standSpot()
    return GetOffsetFromEntityInWorldCoords(standObject, standOffset.x, standOffset.y, standOffset.z)
end

local function getRep()
    local skill = playerData.skills and playerData.skills[Hotdog.Skill]
    return skill and skill.xp or 0
end

local function getLevel()
    local skill = playerData.skills and playerData.skills[Hotdog.Skill]
    return skill and skill.level or 1
end

local function resetStock()
    stock = { common = 0, rare = 0, exotic = 0 }
end

local function buildStockNav()
    local items = {}
    for quality, data in pairs(Hotdog.Stock) do
        local meta = QUALITY_META[quality] or { label = quality, image = nil }
        local count = stock[quality] or 0
        items[#items + 1] = {
            id = quality,
            label = meta.label,
            image = meta.image,
            backgroundColor = meta.color,
            description = ('Max %d'):format(data.Max[math.min(getLevel(), 4)]),
            badge = tostring(count),
            tone = count > 0 and 'success' or 'neutral',
        }
    end

    return {
        {
            id = 'stock',
            label = 'Stock',
            icon = 'Package',
            content = {
                title = 'Your stock',
                blocks = {
                    { type = 'list', layout = 'list', items = items },
                    {
                        type = 'stats',
                        title = 'Cooking skill',
                        items = {
                            { label = 'Level', value = getLevel(), icon = 'Star' },
                            { label = 'Cooking XP', value = getRep(), icon = 'TrendingUp' },
                        },
                    },
                },
            },
        },
    }
end

local function refreshUI()
    Kora.nui.updateApp(STOCK_APP_ID, { navigation = buildStockNav() })
end

Kora.nui.registerApp({
    id = STOCK_APP_ID,
    title = 'Hot Dog Cart',
    description = 'Your current stock',
    icon = 'ShoppingBag',
    layout = 'compact',
    defaultView = 'stock',
    navigation = buildStockNav(),
})

local function openStockApp()
    CreateThread(function()
        Kora.nui.openApp(STOCK_APP_ID)
    end)
end

local function updateBlip()
    if hotdogBlip then
        Kora.blips.remove(hotdogBlip)
        hotdogBlip = nil
    end

    if isHotdogJob() then
        hotdogBlip = Kora.blips.create(Hotdog.Locations['take'].coords, {
            sprite = 542,
            color = 17,
            scale = 0.6,
            shortRange = true,
            category = 'Restaurant',
            name = Kora.lang('hotdog.info.blip_name'),
        }) or nil
    end
end

local function markRecent(ped)
    local recent = selling.recentPeds
    recent[#recent + 1] = ped
    if #recent > 50 then table.remove(recent, 1) end
end

local function releaseCustomer(ped, recent)
    if not ped or not DoesEntityExist(ped) then return end
    FreezeEntityPosition(ped, false)
    SetPedKeepTask(ped, false)
    SetEntityAsNoLongerNeeded(ped)
    ClearPedTasksImmediately(ped)
    if recent then markRecent(ped) end
end

local function removeCustomerTarget()
    if selling.targetId and selling.targetPed then
        Kora.interact.removeEntity(selling.targetPed, selling.targetId)
    end
    selling.targetId = nil
    selling.targetPed = nil
end

local function stopSelling()
    releaseCustomer(selling.target, false)
    removeCustomerTarget()
    selling.enabled = false
    selling.target = nil
    selling.hasTarget = false
end

local function pickHotdog()
    local available = {}
    for quality, count in pairs(stock) do
        if count > 0 then available[#available + 1] = quality end
    end
    if #available == 0 then return nil end
    return available[math.random(1, #available)]
end

local function offerRange(quality, amount)
    local price = Hotdog.Stock[quality].Price[math.min(getLevel(), 4)]
    return ('%d-%d'):format(price.min * amount, price.max * amount)
end

local function findCustomer()
    local nearby = Kora.world.getNearbyEntities('ped', standSpot(), 15.0, { excludeEntities = selling.recentPeds })
    for i = 1, #nearby do
        local ped = nearby[i].entity
        if not IsPedAPlayer(ped) and not IsPedInAnyVehicle(ped, false) and not IsPedDeadOrDying(ped, true) then
            return ped
        end
    end
    return nil
end

local function completeSale(ped, quality, amount)
    stock[quality] = stock[quality] - amount
    refreshUI()

    local result, reason = Kora.callback.trigger('qb-hotdogjob:sell', NetworkGetNetworkIdFromEntity(ped), quality, amount)
    if not result then
        if reason then
            stock[quality] = 0
        else
            stock[quality] = stock[quality] + amount
        end
        refreshUI()
        notify(reason or genericError, 'error')
        releaseCustomer(ped, false)
        return
    end

    notify(Kora.lang('hotdog.success.sold_hotdogs', result.amount, result.total), 'success')
    Kora.anim.play(Kora.cache.ped(), 'mp_arresting', 'a_uncuff', { duration = 500, flag = 48 })
    releaseCustomer(ped, false)
end

local function declineOffer(ped)
    if selling.target ~= ped then return end
    notify(Kora.lang('hotdog.error.cust_refused'), 'error')
    selling.hasTarget = false
    selling.target = nil
    removeCustomerTarget()
    releaseCustomer(ped, true)
end

local function acceptOffer(ped, quality, amount)
    if selling.target ~= ped or not selling.hasTarget then return end
    if #(GetEntityCoords(Kora.cache.ped()) - GetEntityCoords(ped)) > Hotdog.SaleDistance then
        declineOffer(ped)
        notify(Kora.lang('hotdog.error.too_far'), 'error')
        return
    end
    selling.hasTarget = false
    selling.target = nil
    markRecent(ped)
    removeCustomerTarget()
    completeSale(ped, quality, amount)
end

local function addCustomerTarget(ped, quality, amount, range)
    selling.targetPed = ped
    selling.targetId = Kora.interact.addEntity(ped, {
        {
            icon = 'fas fa-hand-holding-dollar',
            label = Kora.lang('hotdog.info.sell_dogs_target', amount, range),
            action = function()
                CreateThread(function() acceptOffer(ped, quality, amount) end)
            end,
        },
        {
            icon = 'fas fa-x',
            label = 'Decline offer',
            action = function() declineOffer(ped) end,
        },
    })
end

local function sellToPed(ped)
    local quality = pickHotdog()
    if not quality then
        stopSelling()
        notify(Kora.lang('hotdog.error.no_dogs'), 'error')
        return
    end
    local amount = math.random(1, math.min(3, stock[quality]))

    selling.hasTarget = true
    SetEntityAsNoLongerNeeded(ped)
    ClearPedTasks(ped)

    local spot = standSpot()
    local pedDistance = #(spot - GetEntityCoords(ped))
    local deadline = GetGameTimer() + 30000
    TaskGoStraightToCoord(ped, spot.x, spot.y, spot.z, 1.2, -1, 0.0, 0.0)

    while pedDistance > standOffset.distance do
        if not selling.enabled or not selling.hasTarget or not standExists()
            or not DoesEntityExist(ped) or GetGameTimer() > deadline then
            releaseCustomer(ped, true)
            selling.hasTarget = false
            return
        end

        spot = standSpot()
        if #(GetEntityCoords(myPed) - spot) > 10.0 then
            releaseCustomer(ped, true)
            stopSelling()
            notify(Kora.lang('hotdog.error.too_far'), 'error')
            return
        end

        TaskGoStraightToCoord(ped, spot.x, spot.y, spot.z, 1.2, -1, 0.0, 0.0)
        pedDistance = #(spot - GetEntityCoords(ped))
        Wait(100)
    end

    local playerPed = Kora.cache.ped()
    FreezeEntityPosition(ped, true)
    TaskLookAtEntity(ped, playerPed, 5500.0, 2048, 3)
    TaskTurnPedToFaceEntity(ped, playerPed, 5500)
    SetEntityHeading(ped, GetEntityHeading(playerPed) + 180.0)
    Kora.anim.playScenario(ped, 'WORLD_HUMAN_STAND_IMPATIENT_UPRIGHT')
    selling.target = ped

    local range = offerRange(quality, amount)
    addCustomerTarget(ped, quality, amount, range)

    while selling.enabled and selling.hasTarget and selling.target == ped and standExists() do
        if #(GetEntityCoords(myPed) - standSpot()) >= 4.0 then
            removeCustomerTarget()
            releaseCustomer(ped, true)
            stopSelling()
            notify(Kora.lang('hotdog.error.too_far'), 'error')
            return
        end

        Wait(250)
    end

    removeCustomerTarget()
end

local function startSelling()
    if not standExists() then
        notify(Kora.lang('hotdog.error.no_stand'), 'error')
        return
    end
    if #(GetEntityCoords(Kora.cache.ped()) - GetEntityCoords(standObject)) >= 5.0 then
        notify(Kora.lang('hotdog.error.too_far'), 'error')
        return
    end

    selling.enabled = true
    selling.run = selling.run + 1
    local run = selling.run

    CreateThread(function()
        while selling.enabled and selling.run == run and standExists() do
            if not selling.hasTarget then
                local ped = findCustomer()
                if ped then
                    local ok = pcall(sellToPed, ped)
                    if not ok then
                        removeCustomerTarget()
                        releaseCustomer(ped, true)
                        selling.hasTarget = false
                        selling.target = nil
                    end
                end
            end
            Wait(100)
        end
    end)
end

local function toggleSelling()
    if not isWorking then return end
    if selling.enabled then stopSelling() else startSelling() end
end

local function letGoOfStand()
    if not isPushing then return end
    isPushing = false

    if pushPromptId then
        Kora.textui.hide(pushPromptId)
        pushPromptId = nil
    end

    if pushLease then
        Kora.controls.release(pushLease)
        pushLease = nil
    end

    if standExists() then
        DetachEntity(standObject, false, false)
        SetEntityCollision(standObject, true, true)
    end
    Kora.anim.clear(Kora.cache.ped())
end

local function keepPushAnimation()
    pushPromptId = Kora.textui.show('[G] To let go of the stand')

    CreateThread(function()
        while isPushing do
            local ped = myPed
            if not Kora.anim.isPlaying(ped) then
                Kora.anim.play(ped, pushAnim.dict, pushAnim.clip, { flag = 50 })
            end
            Wait(1000)
        end
    end)
end

-- Detach keys and the single-frame IsPedShooting check need the tight cadence;
-- the state checks (aiming, melee, dead, ragdoll) only need a few runs a second.
local standStateInterval = 100

local function shouldDropStand(ped, checkState)
    for i = 1, #detachKeys do
        local key = detachKeys[i]
        if IsControlJustPressed(0, key) or IsDisabledControlJustPressed(0, key) then
            return true
        end
    end

    if IsPedShooting(ped) then return true end
    if not checkState then return false end

    return IsPlayerFreeAiming(PlayerId()) or IsPedInMeleeCombat(ped) or myDead or IsPedRagdoll(ped)
end

-- Runs only while the stand is being pushed; takeStand() starts it.
local watchingStand = false

local function watchStandHandling(run)
    if watchingStand then return end
    watchingStand = true
    CreateThread(function()
        local nextStateCheck = 0
        while isPushing and isWorking and workRun == run do
            local now = GetGameTimer()
            local checkState = now >= nextStateCheck
            if checkState then nextStateCheck = now + standStateInterval end
            if shouldDropStand(myPed, checkState) then
                letGoOfStand()
                break
            end
            Wait(5)
        end
        watchingStand = false
    end)
end

local function takeStand()
    if isPushing or not standExists() then return end

    local ped = Kora.cache.ped()
    isPushing = true
    Kora.entities.requestControl(standObject)
    Kora.anim.play(ped, pushAnim.dict, pushAnim.clip, { flag = 50 })
    pushLease = Kora.controls.acquire(pushBlockedControls)

    SetTimeout(150, function()
        if isPushing and standExists() then
            AttachEntityToEntity(standObject, ped, GetPedBoneIndex(ped, 28422), -0.45, -1.2, -0.82, 180.0, 180.0, 270.0, false, false, false, false, 1, true)
        end
    end)

    FreezeEntityPosition(standObject, false)
    FreezeEntityPosition(ped, false)
    keepPushAnimation()
    watchStandHandling(workRun)
end

local function grabStand()
    if selling.enabled then stopSelling() end
    takeStand()
end

local function prepareHotdog()
    if not isWorking or isPushing or isPreparing then return end
    isPreparing = true

    local begun, beginReason = Kora.callback.trigger('qb-hotdogjob:beginPreparing')
    if type(begun) ~= 'table' or type(begun.authorization) ~= 'string' then
        isPreparing = false
        notify(beginReason or genericError, 'error')
        return
    end

    TaskStartScenarioInPlace(Kora.cache.ped(), 'PROP_HUMAN_BBQ', 0, true)
    local played, result = pcall(Kora.minigames.play, 'keys', nil, begun.authorization)
    isPreparing = false
    ClearPedTasks(Kora.cache.ped())

    local cancelled = played and type(result) == 'table' and result.cancelled == true
    local proof = played and type(result) == 'table' and result.success and result.proof or false

    local reward, reason = Kora.callback.trigger('qb-hotdogjob:finishPreparing', proof, begun.authorization)
    if not reward then
        if not cancelled then notify(reason or genericError, 'error') end
        return
    end

    stock[reward.quality] = (stock[reward.quality] or 0) + reward.amount
    if reward.amount == 0 then
        notify(Kora.lang('hotdog.error.no_more', reward.label), 'error')
    elseif reward.amount > 1 then
        notify(Kora.lang('hotdog.success.made_luck_hotdog', reward.amount, reward.label), 'success')
    else
        notify(Kora.lang('hotdog.success.made_hotdog', reward.label), 'success')
    end
    refreshUI()
end

local function addStandTarget()
    standTargetId = Kora.interact.addEntity(standObject, {
        {
            icon = 'fas fa-hand',
            label = Kora.lang('hotdog.info.grab'),
            canInteract = function() return isWorking end,
            action = function()
                CreateThread(function()
                    if isPushing then letGoOfStand() else grabStand() end
                end)
            end,
        },
        {
            icon = 'fas fa-hotdog',
            label = Kora.lang('hotdog.info.prepare'),
            canInteract = function() return isWorking and not isPushing end,
            action = function() CreateThread(prepareHotdog) end,
        },
        {
            icon = 'fas fa-hand-holding-usd',
            label = Kora.lang('hotdog.info.toggle_sell'),
            canInteract = function() return isWorking end,
            action = toggleSelling,
        },
        {
            icon = 'fas fa-box',
            label = 'Check stock',
            canInteract = function() return isWorking end,
            action = openStockApp,
        },
    }, 3.0)
end

local function teardownStand()
    stopSelling()
    letGoOfStand()

    if standTargetId and standObject then
        Kora.interact.removeEntity(standObject, standTargetId)
    end
    standTargetId = nil

    if standExists() then Kora.entities.delete(standObject) end
    standObject = nil

    Kora.anim.clear(Kora.cache.ped(), true)
    isWorking = false
    resetStock()
    refreshUI()
    if Kora.nui.isAppOpen(STOCK_APP_ID) then Kora.nui.closeApp(STOCK_APP_ID) end
end

local function spawnStand()
    local spawn = Hotdog.Locations['spawn'].coords

    local ok, loaded = pcall(Kora.stream.loadModel, standModel, function(hash)
        standObject = CreateObject(hash, spawn.x, spawn.y, spawn.z, true, false, false)
    end)

    if not ok or not loaded or not standExists() then
        standObject = nil
        return false
    end

    PlaceObjectOnGroundProperly(standObject)
    SetEntityHeading(standObject, spawn.w - 90)
    FreezeEntityPosition(standObject, true)
    return true
end

local function startWorking()
    if isWorking then return end

    local started, reason = Kora.callback.trigger('qb-hotdogjob:startWorking')
    if not started then
        notify(reason or genericError, 'error')
        return
    end

    if not spawnStand() then
        Kora.callback.trigger('qb-hotdogjob:stopWorking')
        notify(genericError, 'error')
        return
    end

    isWorking = true
    workRun = workRun + 1
    resetStock()

    addStandTarget()

    refreshUI()
    notify(Kora.lang('hotdog.success.deposit', Hotdog.StandDeposit), 'success')
end

local function stopWorking()
    if not isWorking then return end

    if not standExists() then
        notify(Kora.lang('hotdog.error.no_stand_found'), 'error')
        teardownStand()
        return
    end

    local stopped, reason = Kora.callback.trigger('qb-hotdogjob:stopWorking')
    if stopped then
        teardownStand()
        notify(Kora.lang('hotdog.success.deposit_returned', Hotdog.StandDeposit), 'success')
    elseif reason then
        teardownStand()
        notify(reason, 'error')
    else
        notify(genericError, 'error')
    end
end

local function toggleWork()
    runExclusive(function()
        if isWorking then stopWorking() else startWorking() end
    end)
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if standObject ~= nil then
        DeleteEntity(standObject)
        ClearPedTasksImmediately(PlayerPedId())
    end
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    playerData = exports.kora_core:getPlayerData()
    updateBlip()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUpdated', function(key, val)
    if key == 'job' then
        playerData.job = val
        updateBlip()
    elseif key == 'all' then
        playerData.job = val.job
        updateBlip()
    end
end)

RegisterNetEvent('qb-hotdogjob:client:UpdateReputation', function(jobRep)
    playerData.metadata['rep'] = jobRep
    refreshUI()
end)

RegisterNetEvent('qb-hotdogjob:client:ToggleSell', toggleSelling)

RegisterNetEvent('qb-hotdogjob:staff:DeletStand', function()
    local pos = GetEntityCoords(Kora.cache.ped())
    local object, _, distance = Kora.world.getClosestEntity('object', pos, { radius = 10.0, models = { standModel } })

    if object and distance <= 5.0 then
        Kora.entities.delete(object)
        notify(Kora.lang('hotdog.info.admin_removed'), 'info')
    end
end)

Kora.keybind.add({
    name = 'letgostand',
    description = Kora.lang('hotdog.keymapping.gkey'),
    defaultKey = 'G',
    onPressed = function() letGoOfStand() end,
})

CreateThread(function()
    local take = Hotdog.Locations['take'].coords
    local center = vector3(take.x, take.y, take.z)

    Kora.interact.addBoxZone('hotdog_start', center, vector4(1.0, 1.0, 2.0, take.w), {
            {
                icon = 'fa-solid fa-hotdog',
                label = Kora.lang('hotdog.info.start_work'),
                job = 'hotdog',
                canInteract = function() return not isWorking end,
                action = function() CreateThread(toggleWork) end,
            },
            {
                icon = 'fa-solid fa-hotdog',
                label = Kora.lang('hotdog.info.stop_work'),
                job = 'hotdog',
                canInteract = function() return isWorking end,
                action = function() CreateThread(toggleWork) end,
            },
    }, false)

    updateBlip()
end)
