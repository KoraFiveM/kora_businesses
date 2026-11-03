
-- Register each loaded job's config table next to the job toggles from config.lua. `extend` keeps
-- its own copy, so a bind mirrors the saved/live values back into the table the job code reads.
if Globals and Kora and Kora.config and Kora.config.extend then
    local businesses = {}
    for name, jobConfig in pairs(Globals) do
        if type(jobConfig) == 'table' then
            businesses[name] = jobConfig
        end
    end

    if next(businesses) then
        local resource = GetCurrentResourceName()
        Kora.config.extend(businesses, { skipUnsupported = true })
        for name, jobConfig in pairs(businesses) do
            Kora.config.bind(resource, { name }, function(value)
                if type(value) ~= 'table' then return end
                for key, entry in pairs(value) do
                    jobConfig[key] = entry
                end
            end)
        end
    end
end
