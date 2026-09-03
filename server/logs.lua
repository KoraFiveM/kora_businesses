-- Business logging: a durable per-business log line, qblib's own event log, and
-- an optional Discord embed.
--
-- Webhooks are resolved per business rather than per module so a module only
-- has to opt in with a URL when it wants a SEPARATE channel; otherwise the
-- job's channel (and `Config.webhooks.default`) already receives it.

QbBusinesses = QbBusinesses or {}

local Logs = {}
QbBusinesses.logs = Logs

local COLORS = {
    sale = 0x2ecc71,
    stock = 0x3498db,
    payment = 0x9b59b6,
    craft = 0xf1c40f,
    admin = 0xe67e22,
    panic = 0xe74c3c,
}

---@param business table
---@param moduleWebhook? string
---@return string[]
local function webhooksFor(business, moduleWebhook)
    local seen, urls = {}, {}
    local candidates = { moduleWebhook, Config.webhooks[business.job], Config.webhooks.default }
    for _, url in ipairs(candidates) do
        if type(url) == 'string' and url ~= '' and not seen[url] then
            seen[url] = true
            urls[#urls + 1] = url
        end
    end
    return urls
end

---@param src? integer
---@return string|nil citizenid, string name
local function actor(src)
    if not src then return nil, 'System' end
    local data = exports.qbcore:getPlayerData(src)
    if not data then return nil, ('Player %s'):format(tostring(src)) end
    local charinfo = data.charinfo or {}
    local name = data.name
    if not name or name == 'unknown' then
        name = ('%s %s'):format(charinfo.firstname or '', charinfo.lastname or '')
    end
    return data.citizenid, (name:gsub('^%s*(.-)%s*$', '%1'))
end

QbBusinesses.actor = actor

---Records one business event.
---@param business table
---@param entry { category: string, message: string, src?: integer, amount?: number, fields?: table[], webhook?: string }
function Logs.record(business, entry)
    local citizenid, name = actor(entry.src)
    local message = tostring(entry.message):sub(1, 512)

    -- insertAsync, not enqueue: qbsql's write queue coalesces by primary key,
    -- and an append-only AUTO_INCREMENT log has no key to coalesce on -- every
    -- row would merge into one. This still never yields the caller.
    QB.sql.insertAsync([[INSERT INTO `qbbusinesses_logs` (`business`,`category`,`message`,`citizenid`,`amount`)
        VALUES (?,?,?,?,?)]], {
        business.id, entry.category, message, citizenid,
        entry.amount and math.floor(entry.amount) or nil,
    }, function() end)

    QB.logging.event('qbbusinesses:' .. entry.category, entry.src, {
        business = business.id, job = business.job, message = message, amount = entry.amount,
    })

    local urls = webhooksFor(business, entry.webhook)
    if #urls == 0 then return end

    local fields = { { name = 'Business', value = business.label, inline = true } }
    if entry.src then fields[#fields + 1] = { name = 'Player', value = ('%s (%s)'):format(name, tostring(entry.src)), inline = true } end
    for _, field in ipairs(entry.fields or {}) do fields[#fields + 1] = field end

    local embed = QB.discord.createEmbed({
        title = ('%s: %s'):format(business.label, entry.category),
        description = message,
        color = COLORS[entry.category] or 0x95a5a6,
        fields = fields,
        footer = { text = os.date('%c') },
    })

    for _, url in ipairs(urls) do
        QB.discord.sendWebhook(url, { username = 'Businesses', embeds = { embed } })
    end
end

---Trims a business's log history down to `Config.logs.retain` rows.
---@param businessId string
function Logs.trim(businessId)
    -- `id DESC LIMIT 1 OFFSET retain` is the newest row that is already past
    -- the retention window; everything at or below it goes. With fewer than
    -- `retain` rows the subquery is empty, COALESCE yields 0, and nothing is
    -- deleted. The derived table is required: MySQL cannot read the same table
    -- it is deleting from in a bare subquery.
    QB.sql.executeAsync([[DELETE FROM `qbbusinesses_logs`
        WHERE `business` = ? AND `id` <= COALESCE((
            SELECT `cutoff` FROM (
                SELECT `id` AS `cutoff` FROM `qbbusinesses_logs`
                WHERE `business` = ? ORDER BY `id` DESC LIMIT 1 OFFSET ?
            ) AS `bound`
        ), 0)]], { businessId, businessId, math.floor(Config.logs.retain) }, function() end)
end

---@param businessId string
---@param limit? integer
---@return table[]
function Logs.recent(businessId, limit)
    local rows = QB.sql.query([[SELECT `category`, `message`, `amount`, `created_at`
        FROM `qbbusinesses_logs` WHERE `business` = ? ORDER BY `id` DESC LIMIT ?]], {
        businessId, math.min(math.max(math.floor(tonumber(limit) or 25), 1), 100),
    })
    return rows or {}
end
