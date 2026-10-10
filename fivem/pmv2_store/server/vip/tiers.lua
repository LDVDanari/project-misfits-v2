VIP = {}
Vouchers = {}

local cache = {}                 -- citizenid -> { data = {...}, t = ms }
local CACHE_MS = 30000
local DAY = 86400

local function now() return os.time() end

-- ── State ────────────────────────────────────────────────────
---@return { tier: string|nil, expiresAt: number|nil }
function VIP.Load(citizenid, force)
    local c = cache[citizenid]
    if c and not force and (GetGameTimer() - c.t) < CACHE_MS then return c.data end

    local data = { tier = nil, expiresAt = nil }
    local row = DB.GetPlayer(citizenid)
    if row then
        if row.tier and Config.Tiers[row.tier] then
            if row.expires_at == nil or row.expires_at > now() then
                data.tier = row.tier
                data.expiresAt = row.expires_at
            end
        end
    end
    cache[citizenid] = { data = data, t = GetGameTimer() }
    return data
end

function VIP.Invalidate(citizenid) cache[citizenid] = nil end

function VIP.Rank(tier)
    local def = tier and Config.Tiers[tier]
    return def and def.rank or 0
end

local function notifyTier(citizenid, oldTier, newTier)
    local src = Bridge.GetSourceByCitizenId(citizenid)
    if src then
        Player(src).state:set('vipTier', newTier, true)
        TriggerClientEvent('pmv2_store:client:vipTierChanged', src, newTier)
        if newTier then
            Bridge.Notify(src, L('tier_granted', Config.Tiers[newTier].label), 'success')
        elseif oldTier then
            Bridge.Notify(src, L('tier_expired', Config.Tiers[oldTier] and Config.Tiers[oldTier].label or oldTier), 'inform')
        end
    end
    TriggerEvent('pmv2_store:vipTierChanged', citizenid, oldTier, newTier)
    if Config.Hooks.OnTierChanged then
        local ok, err = pcall(Config.Hooks.OnTierChanged, citizenid, src, oldTier, newTier)
        if not ok then print(('[pmv2_store] OnTierChanged hook error: %s'):format(err)) end
    end
end

-- ── Tier grants ──────────────────────────────────────────────
--- Stacking rules:
---   same tier        -> extend (lifetime stays lifetime; days=0 upgrades to lifetime)
---   higher tier      -> replaces the current one
---   lower tier       -> time is added to the current (higher) tier so the purchase is never wasted
---@param days number|nil  0 or nil = lifetime
---@return boolean ok, string|nil err
function VIP.GrantTier(citizenid, tier, days)
    local def = Config.Tiers[tier]
    if not def then return false, 'unknown_tier' end

    local cur = VIP.Load(citizenid, true)
    local seconds = (days and days > 0) and (days * DAY) or nil
    local newTier, newExp = tier, nil

    if cur.tier == tier then
        if cur.expiresAt == nil then newExp = nil
        elseif seconds then newExp = cur.expiresAt + seconds
        else newExp = nil end
    elseif cur.tier and def.rank <= VIP.Rank(cur.tier) then
        newTier = cur.tier
        if cur.expiresAt == nil then newExp = nil
        elseif seconds then newExp = cur.expiresAt + seconds
        else newExp = cur.expiresAt end
    else
        newExp = seconds and (now() + seconds) or nil
    end

    DB.SetTier(citizenid, newTier, newExp)
    VIP.Invalidate(citizenid)
    if cur.tier ~= newTier then notifyTier(citizenid, cur.tier, newTier) end
    return true
end

function VIP.RemoveTier(citizenid)
    local cur = VIP.Load(citizenid, true)
    if not cur.tier then return false end
    DB.SetTier(citizenid, nil, nil)
    VIP.Invalidate(citizenid)
    notifyTier(citizenid, cur.tier, nil)
    return true
end

-- ── Vouchers ─────────────────────────────────────────────────
function Vouchers.Give(citizenid, pool, picks, expiresDays, source)
    if not Config.Pools[pool] then return false, 'unknown_pool' end
    local expiresAt = (expiresDays and expiresDays > 0) and (now() + expiresDays * DAY) or nil
    DB.GiveVoucher(citizenid, pool, picks, expiresAt, source)
    return true
end

function Vouchers.List(citizenid)
    return DB.ActiveVouchers(citizenid, now())
end

--- Spend `cost` picks from the best matching voucher (soonest-expiring first).
---@param pools string[]
---@return number|nil voucherId
function Vouchers.Spend(citizenid, pools, cost)
    local allowed = {}
    for i = 1, #pools do allowed[pools[i]] = true end
    local list = Vouchers.List(citizenid)
    for i = 1, #list do
        local v = list[i]
        if allowed[v.pool] and (v.picks_total - v.picks_used) >= cost then
            if DB.SpendVoucher(v.id, cost, now()) then return v.id end
        end
    end
    return nil
end

function Vouchers.Refund(id, cost)
    DB.RefundVoucher(id, cost)
end

-- ── Expiry sweep ─────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(5 * 60 * 1000)
        local rows = DB.ExpiredTiers(now())
        for i = 1, #rows do
            local r = rows[i]
            DB.SetTier(r.citizenid, nil, nil)
            VIP.Invalidate(r.citizenid)
            notifyTier(r.citizenid, r.tier, nil)
        end
    end
end)

-- ─────────────────────────────────────────────────────────────
--  EXPORTS  (use these from any other resource)
--    exports.pmv2_store:IsVip(source)                -> boolean
--    exports.pmv2_store:GetTier(source)              -> 'gold' | nil
--    exports.pmv2_store:HasTier(source, 'silver')    -> true if silver or higher
--    exports.pmv2_store:GetPerk(source, 'paycheckMultiplier', 1.0)
--    exports.pmv2_store:GetVipInfo(source)           -> { tier, label, expiresAt, coins }
--    exports.pmv2_store:GrantTier(citizenid, 'gold', 30)
--    exports.pmv2_store:RemoveTier(citizenid)
--    exports.pmv2_store:GiveVoucher(citizenid, 'monthly_pick', 1, 45)
--  Coins: exports.pmv2_store:GetCoins / SpendCoins / AddCoins (see INSTALL.md)
-- ─────────────────────────────────────────────────────────────
local function infoFor(src)
    local cid = src and Bridge.GetCitizenId(src)
    if not cid then return nil end
    return VIP.Load(cid)
end

exports('IsVip', function(src)
    local d = infoFor(src)
    return d ~= nil and d.tier ~= nil
end)

exports('GetTier', function(src)
    local d = infoFor(src)
    return d and d.tier or nil
end)

exports('HasTier', function(src, tier)
    local d = infoFor(src)
    if not d or not d.tier then return false end
    return VIP.Rank(d.tier) >= VIP.Rank(tier)
end)

exports('GetPerk', function(src, perk, default)
    local d = infoFor(src)
    if not d or not d.tier then return default end
    local value = Config.Tiers[d.tier].perks and Config.Tiers[d.tier].perks[perk]
    if value == nil then return default end
    return value
end)

exports('GetVipInfo', function(src)
    local d = infoFor(src)
    if not d then return nil end
    return {
        tier      = d.tier,
        label     = d.tier and Config.Tiers[d.tier].label or nil,
        expiresAt = d.expiresAt,
        coins     = (Store.GetCoins(src)),
    }
end)

exports('GrantTier',   function(cid, tier, days) return VIP.GrantTier(cid, tier, days) end)
exports('RemoveTier',  function(cid) return VIP.RemoveTier(cid) end)
exports('GiveVoucher', function(cid, pool, picks, days) return Vouchers.Give(cid, pool, picks, days, 'export') end)
