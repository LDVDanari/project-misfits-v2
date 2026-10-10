-- /vipadmin <action> <target> [arg1] [arg2] [arg3]
--   info         <target>
--   givetier     <target> <tier> [days]      days omitted or 0 = lifetime
--   removetier   <target>
--   givevoucher  <target> <pool> <picks> [expiresDays]
--   tiers | pools                            list valid keys
-- <target> = a player's server id (online) or a citizenid (works offline).
-- Coins: use /coinsadd and /coinsremove (they work on the same wallet the VIP shop spends from).

local function reply(src, msg)
    if src == 0 then
        print('[pmv2_store] ' .. msg)
    else
        lib.notify(src, { title = 'VIP Admin', description = msg, type = 'inform', duration = 8000 })
    end
end

local function resolveTarget(raw)
    if not raw then return nil end
    local num = tonumber(raw)
    if num and #tostring(raw) <= 6 and GetPlayerName(num) then
        local cid = Bridge.GetCitizenId(num)
        return cid, num
    end
    return tostring(raw), Bridge.GetSourceByCitizenId(tostring(raw))
end

local function keys(tbl)
    local out = {}
    for k in pairs(tbl) do out[#out + 1] = k end
    table.sort(out)
    return table.concat(out, ', ')
end

local function audit(src, text)
    Discord.Log('VIP admin action', ('%s: %s'):format(Store.Who(src), text), nil, Store.Colors.done)
end

lib.addCommand(Config.Admin.command, {
    help = 'VIP administration (info, givetier, removetier, givevoucher, tiers, pools). Coins: /coinsadd',
    restricted = Config.Admin.restricted,
    -- no type on target/arg params: ox_lib's "string" type rejects anything that's only digits (server ids, amounts, days)
    params = {
        { name = 'action', type = 'string', help = 'info | givetier | removetier | givevoucher | tiers | pools' },
        { name = 'target', help = 'server id or citizenid', optional = true },
        { name = 'arg1',   help = 'tier / pool', optional = true },
        { name = 'arg2',   help = 'days / picks', optional = true },
        { name = 'arg3',   help = 'voucher expiry days', optional = true },
    },
}, function(src, args)
    local action = tostring(args.action):lower()

    if action == 'tiers' then return reply(src, 'Tiers: ' .. keys(Config.Tiers)) end
    if action == 'pools' then return reply(src, 'Pools: ' .. keys(Config.Pools)) end
    if action == 'givecredits' then return reply(src, 'Coins moved to the store wallet. Use /coinsadd [id] [amount] [reason].') end

    local citizenid, onlineSrc = resolveTarget(args.target)
    if not citizenid then return reply(src, 'Target required (server id or citizenid).') end

    if action == 'info' then
        local d = VIP.Load(citizenid, true)
        local vs = Vouchers.List(citizenid)
        local picks = 0
        for _, v in ipairs(vs) do picks = picks + (v.picks_total - v.picks_used) end
        local coins = 'offline'
        if onlineSrc then
            local c, err = Store.GetCoins(onlineSrc)
            coins = err == 'no_discord' and 'no Discord' or tostring(c)
        end
        return reply(src, ('%s | tier: %s | expires: %s | %s: %s | active picks: %d'):format(
            citizenid, d.tier or 'none', d.tier and (d.expiresAt and os.date('%Y-%m-%d', d.expiresAt) or 'lifetime') or '-',
            Config.CoinName, coins, picks))

    elseif action == 'givetier' then
        local tier, days = args.arg1, tonumber(args.arg2) or 0
        if not tier or not Config.Tiers[tier] then return reply(src, 'Unknown tier. Valid: ' .. keys(Config.Tiers)) end
        VIP.GrantTier(citizenid, tier, days)
        audit(src, ('gave %s %s (%s days)'):format(citizenid, tier, days == 0 and 'lifetime' or days))
        return reply(src, ('Granted %s to %s.'):format(tier, citizenid))

    elseif action == 'removetier' then
        local ok = VIP.RemoveTier(citizenid)
        audit(src, ('removed tier from %s'):format(citizenid))
        return reply(src, ok and 'Tier removed.' or 'They have no active tier.')

    elseif action == 'givevoucher' then
        local pool, picks, exp = args.arg1, tonumber(args.arg2), tonumber(args.arg3)
        if not pool or not Config.Pools[pool] then return reply(src, 'Unknown pool. Valid: ' .. keys(Config.Pools)) end
        if not picks or picks < 1 then return reply(src, 'Usage: givevoucher <target> <pool> <picks> [expiresDays]') end
        Vouchers.Give(citizenid, pool, math.floor(picks), exp, 'admin')
        audit(src, ('gave %s a voucher: %dx %s'):format(citizenid, picks, pool))
        return reply(src, ('Gave %d x %s to %s.'):format(picks, pool, citizenid))
    end

    reply(src, 'Unknown action.')
end)
