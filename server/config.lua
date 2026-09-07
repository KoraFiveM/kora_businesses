-- Server-only qbbusinesses configuration.
--
-- Do not move these settings into ../config.lua: shared scripts are downloaded
-- by every client, which would disclose webhook credentials.

Config.webhooks = {
    -- `default` receives every business event. A per-job key receives that
    -- job's events as well. Empty strings are skipped.
    default = '',
}

-- Webhook URLs are server-only credentials. Register the branch so qblib
-- knows it exists, but explicitly withhold it from the in-game editor and all
-- client snapshots.
if QB and QB.config and QB.config.extend then
    QB.config.extend({
        webhooks = QB.config.object({
            default = QB.config.string(Config.webhooks.default, { sensitive = true }),
        }, { scope = 'server', sensitive = true }),
    }, { scope = 'server' })
end
