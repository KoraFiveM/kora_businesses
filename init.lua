
if Globals and QB and QB.config and QB.config.adopt then
    local businesses = {}
    for name, jobConfig in pairs(Globals) do
        if type(jobConfig) == 'table' then
            businesses[name] = jobConfig
        end
    end

    if next(businesses) then
        QB.config.adopt(businesses, { fileName = 'businesses.config.local.lua' })
    end
end
