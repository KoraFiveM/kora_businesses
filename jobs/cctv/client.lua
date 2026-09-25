-- CCTV has no client authority. The phone and management resources consume the
-- server callbacks exposed by jobs/cctv/server.lua.
local APP_ID = 'qbbusinesses:cctv-laptop'
local active = false

local function openLaptop()
    if active then return end
    active = true
    CreateThread(function()
        local data, err = QB.callback.trigger('qbbusinesses:cctv:laptopData')
        if not data then
            QB.notify.send({ title = 'CCTV', message = err or 'Laptop access denied.', type = 'error' })
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

        QB.nui.registerApp({
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
        QB.nui.openApp(APP_ID)
        active = false
    end)
end

RegisterNetEvent('qbbusinesses:cctv:openLaptop', openLaptop)
