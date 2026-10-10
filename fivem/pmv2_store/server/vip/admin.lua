-- /vipadmin <action> <target> [arg1] [arg2] [arg3]
--   info         <target>                   coins, voucher picks, what they've bought
--   givevoucher  <target> <pool> <picks> [expiresDays]
--   pools                                    list valid pool keys
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
    help = 'VIP shop admin (info, givevoucher, pools). Coins: /coinsadd',
    restricted = Config.Admin.restricted,
    -- no type on target/arg params: ox_lib's "string" type rejects anything that's only digits (server ids, amounts, days)
    params = {
        { name = 'action', type = 'string', help = 'info | givevoucher | pools' },
        { name = 'target', help = 'server id or citizenid', optional = true },
        { name = 'arg1',   help = 'pool', optional = true },
        { name = 'arg2',   help = 'picks', optional = true },
        { name = 'arg3',   help = 'voucher expiry days', optional = true },
    },
}, function(src, args)
    local action = tostring(args.action):lower()

    if action == 'pools' then return reply(src, 'Pools: ' .. keys(Config.Pools)) end
    if action == 'givecredits' then return reply(src, 'Coins moved to the store wallet. Use /coinsadd [id] [amount] [reason].') end

    local citizenid, onlineSrc = resolveTarget(args.target)
    if not citizenid then return reply(src, 'Target required (server id or citizenid).') end

    if action == 'info' then
        local vs = Vouchers.List(citizenid)
        local picks = 0
        for _, v in ipairs(vs) do picks = picks + (v.picks_total - v.picks_used) end
        local coins = 'offline'
        if onlineSrc then
            local c, err = Store.GetCoins(onlineSrc)
            coins = err == 'no_discord' and 'no Discord' or tostring(c)
        end
        local bought = {}
        for id, n in pairs(DB.PurchaseCounts(citizenid)) do bought[#bought + 1] = ('%s x%s'):format(id, n) end
        table.sort(bought)
        return reply(src, ('%s | %s: %s | active picks: %d | bought: %s'):format(
            citizenid, Config.CoinName, coins, picks, #bought > 0 and table.concat(bought, ', ') or 'nothing'))

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
