Config = {}

Config.enable = {
    mechanic = true,
    taxi = true
}

for job, bool in pairs(Config.enable) do
    if bool then
        if IsDuplicityVersion() then
            QB.require.current('server/' .. job .. '.lua')
        else
            QB.require.current('client/' .. job .. '.lua')
        end
        QB.require.current('shared/' .. job .. '.lua')
    end
end