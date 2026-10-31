-- CCTV has no client authority. The phone and management resources consume the
-- server callbacks exposed by jobs/cctv/server.lua.
local APP_ID = 'qbbusinesses:cctv-laptop'
local active = false

local function hack(targetId)
    local started, data = Kora.callback.trigger('qbbusinesses:cctv:beginHack', { targetId = targetId })
    if not started then
        return Kora.notify.send({ title = 'CCTV', message = data or 'Could not start the hack.', type = 'error' })
    end
    local result = Kora.minigames.play(Cctv.hacking.game, nil, data.authorization)
    local success, response = Kora.callback.trigger('qbbusinesses:cctv:finishHack', { proof = result and result.proof })
    Kora.notify.send({
        title = 'CCTV',
        message = success and ('Access granted: %s'):format(response.targetId) or (response or 'The hack failed.'),
        type = success and 'success' or 'error',
    })
end

local function repair(targetId)
    local started, data = Kora.callback.trigger('qbbusinesses:cctv:beginRepairCheck', {
        targetId = targetId,
    })
    if not started then return Kora.notify.send({ title = 'CCTV', message = data or 'Could not start repair.', type = 'error' }) end
    local result = Kora.minigames.play(Cctv.repairChecks.game, nil, data.authorization)
    local success, response = Kora.callback.trigger('qbbusinesses:cctv:finishRepairCheck', { proof = result and result.proof })
    Kora.notify.send({ title = 'CCTV', message = success and ('Repair check passed: %s'):format(response.targetId) or (response or 'The repair check failed.'), type = success and 'success' or 'error' })
end

RegisterCommand('cctvhack', function(_, args)
    if not args[1] then return end
    CreateThread(function() hack(args[1]) end)
end, false)

RegisterCommand('cctvrepair', function(_, args)
    if not args[1] then return end
    CreateThread(function() repair(args[1]) end)
end, false)

local function openLaptop()
    if active then return end
    active = true
    CreateThread(function()
        local data, err = Kora.callback.trigger('qbbusinesses:cctv:laptopData')
        if not data then
            Kora.notify.send({ title = 'CCTV', message = err or 'Laptop access denied.', type = 'error' })
            active = false
            return
        end

        local systems = {}
        for _, system in ipairs(data.systems or {}) do
            systems[#systems + 1] = {
                id = system.id, label = system.businessLabel or system.business,
                description = ('%d cameras · %s'):format(tonumber(system.cameraCount) or 0, system.status or 'Unknown'),
                icon = 'shield-check', tone = system.status == 'online' and 'success' or 'warning',
            }
        end
        local jobs = {}
        for _, callout in ipairs(data.callouts or {}) do
            jobs[#jobs + 1] = {
                id = callout.id, label = ('%s repair · %s'):format(callout.issue, callout.business),
                description = callout.status, icon = 'wrench', tone = callout.status == 'completed' and 'success' or 'warning',
            }
        end

        Kora.nui.registerApp({
            id = APP_ID, title = 'CCTV Engineer Laptop', description = 'Installed systems and service call-outs',
            icon = 'monitor-smartphone', width = 1100, height = 720,
            navigation = {
                { id = 'systems', label = 'Installed systems', icon = 'shield-check', content = {
                    title = 'Company systems', description = 'CCTV systems installed by your company.',
                    blocks = { { type = 'list', layout = 'cards', searchable = true, pageSize = 8, items = systems,
                        empty = 'No installed systems are available yet.' } },
                } },
                { id = 'callouts', label = 'Call-outs', icon = 'wrench', badge = #jobs, content = {
                    title = 'Service call-outs', description = 'Emergency repair work for your company.',
                    blocks = { { type = 'list', layout = 'cards', searchable = true, pageSize = 8, items = jobs,
                        empty = 'No call-outs are currently listed.' } },
                } },
            },
        })
        Kora.nui.openApp(APP_ID)
        active = false
    end)
end

RegisterNetEvent('qbbusinesses:cctv:openLaptop', openLaptop)
