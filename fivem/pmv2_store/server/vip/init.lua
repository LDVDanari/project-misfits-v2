-- ─────────────────────────────────────────────────────────────
--  VIP shop startup: tables, config checks, old-balance move.
-- ─────────────────────────────────────────────────────────────

--- Moves any coins left in the old misfits_vip balance into this player's store wallet.
--- Safe to call often: the old column is zeroed before the coins are added, so it only happens once.
function MoveOldVipCoins(src, citizenid)
    if not Config.MoveOldVipCoins then return end
    citizenid = citizenid or Bridge.GetCitizenId(src)
    if not citizenid or not Store.DiscordOf(src) then return end -- no Discord yet: leave them where they are

    local amount = DB.TakeOldCredits(citizenid)
    if amount <= 0 then return end
    local ok, why = Store.GiveCoins(src, amount, 'Moved from old misfits_vip balance')
    if not ok then
        DB.RestoreOldCredits(citizenid, amount)
        print(('[pmv2_store] Could not move %d old VIP coins for %s (%s). Left them in misfits_vip_players.'):format(amount, citizenid, tostring(why)))
    end
end

AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    local src = player and player.PlayerData and player.PlayerData.source
    if not src then return end
    SetTimeout(8000, function()
        if GetPlayerName(src) then
            local ok, err = pcall(MoveOldVipCoins, src)
            if not ok then print('[pmv2_store] Old VIP coin move failed: ' .. tostring(err)) end
        end
    end)
end)

CreateThread(function()
    DB.Init()

    -- Config sanity checks: fail loudly at start instead of silently at purchase time.
    local problems = 0
    local function warn(msg) problems = problems + 1 print('[pmv2_store] VIP CONFIG: ' .. msg) end

    for _, item in ipairs(Config.Items) do
        for _, pool in ipairs(item.pools or {}) do
            if not Config.Pools[pool] then warn(('item "%s" uses unknown pool "%s"'):format(item.id, pool)) end
        end
        if not item.rewards or #item.rewards == 0 then warn(('item "%s" has no rewards'):format(item.id)) end
        if not item.pools and not item.price then warn(('item "%s" has no pools and no price: nobody can buy it'):format(item.id)) end
        for _, r in ipairs(item.rewards or {}) do
            if r.type == 'tier' then warn(('item "%s" has a tier reward: VIP tiers were removed, delete it'):format(item.id)) end
        end
    end
    local itemIds, catIds = {}, {}
    for _, item in ipairs(Config.Items) do itemIds[item.id] = item end
    for _, c in ipairs(Config.Categories) do catIds[c.id] = true end
    for key, shop in pairs(Config.Shops) do
        for _, cat in ipairs(shop.categories or {}) do
            if not catIds[cat] then warn(('store "%s" lists unknown category "%s"'):format(key, cat)) end
        end
    end
    if Config.Showroom.enabled then
        for i, slot in ipairs(Config.Showroom.vehicles) do
            local item = itemIds[slot.item]
            local hasVehicle = false
            for _, r in ipairs(item and item.rewards or {}) do if r.type == 'vehicle' then hasVehicle = true end end
            if not item then warn(('showroom slot %d uses unknown item "%s"'):format(i, tostring(slot.item)))
            elseif not hasVehicle then warn(('showroom slot %d item "%s" has no vehicle reward'):format(i, slot.item)) end
        end
    end
    if GetResourceState('misfits_vip') == 'started' or GetResourceState('misfits_vip') == 'starting' then
        print('[pmv2_store] misfits_vip is still running. It is built into pmv2_store now: remove `ensure misfits_vip` and delete that folder.')
    end

    if Config.Showroom.enabled and Config.Showroom.spawns and Config.Showroom.spawns[1]
        and math.abs(Config.Showroom.spawns[1].x - 540.20) < 0.01 and math.abs(Config.Showroom.spawns[1].y + 3066.50) < 0.01 then
        warn('Config.Showroom.spawns is still the placeholder. Stand where bought/test cars should appear and use /showroomspot')
    end
    print(('[pmv2_store] VIP shop ready. %d items, %d showroom cars%s.'):format(
        #Config.Items, Config.Showroom.enabled and #Config.Showroom.vehicles or 0,
        problems > 0 and (', ' .. problems .. ' config warning(s)') or ''))
end)

