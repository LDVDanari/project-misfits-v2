-- ============================================================
-- PMv2 STORE - SERVER
-- ============================================================
-- Reads the store tables (db/pmv2_store.sql) that projectmisfitsrp.com writes:
--   * links each player's Discord account to their character
--   * hands over anything waiting in pmv2_store_deliveries while they're online
--   * Misfit Coins: /coins, plus exports other scripts use to spend them
--   * staff tools: /coinsadd, /coinsremove, /storelookup, /storedone
--   * the in-city VIP shop + VIP tiers live in server/vip/ and spend from this same wallet
--
-- Players are matched by the Discord account FiveM sees (Discord must be open
-- when they launch FiveM). That's the same account they log in with at checkout.

local handlers = {}  -- delivery handlers by action name
local linked = {}    -- [source] = 'discordId:citizenid' once linked this session
local busy = {}      -- [customerId] = true while a coin change is running
local ready = false

local function log(msg)
    print(('[pmv2_store] %s'):format(msg))
end

local function debug(msg)
    if Config.Debug then log(msg) end
end

local function notify(src, text, kind, duration)
    if not src or src <= 0 then
        log(text)
        return
    end
    TriggerClientEvent('ox_lib:notify', src, {
        title = 'PMv2 Store',
        description = text,
        type = kind or 'inform',
        duration = duration or 7000
    })
end

-- ------------------------------------------------------------
-- Player helpers
-- ------------------------------------------------------------

local function discordOf(src)
    local id = GetPlayerIdentifierByType(src, 'discord')
    if not id then return nil end
    id = id:gsub('^discord:', '')
    return id:match('^%d+$') and id or nil
end

local function citizenOf(src)
    local player = exports.qbx_core:GetPlayer(src)
    return player and player.PlayerData and player.PlayerData.citizenid or nil
end

local function displayName(src)
    if src == 0 then return 'Console' end
    return GetPlayerName(src) or ('ID %s'):format(src)
end

local function onlinePlayers()
    local list = {}
    for _, s in ipairs(GetPlayers()) do
        local src = tonumber(s)
        local discordId, citizenid = discordOf(src), citizenOf(src)
        if discordId and citizenid then
            list[#list + 1] = { src = src, discord = discordId, citizenid = citizenid }
        end
    end
    return list
end

-- Accepts an online server ID or a Discord ID. Returns discordId, onlineSource.
local function resolveTarget(target)
    target = tostring(target or ''):gsub('^discord:', '')
    local asNumber = tonumber(target)
    if asNumber and #target <= 6 and GetPlayerName(asNumber) then
        return discordOf(asNumber), asNumber
    end
    if target:match('^%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d+$') then
        for _, s in ipairs(GetPlayers()) do
            if discordOf(tonumber(s)) == target then return target, tonumber(s) end
        end
        return target, nil
    end
    return nil, nil
end

local function customerByDiscord(discordId)
    return MySQL.single.await([[
        SELECT c.id, c.discord_id, c.discord_username, COALESCE(w.balance, 0) AS coins
        FROM pmv2_store_customers c
        LEFT JOIN pmv2_store_wallets w ON w.customer_id = c.id
        WHERE c.discord_id = ?
    ]], { discordId })
end

-- Finds the customer + wallet. Only creates a new account for a player who's online right now,
-- so a mistyped Discord ID can't create a made-up account.
local function ensureCustomer(discordId, online)
    if online then
        MySQL.insert.await(
            'INSERT INTO pmv2_store_customers (discord_id) VALUES (?) ON DUPLICATE KEY UPDATE discord_id = discord_id',
            { discordId }
        )
    end
    local row = MySQL.single.await('SELECT id FROM pmv2_store_customers WHERE discord_id = ?', { discordId })
    if not row then return nil end
    MySQL.insert.await(
        'INSERT INTO pmv2_store_wallets (customer_id) VALUES (?) ON DUPLICATE KEY UPDATE customer_id = customer_id',
        { row.id }
    )
    return row.id
end

local function audit(actor, action, targetType, targetId, details)
    MySQL.insert(
        'INSERT INTO pmv2_store_audit_log (actor, action, target_type, target_id, details) VALUES (?, ?, ?, ?, ?)',
        { actor, action, targetType, targetId and tostring(targetId) or nil, details and json.encode(details) or nil }
    )
end

-- ------------------------------------------------------------
-- Discord logs
-- ------------------------------------------------------------

local COLORS = { spend = 0xa200ec, add = 0x2ecc71, remove = 0xe67e22, delivery = 0x3498db, done = 0xf1c40f, fail = 0xe74c3c }

local function who(src)
    if not src or src == 0 then return 'Console' end
    local player = exports.qbx_core:GetPlayer(src)
    local info = player and player.PlayerData and player.PlayerData.charinfo
    local char = info and ('%s %s'):format(info.firstname or '', info.lastname or ''):gsub('^%s+', ''):gsub('%s+$', '') or nil
    local cid = player and player.PlayerData and player.PlayerData.citizenid
    local discordId = discordOf(src)
    return ('%s%s (ID %s%s)%s'):format(
        GetPlayerName(src) or 'Unknown',
        char and char ~= '' and (' / ' .. char) or '',
        src,
        cid and (', ' .. cid) or '',
        discordId and (' <@' .. discordId .. '>') or '')
end

local function sendLog(title, color, fields, description)
    local url = Config.LogWebhook
    if type(url) ~= 'string' or not url:match('^https://[%w%.]*discord[%w]*%.com/api/webhooks/') then return end
    local embedFields = {}
    for _, f in ipairs(fields or {}) do
        embedFields[#embedFields + 1] = { name = f[1], value = tostring(f[2] or '-'):sub(1, 1000), inline = f[3] == true }
    end
    PerformHttpRequest(url, function(code)
        if code and code >= 300 then log(('Discord log failed (HTTP %s)'):format(code)) end
    end, 'POST', json.encode({
        username = Config.LogName or 'PMv2 Store Logs',
        allowed_mentions = { parse = {} },
        embeds = { {
            title = title,
            description = description,
            color = color,
            fields = embedFields,
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
            footer = { text = GetConvar('sv_hostname', 'PMv2'):sub(1, 60) }
        } }
    }), { ['Content-Type'] = 'application/json' })
end

local function balanceLine(before, after)
    return ('%s → %s'):format(before, after)
end

local function uniqueKey(prefix, customerId)
    return ('%s:%s:%s:%06d'):format(prefix, customerId, os.time(), math.random(0, 999999))
end

-- ------------------------------------------------------------
-- Linking players to their store account
-- ------------------------------------------------------------

local function link(p)
    local key = p.discord .. ':' .. p.citizenid
    if linked[p.src] == key then return end
    linked[p.src] = key
    MySQL.update(
        'UPDATE pmv2_store_customers SET fivem_license = ?, last_citizenid = ?, last_seen_ingame = CURRENT_TIMESTAMP(3) WHERE discord_id = ?',
        { GetPlayerIdentifierByType(p.src, 'license'), p.citizenid, p.discord }
    )
end

AddEventHandler('playerDropped', function()
    linked[source] = nil
end)

-- ------------------------------------------------------------
-- Deliveries
-- ------------------------------------------------------------

handlers.notify = function(src, payload)
    notify(src, payload.message or 'Your store purchase has arrived.', 'success', 12000)
    return true
end

handlers.give_item = function(src, payload)
    if not Config.ItemDeliveries then return false, 'item deliveries are turned off' end
    local item, count = payload.item, math.floor(tonumber(payload.count) or 1)
    if type(item) ~= 'string' or count < 1 then return false, 'delivery has no item' end
    if not exports.ox_inventory:CanCarryItem(src, item, count) then
        notify(src, 'You have a store item waiting, but your pockets are full. Make some room.', 'warning')
        return false, 'inventory full'
    end
    local ok, response = exports.ox_inventory:AddItem(src, item, count, payload.metadata)
    if not ok then return false, tostring(response) end
    notify(src, payload.message or ('You received %sx %s from the store.'):format(count, item), 'success', 12000)
    return true
end

-- Other resources can add their own delivery types (vehicles, houses...).
-- fn(source, payload, row) must return true, or false + a reason.
exports('RegisterDeliveryHandler', function(action, fn)
    if type(action) == 'string' and fn then handlers[action] = fn end
end)

local PENDING = "(status = 'pending' OR (status = 'claimed' AND claimed_at < (CURRENT_TIMESTAMP(3) - INTERVAL 5 MINUTE)))"

local function processDeliveries(players)
    if #players == 0 then return end
    local byDiscord, ids = {}, {}
    for _, p in ipairs(players) do
        byDiscord[p.discord] = p
        ids[#ids + 1] = p.discord
    end

    local placeholders = ('?,'):rep(#ids):sub(1, -2)
    local rows = MySQL.query.await(
        ('SELECT id, discord_id, action, payload, attempts FROM pmv2_store_deliveries WHERE discord_id IN (%s) AND %s ORDER BY id LIMIT 50')
            :format(placeholders, PENDING),
        ids
    ) or {}

    for _, row in ipairs(rows) do
        local p = byDiscord[row.discord_id]
        -- Claim it first so it can never be handed out twice.
        local claimed = MySQL.update.await(
            ("UPDATE pmv2_store_deliveries SET status = 'claimed', claimed_at = CURRENT_TIMESTAMP(3), attempts = attempts + 1 WHERE id = ? AND %s"):format(PENDING),
            { row.id }
        )
        if claimed == 1 and p and GetPlayerName(p.src) then
            local payload = row.payload
            if type(payload) == 'string' then payload = json.decode(payload) end
            if type(payload) ~= 'table' then payload = {} end

            local handler = handlers[row.action]
            local ok, err
            if not handler then
                ok, err = false, 'no handler for "' .. tostring(row.action) .. '"'
            else
                local success, result, reason = pcall(handler, p.src, payload, row)
                if success then ok, err = result, reason else ok, err = false, tostring(result) end
            end

            if ok then
                MySQL.update.await(
                    "UPDATE pmv2_store_deliveries SET status = 'delivered', delivered_to = ?, delivered_at = CURRENT_TIMESTAMP(3), last_error = NULL WHERE id = ?",
                    { p.citizenid, row.id }
                )
                debug(('Delivered #%s (%s) to %s'):format(row.id, row.action, p.citizenid))
                local what = payload.message or (payload.item and ('%sx %s'):format(payload.count or 1, payload.item)) or row.action
                local fields = { { 'Player', who(p.src) }, { 'Delivered', what } }
                if payload.order_ref then fields[#fields + 1] = { 'Order', payload.order_ref, true } end
                if payload.coins then
                    local c = customerByDiscord(p.discord)
                    fields[#fields + 1] = { Config.CoinName .. ' now', c and c.coins or '?', true }
                end
                sendLog('Store delivery received', COLORS.delivery, fields)
            else
                local attempts = (tonumber(row.attempts) or 0) + 1
                local status = attempts >= Config.MaxAttempts and 'failed' or 'pending'
                MySQL.update.await(
                    'UPDATE pmv2_store_deliveries SET status = ?, last_error = ? WHERE id = ?',
                    { status, tostring(err or 'unknown error'):sub(1, 250), row.id }
                )
                log(('Delivery #%s (%s) for %s failed (%s/%s): %s'):format(row.id, row.action, p.citizenid, attempts, Config.MaxAttempts, tostring(err)))
                if status == 'failed' then
                    sendLog('Store delivery FAILED', COLORS.fail, {
                        { 'Player', who(p.src) }, { 'Delivery', ('#%s %s'):format(row.id, row.action), true },
                        { 'Why', tostring(err) }, { 'Next step', 'Fix the cause, then set its status back to pending (or hand it out by hand).' }
                    })
                end
            end
        elseif claimed == 1 then
            -- Player left between the lookup and the claim: put it back.
            MySQL.update.await("UPDATE pmv2_store_deliveries SET status = 'pending', attempts = attempts - 1 WHERE id = ?", { row.id })
        end
    end
end

local function check(players)
    if not ready then return end
    for _, p in ipairs(players) do link(p) end
    processDeliveries(players)
end

CreateThread(function()
    while not ready do Wait(1000) end
    while true do
        local ok, err = pcall(check, onlinePlayers())
        if not ok then log('Check failed: ' .. tostring(err)) end
        Wait(math.max(10, Config.CheckSeconds) * 1000)
    end
end)

-- Check right after someone loads a character instead of waiting for the next round.
local function checkSoon(src)
    SetTimeout(5000, function()
        local discordId, citizenid = discordOf(src), citizenOf(src)
        if discordId and citizenid then
            local ok, err = pcall(check, { { src = src, discord = discordId, citizenid = citizenid } })
            if not ok then log('Check failed: ' .. tostring(err)) end
        end
    end)
end

AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    local src = player and player.PlayerData and player.PlayerData.source
    if src then checkSoon(src) end
end)

-- ------------------------------------------------------------
-- Misfit Coins
-- ------------------------------------------------------------

local function getCoins(src)
    local discordId = discordOf(src)
    if not discordId then return 0, 'no_discord' end
    local customer = customerByDiscord(discordId)
    return customer and tonumber(customer.coins) or 0
end

-- Takes coins only if the player has enough. Returns true, newBalance  or  false, reason.
-- reason: 'invalid_amount', 'no_discord', 'not_enough_coins', 'busy', 'error'
local function spendCoins(src, amount, reference)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'invalid_amount' end
    local discordId = discordOf(src)
    if not discordId then return false, 'no_discord' end
    local customer = MySQL.single.await('SELECT id FROM pmv2_store_customers WHERE discord_id = ?', { discordId })
    if not customer then return false, 'not_enough_coins' end
    if busy[customer.id] then return false, 'busy' end

    busy[customer.id] = true
    local key = uniqueKey('spend', customer.id)
    local actor = ('city:%s'):format(citizenOf(src) or discordId)
    local ok, done = pcall(MySQL.transaction.await, {
        -- Both statements only do anything if the balance covers it, and run all-or-nothing.
        {
            query = [[INSERT INTO pmv2_store_coin_ledger (customer_id, delta, reason, balance_after, reference, idempotency_key, actor)
                      SELECT customer_id, ?, 'spend', balance - ?, ?, ?, ? FROM pmv2_store_wallets WHERE customer_id = ? AND balance >= ? FOR UPDATE]],
            values = { -amount, amount, tostring(reference or 'In-city purchase'):sub(1, 128), key, actor, customer.id, amount }
        },
        {
            query = 'UPDATE pmv2_store_wallets SET balance = balance - ?, lifetime_spent = lifetime_spent + ? WHERE customer_id = ? AND balance >= ?',
            values = { amount, amount, customer.id, amount }
        }
    })
    busy[customer.id] = nil

    if not ok or not done then
        log(('SpendCoins failed for %s: %s'):format(discordId, tostring(done)))
        return false, 'error'
    end
    local entry = MySQL.single.await('SELECT balance_after FROM pmv2_store_coin_ledger WHERE idempotency_key = ?', { key })
    if not entry then return false, 'not_enough_coins' end
    local after = tonumber(entry.balance_after)
    sendLog(('%s spent'):format(Config.CoinName), COLORS.spend, {
        { 'Player', who(src) },
        { 'Bought', tostring(reference or 'In-city purchase') },
        { 'Cost', amount, true },
        { 'Balance', balanceLine(after + amount, after), true },
        { 'Script', GetInvokingResource() or 'pmv2_store', true }
    })
    return true, after
end

-- Adds (or with a negative amount, removes) coins. Removing never goes below 0.
-- target: online server ID or Discord ID. Returns true, newBalance  or  false, reason.
local function adjustCoins(target, delta, reason, actor, staffSrc)
    delta = math.floor(tonumber(delta) or 0)
    if delta == 0 then return false, 'invalid_amount' end
    local discordId, online = resolveTarget(target)
    if not discordId then return false, 'player_not_found' end

    local customerId = ensureCustomer(discordId, online)
    if not customerId then return false, 'no_account' end
    if busy[customerId] then return false, 'busy' end
    busy[customerId] = true

    local key = uniqueKey(delta > 0 and 'grant' or 'remove', customerId)
    local kind = delta > 0 and 'admin_grant' or 'admin_remove'
    -- Removals only go through if the balance covers them; grants always do.
    local guard = delta > 0 and '' or ' AND balance + ? >= 0'
    local insertValues = { delta, kind, delta, tostring(reason or 'Staff adjustment'):sub(1, 128), key, actor, customerId }
    local updateValues = { delta, customerId }
    if delta < 0 then
        insertValues[#insertValues + 1] = delta
        updateValues[#updateValues + 1] = delta
    end
    local ok, done = pcall(MySQL.transaction.await, {
        {
            query = [[INSERT INTO pmv2_store_coin_ledger (customer_id, delta, reason, balance_after, reference, idempotency_key, actor)
                      SELECT customer_id, ?, ?, balance + ?, ?, ?, ? FROM pmv2_store_wallets WHERE customer_id = ?]] .. guard .. ' FOR UPDATE',
            values = insertValues
        },
        {
            query = 'UPDATE pmv2_store_wallets SET balance = balance + ? WHERE customer_id = ?' .. guard,
            values = updateValues
        }
    })
    busy[customerId] = nil

    if not ok or not done then
        log(('Coin change failed for %s: %s'):format(discordId, tostring(done)))
        return false, 'error'
    end
    local entry = MySQL.single.await('SELECT balance_after FROM pmv2_store_coin_ledger WHERE idempotency_key = ?', { key })
    if not entry then return false, 'not_enough_coins' end

    audit(actor, 'coins.' .. kind, 'customer', discordId, { delta = delta, reason = reason, balance_after = entry.balance_after })
    local after = tonumber(entry.balance_after)
    sendLog(delta > 0 and ('%s added'):format(Config.CoinName) or ('%s removed'):format(Config.CoinName), delta > 0 and COLORS.add or COLORS.remove, {
        { 'Player', online and who(online) or ('<@%s> (offline, Discord %s)'):format(discordId, discordId) },
        { 'By', staffSrc and who(staffSrc) or actor },
        { 'Amount', (delta > 0 and '+' or '') .. delta, true },
        { 'Balance', balanceLine(after - delta, after), true },
        { 'Reason', tostring(reason or '-') }
    })
    if online then
        notify(online, delta > 0
            and ('%s %s were added to your account.'):format(delta, Config.CoinName)
            or ('%s %s were removed from your account.'):format(-delta, Config.CoinName),
            delta > 0 and 'success' or 'inform')
    end
    return true, tonumber(entry.balance_after)
end

exports('GetCoins', function(src) return (getCoins(src)) end)
exports('SpendCoins', spendCoins)
exports('AddCoins', function(target, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'invalid_amount' end
    return adjustCoins(target, amount, reason or 'Script grant', 'script:' .. (GetInvokingResource() or 'unknown'))
end)
exports('GetDiscordId', discordOf)

-- Shared with the VIP shop files in server/vip/ (same resource, so no export round-trip).
Store = {
    GetCoins = getCoins,                 -- (src) -> coins, 'no_discord'?
    SpendCoins = spendCoins,             -- (src, amount, reference) -> ok, newBalance | reason
    -- (src or Discord ID, amount, reason) -> ok, newBalance | reason
    GiveCoins = function(target, amount, reason)
        amount = math.floor(tonumber(amount) or 0)
        if amount <= 0 then return false, 'invalid_amount' end
        return adjustCoins(target, amount, reason or 'VIP shop', 'pmv2_store:vip')
    end,
    DiscordOf = discordOf,
    CustomerByDiscord = customerByDiscord,
    Log = sendLog,                       -- (title, color, fields{{name, value, inline?}}, description?)
    Who = who,
    Colors = COLORS,
    RegisterDeliveryHandler = function(action, fn) handlers[action] = fn end,
}

-- ------------------------------------------------------------
-- Tebex purchases
-- ------------------------------------------------------------
-- Tebex (the payment processor) runs these from the server console. Set them on each
-- coin package in the Tebex control panel ("execute even if the player is offline"):
--   pmv2_tebex {id} {transaction} {packageId} {purchaseQuantity} <coins in one package>
--   pmv2_tebex_reverse {id} {transaction} {packageId} {purchaseQuantity} <coins in one package>   (refund + chargeback)
-- {id} is the buyer's FiveM (Cfx.re) account. Every purchase is saved first, then credited to
-- the Discord-linked wallet of whoever plays on that FiveM account: right away if they're
-- online, otherwise the next time they load in. A transaction is only ever credited once.

local NO_DISCORD_TEBEX = 'Your store purchase is waiting! Open the Discord app before launching FiveM, then reconnect so we know which account to credit.'
local tebexBusy, tebexWarned = {}, {}

MySQL.ready(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS pmv2_store_tebex (
            id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            tx_key         VARCHAR(160) NOT NULL,
            kind           ENUM('purchase','reversal') NOT NULL,
            transaction_id VARCHAR(64)  NOT NULL,
            package_id     VARCHAR(32)  NOT NULL,
            identifier     VARCHAR(64)  NOT NULL,
            quantity       INT UNSIGNED NOT NULL DEFAULT 1,
            coins          INT UNSIGNED NOT NULL,
            status         ENUM('pending','delivered','canceled') NOT NULL DEFAULT 'pending',
            discord_id     VARCHAR(32)  NULL,
            created_at     DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
            delivered_at   DATETIME(3)  NULL,
            PRIMARY KEY (id),
            UNIQUE KEY uq_tebex_tx (tx_key),
            KEY idx_tebex_pending (status, identifier)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
end)

-- "123" -> "fivem:123"; "license:abc" stays as-is.
local function tebexIdentifier(raw)
    raw = tostring(raw or ''):gsub('%s', '')
    local kind, value = raw:match('^(%a%w*):([%w]+)$')
    if kind then return kind:lower() .. ':' .. value end
    if raw:match('^%d+$') then return 'fivem:' .. raw end
    return nil
end

local function onlineByIdentifier(identifier)
    for _, s in ipairs(GetPlayers()) do
        local src = tonumber(s)
        for _, id in ipairs(GetPlayerIdentifiers(src)) do
            if id == identifier then return src end
        end
    end
    return nil
end

local function parseTebexArgs(args)
    local identifier = tebexIdentifier(args[1])
    local tx = tostring(args[2] or ''):match('^[%w%-_%.]+$')
    local pkg = tostring(args[3] or ''):match('^[%w%-_]+$')
    local qty = math.floor(tonumber(args[4]) or 0)
    local per = math.floor(tonumber(args[5]) or 0)
    if not identifier or not tx or not pkg or qty < 1 or qty > 1000 or per < 1 or per > 1000000 then return nil end
    return { identifier = identifier, tx = tx:sub(1, 64), pkg = pkg:sub(1, 32), qty = qty, coins = per * qty }
end

local function waitReady()
    local t = 0
    while not ready and t < 60 do Wait(1000); t = t + 1 end
    return ready
end

-- Ledger row + wallet change in one transaction. The unique idempotency key means a second
-- attempt for the same purchase fails instead of paying twice. Reversals have no floor:
-- if refunded coins were already spent the balance goes negative (by design).
local function tebexLedger(customerId, delta, reason, reference, key)
    local ok, done = pcall(MySQL.transaction.await, {
        {
            query = [[INSERT INTO pmv2_store_coin_ledger (customer_id, delta, reason, balance_after, reference, idempotency_key, actor)
                      SELECT customer_id, ?, ?, balance + ?, ?, ?, 'tebex' FROM pmv2_store_wallets WHERE customer_id = ? FOR UPDATE]],
            values = { delta, reason, delta, reference:sub(1, 128), key, customerId }
        },
        {
            query = 'UPDATE pmv2_store_wallets SET balance = balance + ?, lifetime_purchased = lifetime_purchased + ? WHERE customer_id = ?',
            values = { delta, delta > 0 and delta or 0, customerId }
        }
    })
    local entry = MySQL.single.await('SELECT balance_after FROM pmv2_store_coin_ledger WHERE idempotency_key = ?', { key })
    if entry then return tonumber(entry.balance_after), ok and done end
    return nil, tostring(done)
end

local function deliverTebex(row, src)
    if row.status ~= 'pending' or tebexBusy[row.tx_key] then return false end
    local discordId = discordOf(src)
    if not discordId then
        if not tebexWarned[src] then
            tebexWarned[src] = true
            notify(src, NO_DISCORD_TEBEX, 'error', 15000)
        end
        return false
    end

    tebexBusy[row.tx_key] = true
    local customerId = ensureCustomer(discordId, true)
    local after, fresh = nil, false
    if customerId then
        after, fresh = tebexLedger(customerId, row.coins, 'purchase', ('Tebex %s'):format(row.transaction_id), 'tebex:' .. row.tx_key)
    end
    tebexBusy[row.tx_key] = nil
    if not after then
        log(('Tebex %s: could not credit %s yet: %s'):format(row.transaction_id, discordId, tostring(fresh)))
        return false
    end

    MySQL.update.await(
        "UPDATE pmv2_store_tebex SET status = 'delivered', discord_id = ?, delivered_at = CURRENT_TIMESTAMP(3) WHERE id = ?",
        { discordId, row.id }
    )
    if fresh then
        audit('tebex', 'coins.purchase', 'customer', discordId, { coins = row.coins, transaction = row.transaction_id, package = row.package_id })
        sendLog(('%s purchased'):format(Config.CoinName), COLORS.add, {
            { 'Player', who(src) },
            { 'Coins', ('+%d (%dx package %s)'):format(row.coins, row.quantity, row.package_id), true },
            { 'Balance', balanceLine(after - row.coins, after), true },
            { 'Transaction', row.transaction_id, true }
        })
        notify(src, ('Thanks for your purchase! %d %s were added to your account.'):format(row.coins, Config.CoinName), 'success', 12000)
    end
    return true
end

-- Credits any waiting purchases for players who are online now.
local function processTebex(onlySrc)
    if not ready then return end
    local rows = MySQL.query.await("SELECT * FROM pmv2_store_tebex WHERE kind = 'purchase' AND status = 'pending' ORDER BY id LIMIT 200") or {}
    for _, row in ipairs(rows) do
        local src = onlineByIdentifier(row.identifier)
        if src and (not onlySrc or src == onlySrc) then deliverTebex(row, src) end
    end
end

CreateThread(function()
    while not ready do Wait(1000) end
    while true do
        local ok, err = pcall(processTebex)
        if not ok then log('Tebex check failed: ' .. tostring(err)) end
        Wait(math.max(10, Config.CheckSeconds) * 1000)
    end
end)

AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    local src = player and player.PlayerData and player.PlayerData.source
    if src then SetTimeout(6000, function() pcall(processTebex, src) end) end
end)

AddEventHandler('playerDropped', function()
    tebexWarned[source] = nil
end)

RegisterCommand('pmv2_tebex', function(source, args)
    if source ~= 0 then return end
    local p = parseTebexArgs(args)
    if not p then
        log('pmv2_tebex: wrong format. Use: pmv2_tebex {id} {transaction} {packageId} {purchaseQuantity} <coins per package>')
        return
    end
    CreateThread(function()
        if not waitReady() then
            log(('pmv2_tebex: store tables missing - purchase %s was NOT recorded. Run db/pmv2_store.sql.'):format(p.tx))
            return
        end
        local key = ('buy:%s:%s'):format(p.tx, p.pkg)
        MySQL.insert.await(
            "INSERT IGNORE INTO pmv2_store_tebex (tx_key, kind, transaction_id, package_id, identifier, quantity, coins) VALUES (?, 'purchase', ?, ?, ?, ?, ?)",
            { key, p.tx, p.pkg, p.identifier, p.qty, p.coins }
        )
        local row = MySQL.single.await('SELECT * FROM pmv2_store_tebex WHERE tx_key = ?', { key })
        if not row then return log(('pmv2_tebex: could not save purchase %s'):format(p.tx)) end
        if row.status ~= 'pending' then return log(('Tebex %s already %s - skipped.'):format(p.tx, row.status)) end

        -- Refunded before it was ever credited
        if MySQL.scalar.await('SELECT COUNT(*) FROM pmv2_store_tebex WHERE tx_key = ?', { ('rev:%s:%s'):format(p.tx, p.pkg) }) > 0 then
            MySQL.update.await("UPDATE pmv2_store_tebex SET status = 'canceled' WHERE id = ?", { row.id })
            return log(('Tebex %s was already refunded - not credited.'):format(p.tx))
        end

        log(('Tebex purchase %s: %d %s for %s'):format(p.tx, p.coins, Config.CoinName, p.identifier))
        local src = onlineByIdentifier(p.identifier)
        if src and deliverTebex(row, src) then return end
        sendLog(('%s purchase received'):format(Config.CoinName), COLORS.delivery, {
            { 'FiveM account', p.identifier, true },
            { 'Coins', p.coins, true },
            { 'Transaction', p.tx, true }
        }, src and 'Buyer is online but FiveM can\'t see their Discord - credited once it can.'
            or 'Buyer is offline - the coins are credited the next time they load in.')
    end)
end, true)

RegisterCommand('pmv2_tebex_reverse', function(source, args)
    if source ~= 0 then return end
    local p = parseTebexArgs(args)
    if not p then
        log('pmv2_tebex_reverse: wrong format. Use the same arguments as pmv2_tebex.')
        return
    end
    CreateThread(function()
        if not waitReady() then
            log(('pmv2_tebex_reverse: store tables missing - reversal %s NOT applied.'):format(p.tx))
            return
        end
        local revKey = ('rev:%s:%s'):format(p.tx, p.pkg)
        MySQL.insert.await(
            "INSERT IGNORE INTO pmv2_store_tebex (tx_key, kind, transaction_id, package_id, identifier, quantity, coins) VALUES (?, 'reversal', ?, ?, ?, ?, ?)",
            { revKey, p.tx, p.pkg, p.identifier, p.qty, p.coins }
        )
        local rev = MySQL.single.await('SELECT * FROM pmv2_store_tebex WHERE tx_key = ?', { revKey })
        if not rev or rev.status ~= 'pending' then return end
        local buy = MySQL.single.await('SELECT * FROM pmv2_store_tebex WHERE tx_key = ?', { ('buy:%s:%s'):format(p.tx, p.pkg) })

        -- Never credited (or unknown): make sure it never pays out.
        if not buy or buy.status ~= 'delivered' then
            if buy and buy.status == 'pending' then
                MySQL.update.await("UPDATE pmv2_store_tebex SET status = 'canceled' WHERE id = ?", { buy.id })
            end
            MySQL.update.await("UPDATE pmv2_store_tebex SET status = 'delivered', delivered_at = CURRENT_TIMESTAMP(3) WHERE id = ?", { rev.id })
            log(('Tebex %s refunded/charged back before delivery - nothing to take back.'):format(p.tx))
            return sendLog('Tebex purchase canceled', COLORS.remove, {
                { 'FiveM account', p.identifier, true }, { 'Transaction', p.tx, true }
            }, 'Refunded or charged back before the coins were credited. Nothing was taken back.')
        end

        local customer = MySQL.single.await('SELECT id FROM pmv2_store_customers WHERE discord_id = ?', { buy.discord_id })
        if not customer then return log(('Tebex %s: customer %s not found for reversal'):format(p.tx, tostring(buy.discord_id))) end
        local after, fresh = tebexLedger(customer.id, -buy.coins, 'refund', ('Tebex refund/chargeback %s'):format(p.tx), 'tebex:' .. revKey)
        if not after then return log(('Tebex %s: reversal failed: %s'):format(p.tx, tostring(fresh))) end

        MySQL.update.await(
            "UPDATE pmv2_store_tebex SET status = 'delivered', discord_id = ?, delivered_at = CURRENT_TIMESTAMP(3) WHERE id = ?",
            { buy.discord_id, rev.id }
        )
        if fresh then
            audit('tebex', 'coins.refund', 'customer', buy.discord_id, { coins = -buy.coins, transaction = p.tx })
            local _, online = resolveTarget(buy.discord_id)
            sendLog(('%s taken back (Tebex refund/chargeback)'):format(Config.CoinName), COLORS.remove, {
                { 'Player', online and who(online) or ('<@%s>'):format(buy.discord_id) },
                { 'Coins', -buy.coins, true },
                { 'Balance', balanceLine(after + buy.coins, after), true },
                { 'Transaction', p.tx, true }
            })
            if online then
                notify(online, ('%d %s were removed because a store payment was refunded or charged back.'):format(buy.coins, Config.CoinName), 'inform', 12000)
            end
        end
    end)
end, true)

-- ------------------------------------------------------------
-- Commands
-- ------------------------------------------------------------

local NO_DISCORD = 'We can\'t see your Discord account. Open the Discord app before launching FiveM, then reconnect.'

lib.addCommand('coins', {
    help = ('Check your %s'):format(Config.CoinName)
}, function(source)
    if source == 0 then return end
    local coins, err = getCoins(source)
    if err == 'no_discord' then return notify(source, NO_DISCORD, 'error', 10000) end
    notify(source, ('You have %s %s. Get more at %s'):format(coins, Config.CoinName, Config.StoreUrl), 'inform', 9000)
end)

local REASONS = {
    player_not_found = 'Player not found. Use their server ID (online) or Discord ID.',
    no_account = 'No store account for that Discord ID. Check the ID, or do it while they\'re in the city.',
    not_enough_coins = 'They don\'t have that many coins.',
    busy = 'Their coins are being changed right now. Try again.',
    invalid_amount = 'Amount must be a whole number above 0.',
    error = 'Database error, check the server console.'
}

lib.addCommand('coinsadd', {
    help = ('Give a player %s'):format(Config.CoinName),
    params = {
        { name = 'target', help = 'Server ID or Discord ID' }, -- no type: ox_lib's "string" type rejects numbers
        { name = 'amount', type = 'number', help = 'How many' },
        { name = 'reason', type = 'longString', help = 'Reason (saved in the log)' }
    },
    restricted = Config.StaffGroups
}, function(source, args)
    local amount = math.floor(tonumber(args.amount) or 0)
    if amount <= 0 then return notify(source, REASONS.invalid_amount, 'error') end
    local ok, result = adjustCoins(args.target, amount, args.reason, ('staff:%s'):format(displayName(source)), source)
    notify(source, ok and ('Done. New balance: %s'):format(result) or REASONS[result] or result, ok and 'success' or 'error')
end)

lib.addCommand('coinsremove', {
    help = ('Take %s from a player'):format(Config.CoinName),
    params = {
        { name = 'target', help = 'Server ID or Discord ID' }, -- no type: ox_lib's "string" type rejects numbers
        { name = 'amount', type = 'number', help = 'How many' },
        { name = 'reason', type = 'longString', help = 'Reason (saved in the log)' }
    },
    restricted = Config.StaffGroups
}, function(source, args)
    local amount = math.floor(tonumber(args.amount) or 0)
    if amount <= 0 then return notify(source, REASONS.invalid_amount, 'error') end
    local ok, result = adjustCoins(args.target, -amount, args.reason, ('staff:%s'):format(displayName(source)), source)
    notify(source, ok and ('Done. New balance: %s'):format(result) or REASONS[result] or result, ok and 'success' or 'error')
end)

lib.addCommand('storelookup', {
    help = 'Show a player\'s store orders, coins and anything stuck (prints to F8)',
    params = {
        { name = 'target', help = 'Server ID, Discord ID or order code (PM-XXXXXX)' }
    },
    restricted = Config.StaffGroups
}, function(source, args)
    local target = tostring(args.target or '')
    local discordId
    if target:upper():match('^PM%-%w+$') then
        local order = MySQL.single.await('SELECT discord_id FROM pmv2_store_orders WHERE order_ref = ?', { target:upper() })
        discordId = order and order.discord_id
    else
        discordId = resolveTarget(target)
    end
    if not discordId then return notify(source, REASONS.player_not_found, 'error') end

    local customer = customerByDiscord(discordId)
    if not customer then return notify(source, 'No store account for that player yet.', 'inform') end

    local lines = { ('---- Store: %s (Discord %s) ----'):format(customer.discord_username or 'unknown', discordId),
                    ('%s: %s'):format(Config.CoinName, customer.coins) }
    local orders = MySQL.query.await([[
        SELECT order_ref, status, amount_total, DATE_FORMAT(created_at, '%Y-%m-%d') AS day
        FROM pmv2_store_orders WHERE customer_id = ? ORDER BY id DESC LIMIT 8
    ]], { customer.id }) or {}
    lines[#lines + 1] = ('Orders (latest %s):'):format(#orders)
    for _, o in ipairs(orders) do
        lines[#lines + 1] = ('  %s  %s  $%.2f  %s'):format(o.order_ref, o.status, (tonumber(o.amount_total) or 0) / 100, o.day)
    end
    local waiting = MySQL.query.await([[
        SELECT e.product_slug, JSON_UNQUOTE(JSON_EXTRACT(e.details, '$.order_ref')) AS order_ref
        FROM pmv2_store_entitlements e WHERE e.customer_id = ? AND e.status = 'pending_setup'
    ]], { customer.id }) or {}
    for _, w in ipairs(waiting) do
        lines[#lines + 1] = ('  NEEDS SETUP: %s (order %s) -> /storedone %s'):format(w.product_slug, w.order_ref or '?', w.order_ref or '')
    end
    local stuck = MySQL.query.await([[
        SELECT id, action, status, attempts, last_error FROM pmv2_store_deliveries
        WHERE customer_id = ? AND status IN ('pending', 'claimed', 'failed') ORDER BY id DESC LIMIT 5
    ]], { customer.id }) or {}
    for _, d in ipairs(stuck) do
        lines[#lines + 1] = ('  Delivery #%s %s: %s (tries %s) %s'):format(d.id, d.action, d.status, d.attempts, d.last_error or '')
    end

    if source == 0 then
        for _, line in ipairs(lines) do print(line) end
    else
        TriggerClientEvent('pmv2_store:print', source, lines)
        notify(source, ('%s has %s coins, %s orders, %s needing setup. Details in F8.'):format(customer.discord_username or 'Player', customer.coins, #orders, #waiting), 'inform', 9000)
    end
end)

lib.addCommand('storedone', {
    help = 'Mark a package order as set up (activates it)',
    params = {
        { name = 'order', help = 'Order code, e.g. PM-7K3QX2' }
    },
    restricted = Config.StaffGroups
}, function(source, args)
    local ref = tostring(args.order or ''):upper()
    local order = MySQL.single.await('SELECT id, discord_id, status FROM pmv2_store_orders WHERE order_ref = ?', { ref })
    if not order then return notify(source, 'No order with that code.', 'error') end
    if order.status ~= 'paid' then return notify(source, ('That order is %s, not paid. Check it before setting anything up.'):format(order.status), 'error', 9000) end

    local actor = ('staff:%s'):format(displayName(source))
    local changed = MySQL.update.await([[
        UPDATE pmv2_store_entitlements SET status = 'active'
        WHERE status = 'pending_setup' AND order_item_id IN (SELECT id FROM pmv2_store_order_items WHERE order_id = ?)
    ]], { order.id })
    MySQL.update.await([[
        UPDATE pmv2_store_order_items SET fulfillment_status = 'fulfilled', fulfilled_by = ?, fulfilled_at = CURRENT_TIMESTAMP(3)
        WHERE order_id = ? AND kind = 'package' AND fulfillment_status IN ('pending', 'processing')
    ]], { actor, order.id })
    if changed == 0 then return notify(source, 'Nothing was waiting on setup for that order.', 'inform') end

    audit(actor, 'order.fulfilled', 'order', ref, nil)
    notify(source, ('Order %s marked as set up.'):format(ref), 'success')
    local items = MySQL.query.await("SELECT product_title, quantity FROM pmv2_store_order_items WHERE order_id = ? AND kind = 'package'", { order.id }) or {}
    local list = {}
    for _, it in ipairs(items) do list[#list + 1] = ('%sx %s'):format(it.quantity, it.product_title) end
    sendLog('Package set up', COLORS.done, {
        { 'Order', ref, true }, { 'Buyer', ('<@%s>'):format(order.discord_id), true },
        { 'Package', table.concat(list, ', ') }, { 'By', who(source) }
    })
    local _, online = resolveTarget(order.discord_id)
    if online then notify(online, ('Your package from order %s is all set up. Enjoy!'):format(ref), 'success', 12000) end
end)

-- ------------------------------------------------------------
-- Startup check
-- ------------------------------------------------------------

MySQL.ready(function()
    local ok = pcall(MySQL.scalar.await, 'SELECT COUNT(*) FROM pmv2_store_deliveries')
    if not ok then
        log('Store tables not found. Run db/pmv2_store.sql on this database, then restart pmv2_store.')
        return
    end
    ready = true
    log('Ready.')
end)
