Config = {}

Config.enable = {
    mechanic = true,
    taxi = true
}

for job, bool in pairs(Config.enable) do
    if bool then
        QB.require.current('jobs/' .. job .. '/shared.lua')
        if IsDuplicityVersion() then
            QB.require.current('jobs/' .. job .. '/server.lua')
        else
            QB.require.current('jobs/' .. job .. '/client.lua')
        end
    end
end
