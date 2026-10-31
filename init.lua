
if Globals and Kora and Kora.config and Kora.config.adopt then
    local businesses = {}
    for name, jobConfig in pairs(Globals) do
        if type(jobConfig) == 'table' then
            businesses[name] = jobConfig
        end
    end

    if next(businesses) then
        Kora.config.adopt(businesses, { fileName = 'businesses.config.local.lua' })
    end
end
