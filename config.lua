Config = {}

Config.enable = {
    mechanic = true,
    taxi = true
}

for job, bool in pairs(Config.enable) do
    if bool then
        if IsDuplicityVersion() then
            QB.require.current('jobs/' .. job .. '/server.lua')
        else
            QB.require.current('jobs/' .. job .. '/client.lua')
        end
        QB.require.current('jobs/' .. job .. '/shared.lua')
    end
end
