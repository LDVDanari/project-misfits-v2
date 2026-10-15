-- ─────────────────────────────────────────────────────────────
--  BILLING - rent, tenant rent, utilities, property tax, dirt, repossession
--  Every rate lives in config.lua (Config.Rent / Config.Utilities / Config.Dirt).
-- ─────────────────────────────────────────────────────────────
Billing = {}

function Billing.TotalDue(p)
    local total = p.state.taxDue or 0
    for _, k in ipairs(Shared.UtilityKeys) do total = total + (p.state.util[k].due or 0) end
    return math.floor(total)
end

local function payer(p)
    return p.renter or p.owner
end

local function notifyCid(cid, msg, ntype)
    local s = cid and Bridge.GetSource(cid)
    if s then Bridge.Notify(s, msg, ntype) end
end

-- ── Rent ─────────────────────────────────────────────────────
--- Tries to collect one rent payment. Offline players are charged when they log in.
local function chargeRent(cid, amount, label, onPaid)
    local src = Bridge.GetSource(cid)
    if not src then return nil end                    -- offline: try again at login
    if amount <= 0 then return true end
    if Bridge.GetBank(src) >= amount and Bridge.RemoveBank(src, amount, 'Rent: ' .. label) then
        onPaid()
        Bridge.Notify(src, ('Rent paid for %s: %s'):format(label, Shared.Money(amount)), 'inform')
        return true
    end
    return false
end

local function processRenter(p, now)
    if not p.renter or not p.rent_due or p.rent_due > now then return end
    local amount = p.data.rentAmount or p.rent_price
    local paid = chargeRent(p.renter, amount, p.label, function()
        Owner.PayRealtor(p.data.listedBy, amount, 'Rent ' .. p.label)
    end)
    if paid == nil then return end
    p.rent_due = p.rent_due + Config.Rent.intervalHours * 3600
    if paid then
        p.rent_missed = 0
    else
        p.rent_missed = (p.rent_missed or 0) + 1
        notifyCid(p.renter, ('Missed rent at %s (%d/%d). Keep money in the bank or you will be evicted.'):format(
            p.label, p.rent_missed, Config.Rent.missedLimit), 'error')
        if p.rent_missed >= Config.Rent.missedLimit then
            Bridge.Log('🚪 Renter evicted', ('**%s** was evicted from **#%d %s** for missed rent'):format(p.renter_name or p.renter, p.id, p.label), 0xe74c3c)
            Owner.ClearOwnership(p, 'You were evicted for missing rent.')
            return true
        end
    end
    DB.Save(p)
end

local function processTenants(p, now)
    for cid, a in pairs(p.access) do
        if a.level == 'tenant' and (a.rent or 0) > 0 and a.rent_due and a.rent_due <= now then
            local paid = chargeRent(cid, a.rent, p.label, function()
                if p.owner then Bridge.Pay(p.owner, a.rent, ('Rent from %s (%s)'):format(a.name or 'tenant', p.label)) end
            end)
            if paid ~= nil then
                a.rent_due = a.rent_due + Config.Rent.intervalHours * 3600
                if paid then
                    a.rent_missed = 0
                else
                    a.rent_missed = (a.rent_missed or 0) + 1
                    notifyCid(cid, ('Missed rent at %s (%d/%d).'):format(p.label, a.rent_missed, Config.Rent.missedLimit), 'error')
                    notifyCid(p.owner, ('%s missed rent at %s.'):format(a.name or 'A tenant', p.label), 'error')
                end
                if a.rent_missed >= Config.Rent.missedLimit then
                    p.access[cid] = nil
                    DB.RemoveAccess(p.id, cid)
                    Housing.Commit(p, { notify = { cid } })
                    notifyCid(cid, ('You were evicted from %s for missing rent.'):format(p.label), 'error')
                    notifyCid(p.owner, ('%s was evicted from %s for missed rent.'):format(a.name or 'A tenant', p.label))
                else
                    DB.SetAccess(p.id, a)
                end
            end
        end
    end
end

-- ── Utilities / tax / dirt ───────────────────────────────────
local function processUpkeep(p, hours)
    local U, D = Config.Utilities, Config.Dirt
    local changed = false
    local who = payer(p)

    if U.enabled then
        for _, k in ipairs(Shared.UtilityKeys) do
            local u = p.state.util[k]
            if u.on then
                u.due = u.due + (U[k].perHour or 0) * hours
                changed = true
                if U.shutoffAt > 0 and u.due >= U.shutoffAt then
                    u.on, u.shutoff = false, true
                    notifyCid(who, ('%s at %s was shut off for an unpaid bill.'):format(U[k].label, p.label), 'error')
                end
            end
        end
        if p.owner and U.taxPercentPerDay > 0 and p.price > 0 then
            p.state.taxDue = p.state.taxDue + p.price * U.taxPercentPerDay / 100 * hours / 24
            changed = true
        end
    end

    if D.enabled and (not D.onlyWhenUsed or p.state.used) then
        p.state.dirt = math.min(100, p.state.dirt + D.perHour * hours)
        changed = true
    end
    p.state.used = false

    if U.enabled then
        local total = Billing.TotalDue(p)
        if U.repossessAt > 0 and total >= U.repossessAt and p.owner then
            Bridge.Log('🏚️ Property repossessed', ('**#%d %s** owned by **%s** was repossessed (%s unpaid)'):format(
                p.id, p.label, p.owner_name or p.owner, Shared.Money(total)), 0xe74c3c)
            Owner.ClearOwnership(p, ('Repossessed for %s in unpaid bills.'):format(Shared.Money(total)))
            return
        elseif total >= U.finalWarningAt and not p.state.warned then
            p.state.warned = true
            notifyCid(who, ('FINAL WARNING: %s owes %s in bills. Pay up or lose the property.'):format(p.label, Shared.Money(total)), 'error')
        elseif total < U.finalWarningAt then
            p.state.warned = false
        end
    end

    if changed then DB.Save(p) end
end

CreateThread(function()
    Housing.WaitLoaded()
    local tickMs = math.max(1, Config.Utilities.tickMinutes) * 60000
    while true do
        Wait(tickMs)
        local now, hours = os.time(), Config.Utilities.tickMinutes / 60
        for _, p in pairs(Props) do
            local ok, err = pcall(function()
                if processRenter(p, now) then return end
                processTenants(p, now)
                if Housing.IsOccupied(p) then processUpkeep(p, hours) end
            end)
            if not ok then print(('[pmv2_housing] billing error on #%s: %s'):format(p.id, err)) end
        end
        for _, p in pairs(Props) do Housing.Broadcast(p) end
    end
end)

--- Catch up on rent owed while the player was offline.
function Billing.OnLogin(src, cid)
    local now = os.time()
    for _, p in pairs(Props) do
        for _ = 1, Config.Rent.missedLimit + 1 do
            if p.renter == cid and p.rent_due and p.rent_due <= now then
                if processRenter(p, now) then break end
            else
                break
            end
        end
        if p.access[cid] then processTenants(p, now) end
        if (p.owner == cid or p.renter == cid) and p.state.warned then
            Bridge.Notify(src, ('FINAL WARNING: %s owes %s in bills.'):format(p.label, Shared.Money(Billing.TotalDue(p))), 'error')
        end
    end
end

-- ── Paying bills, switching utilities, cleaning ─────────────
local function utilityGuard(src, id)
    local p = Housing.Get(id)
    if not p then return nil end
    local cid = Bridge.GetCitizenId(src)
    if not Housing.Can(p, cid, 'utilities') then return nil, "You can't manage the bills here." end
    if not Housing.IsAtProperty(src, p) then return nil, 'You need to be at the property.' end
    return p, cid
end

--- Pay one utility ('electricity' | 'water' | 'internet' | 'tax') or 'all'.
lib.callback.register('pmv2_housing:payBill', function(src, id, key)
    local p, _, err = utilityGuard(src, id)
    if not p then return false, err end
    local amount = 0
    if key == 'all' then
        amount = Billing.TotalDue(p)
    elseif key == 'tax' then
        amount = math.floor(p.state.taxDue)
    elseif p.state.util[key] then
        amount = math.floor(p.state.util[key].due)
    else
        return false
    end
    if amount <= 0 then return false, 'Nothing to pay.' end
    if Bridge.GetBank(src) < amount then return false, ("You don't have %s in the bank."):format(Shared.Money(amount)) end
    if not Bridge.RemoveBank(src, amount, 'Bills: ' .. p.label) then return false, 'Payment failed.' end

    local function clear(k)
        local u = p.state.util[k]
        u.due = 0
        if u.shutoff then u.shutoff, u.on = false, true end
    end
    if key == 'all' then
        for _, k in ipairs(Shared.UtilityKeys) do clear(k) end
        p.state.taxDue = 0
    elseif key == 'tax' then
        p.state.taxDue = 0
    else
        clear(key)
    end
    if Billing.TotalDue(p) < Config.Utilities.finalWarningAt then p.state.warned = false end
    Bridge.AddSociety(Config.Utilities.society or 'government', amount, 'Utilities ' .. p.label)
    Housing.Commit(p, { doors = false, garage = false })
    return true, amount
end)

lib.callback.register('pmv2_housing:toggleUtility', function(src, id, key)
    local p, _, err = utilityGuard(src, id)
    if not p then return false, err end
    local u = p.state.util[key]
    if not u then return false end
    if u.shutoff then return false, 'Shut off by the company. Pay the bill to get it back.' end
    u.on = not u.on
    Housing.Commit(p, { doors = false, garage = false })
    return true, u.on
end)

lib.callback.register('pmv2_housing:clean', function(src, id)
    local p = Housing.Get(id)
    if not p or not Config.Dirt.enabled then return false end
    local cid = Bridge.GetCitizenId(src)
    if not Housing.Can(p, cid, 'enter') then return false, "You don't live here." end
    if not Housing.IsAtProperty(src, p) then return false end
    if Config.Dirt.needsWater and not p.state.util.water.on then return false, 'The water is off.' end
    local last = p.state.lastClean or {}
    if (last[cid] or 0) + Config.Dirt.cleanSeconds - 2 > os.time() then return false end
    last[cid] = os.time()
    p.state.lastClean = last
    p.state.dirt = math.max(0, p.state.dirt - Config.Dirt.cleanAmount)
    if Config.Dirt.needsWater then p.state.util.water.due = p.state.util.water.due + (Config.Utilities.water.perHour or 0) * 0.1 end
    Housing.Commit(p, { doors = false, garage = false })
    return true, math.floor(p.state.dirt)
end)
