-- CCTV has no client authority. The phone and management resources consume the
-- server callbacks exposed by jobs/cctv/server.lua.
local APP_ID = 'kora_businesses:cctv-laptop'
local active = false

local function hack(targetId)
    local started, data = Kora.callback.trigger('kora_businesses:cctv:beginHack', { targetId = targetId })
    if not started then
        return Kora.notify.send({ title = Kora.lang('cctv.title'), message = data or Kora.lang('cctv.start_hack_failed'), type = 'error' })
    end
    local result = Kora.minigames.play(Cctv.hacking.game, nil, data.authorization)
    local success, response = Kora.callback.trigger('kora_businesses:cctv:finishHack', { proof = result and result.proof })
    Kora.notify.send({
        title = Kora.lang('cctv.title'),
        message = success and Kora.lang('cctv.access_granted', response.targetId) or (response or Kora.lang('cctv.hack_failed_client')),
        type = success and 'success' or 'error',
    })
end

local function repair(targetId)
    local started, data = Kora.callback.trigger('kora_businesses:cctv:beginRepairCheck', {
        targetId = targetId,
    })
    if not started then return Kora.notify.send({ title = Kora.lang('cctv.title'), message = data or Kora.lang('cctv.start_repair_failed'), type = 'error' }) end
    local result = Kora.minigames.play(Cctv.repairChecks.game, nil, data.authorization)
    local success, response = Kora.callback.trigger('kora_businesses:cctv:finishRepairCheck', { proof = result and result.proof })
    Kora.notify.send({ title = Kora.lang('cctv.title'), message = success and Kora.lang('cctv.repair_check_passed', response.targetId) or (response or Kora.lang('cctv.repair_check_failed')), type = success and 'success' or 'error' })
end

RegisterCommand('cctvhack', function(_, args)
    if not args[1] then return end
    CreateThread(function() hack(args[1]) end)
end, false)

RegisterCommand('cctvrepair', function(_, args)
    if not args[1] then return end
    CreateThread(function() repair(args[1]) end)
end, false)

local function suggestCommands()
    TriggerEvent('chat:addSuggestion', '/cctvhack', Kora.lang('cctv.command_hack'), { { name = 'targetId', help = Kora.lang('cctv.target_id') } })
    TriggerEvent('chat:addSuggestion', '/cctvrepair', Kora.lang('cctv.command_repair'), { { name = 'targetId', help = Kora.lang('cctv.target_id') } })
end
suggestCommands()
AddEventHandler('chat:init', suggestCommands)

local function openLaptop()
    if active then return end
    active = true
    CreateThread(function()
        local data, err = Kora.callback.trigger('kora_businesses:cctv:laptopData')
        if not data then
            Kora.notify.send({ title = Kora.lang('cctv.title'), message = err or Kora.lang('cctv.access_denied'), type = 'error' })
            active = false
            return
        end

        local systems = {}
        for _, system in ipairs(data.systems or {}) do
            local status = system.status and Kora.lang('cctv.status.' .. system.status) or Kora.lang('cctv.status_unknown')
            systems[#systems + 1] = {
                id = system.id, label = system.businessLabel or system.business,
                description = Kora.lang('cctv.cameras_status', tonumber(system.cameraCount) or 0, status),
                icon = 'shield-check', tone = system.status == 'online' and 'success' or 'warning',
            }
        end
        local jobs = {}
        for _, callout in ipairs(data.callouts or {}) do
            local issue = Kora.lang('cctv.issue.' .. (callout.issue or ''))
            local status = Kora.lang('cctv.status.' .. (callout.status or ''))
            jobs[#jobs + 1] = {
                id = callout.id, label = Kora.lang('cctv.callout_label', issue, callout.business),
                description = status, icon = 'wrench', tone = callout.status == 'completed' and 'success' or 'warning',
            }
        end

        Kora.nui.registerApp({
            id = APP_ID, title = Kora.lang('cctv.laptop'), description = Kora.lang('cctv.laptop_description'),
            icon = 'monitor-smartphone', width = 1100, height = 720,
            navigation = {
                { id = 'systems', label = Kora.lang('cctv.installed_systems'), icon = 'shield-check', content = {
                    title = Kora.lang('cctv.company_systems'), description = Kora.lang('cctv.company_systems_description'),
                    blocks = { { type = 'list', layout = 'cards', searchable = true, pageSize = 8, items = systems,
                        empty = Kora.lang('cctv.no_systems') } },
                } },
                { id = 'callouts', label = Kora.lang('cctv.callouts'), icon = 'wrench', badge = #jobs, content = {
                    title = Kora.lang('cctv.service_callouts'), description = Kora.lang('cctv.callouts_description'),
                    blocks = { { type = 'list', layout = 'cards', searchable = true, pageSize = 8, items = jobs,
                        empty = Kora.lang('cctv.no_callouts') } },
                } },
            },
        })
        Kora.nui.openApp(APP_ID)
        active = false
    end)
end

RegisterNetEvent('kora_businesses:cctv:openLaptop', openLaptop)
