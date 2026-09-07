-- Server-only qbbusinesses configuration.
--
-- Do not move these settings into ../config.lua: shared scripts are downloaded
-- by every client, which would disclose webhook credentials.

Config.webhooks = {
    -- `default` receives every business event. A per-job key receives that
    -- job's events as well. Empty strings are skipped.
    default = '',
}
