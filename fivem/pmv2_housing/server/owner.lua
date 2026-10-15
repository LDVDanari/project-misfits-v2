-- ─────────────────────────────────────────────────────────────
--  OWNERS, RENTERS, TENANTS & KEYS
-- ─────────────────────────────────────────────────────────────
Owner = {}
local MAX_PRICE = 100000000
local busy = {}   -- [citizenid] = true while a payment is being processed

local function int(v, min, max)
    v = math.floor(tonumber(v) or 0)
    if min and v < min then v = min end
    if max and v > max then v = max end
    return v
end

local function countOwned(cid, kind)
    local n = 0
    for _, p in pairs(Props) do
        if (kind == 'owner' and p.owner == cid) or (kind == 'renter' and p.renter == cid) then n = n + 1 end
    end
    return n
end

local function nextDue()
    return os.time() + Config.Rent.intervalHours * 3600
end

--- Splits a realtor sale/rent payment: commission to the realtor who listed it, rest to the society.
function Owner.PayRealtor(listedBy, amount, reason)
    if amount <= 0 then return end
    local commission = listedBy and math.floor(amount * Config.Realtor.commission / 100) or 0
    if commission > 0 then Bridge.Pay(listedBy, commission, 'Commission: ' .. reason) end
    Bridge.AddSociety(Config.Realtor.society, amount - commission, reason)
end

--- Gives a property to a player after they paid. mode = 'buy' | 'rent'
function Owner.Acquire(src, p, mode, price, realtorCid)
    local cid = Bridge.GetCitizenId(src)
    if not cid then return false, 'No character loaded.' end
    if Housing.IsOccupied(p) then return false, 'Someone already owns or rents this property.' end
    if busy[cid] then return false, 'Please wait.' end
    if mode == 'buy' and countOwned(cid, 'owner') >= Config.Limits.maxOwned then
        return false, ('You can only own %d properties.'):format(Config.Limits.maxOwned)
    end
    if mode == 'rent' and countOwned(cid, 'renter') >= Config.Limits.maxRented then
        return false, ('You can only rent %d properties.'):format(Config.Limits.maxRented)
    end
    if Bridge.GetBank(src) < price then return false, ("You don't have %s in the bank."):format(Shared.Money(price)) end

    busy[cid] = true
    local paid = Bridge.RemoveBank(src, price, (mode == 'rent' and 'Rent: ' or 'Property: ') .. p.label)
    busy[cid] = nil
    if not paid then return false, 'Payment failed.' end

    local seller = p.data.sellerListing and p.data.sellerListing.by
    if seller then
        Bridge.Pay(seller, price, 'Property sold: ' .. p.label)
    else
        Owner.PayRealtor(realtorCid or p.data.listedBy, price, (mode == 'rent' and 'Rent ' or 'Sale ') .. p.label)
    end

    if mode == 'buy' then
        p.owner, p.owner_name = cid, Bridge.GetName(src)
        p.data.boughtFor = price
    else
        p.renter, p.renter_name = cid, Bridge.GetName(src)
        p.data.rentAmount = price
        p.rent_due, p.rent_missed = nextDue(), 0
    end
    p.for_sale, p.for_rent = false, false
    p.data.sellerListing, p.data.listedBy = nil, (mode == 'rent') and (realtorCid or p.data.listedBy) or nil
    p.state = Housing.DefaultState()
    Housing.EmptyInterior(p.id, nil)
    Housing.SyncStash(p)
    Housing.Commit(p, { notify = { cid } })

    Bridge.Notify(src, mode == 'rent'
        and ('You now rent %s. %s every %dh.'):format(p.label, Shared.Money(price), Config.Rent.intervalHours)
        or ('You bought %s!'):format(p.label), 'success')
    Bridge.Log(mode == 'rent' and '🔑 Property rented' or '💰 Property bought',
        ('**%s** (`%s`) %s **#%d %s** for %s'):format(Bridge.GetName(src), cid, mode == 'rent' and 'rented' or 'bought', p.id, p.label, Shared.Money(price)))
    return true
end

--- Wipes owner, renter, tenants and keys. Used by sell-back, eviction, repossession and admin reset.
function Owner.ClearOwnership(p, reason)
    local cids = {}
    if p.owner then cids[#cids + 1] = p.owner end
    if p.renter then cids[#cids + 1] = p.renter end
    for cid in pairs(p.access) do cids[#cids + 1] = cid end

    p.owner, p.owner_name, p.renter, p.renter_name = nil, nil, nil, nil
    p.rent_due, p.rent_missed = nil, 0
    p.access = {}
    p.for_sale, p.for_rent = false, false
    p.data.sellerListing, p.data.listedBy, p.data.boughtFor, p.data.rentAmount = nil, nil, nil, nil
    p.state = Housing.DefaultState()
    DB.ClearAccess(p.id)

    Housing.EmptyInterior(p.id, reason)
    if Config.Sale.clearStashOnReset then
        pcall(function() exports.ox_inventory:ClearInventory(Housing.StashId(p.id)) end)
    end
    Housing.LockDoors(p, 1)
    Housing.Commit(p, { notify = cids })
    for _, cid in ipairs(cids) do
        local s = Bridge.GetSource(cid)
        if s and reason then Bridge.Notify(s, ('%s: %s'):format(p.label, reason), 'error') end
    end
end

local function mustBe(src, id, levels)
    local p = Housing.Get(id)
    if not p then return nil, nil, 'Property not found.' end
    local cid = Bridge.GetCitizenId(src)
    local level = Housing.Level(p, cid)
    for _, l in ipairs(levels) do
        if level == l then return p, cid end
    end
    return nil, nil, "You can't do that here."
end

local function nearbyTarget(src, target)
    target = tonumber(target)
    if not target or target == src or not GetPlayerName(target) then return nil end
    if #(Housing.Coords(src) - Housing.Coords(target)) > 5.0 then return nil end
    return target
end

-- ── Buy / rent from a listing ────────────────────────────────
lib.callback.register('pmv2_housing:buy', function(src, id)
    local p = Housing.Get(id)
    if not p or not p.for_sale or Housing.IsOccupied(p) and not p.data.sellerListing then return false, 'Not for sale.' end
    if p.data.sellerListing then
        -- player-to-player listing: hand over from the current owner
        local seller = p.owner
        if seller == Bridge.GetCitizenId(src) then return false, 'You already own this.' end
        local price = p.price
        if Bridge.GetBank(src) < price then return false, ("You don't have %s in the bank."):format(Shared.Money(price)) end
        if countOwned(Bridge.GetCitizenId(src), 'owner') >= Config.Limits.maxOwned then
            return false, ('You can only own %d properties.'):format(Config.Limits.maxOwned)
        end
        if not Bridge.RemoveBank(src, price, 'Property: ' .. p.label) then return false, 'Payment failed.' end
        Bridge.Pay(seller, price, 'Property sold: ' .. p.label)
        local old = { seller }
        for cid in pairs(p.access) do old[#old + 1] = cid end
        p.access = {}
        DB.ClearAccess(p.id)
        p.owner, p.owner_name = Bridge.GetCitizenId(src), Bridge.GetName(src)
        p.data.boughtFor, p.data.sellerListing = price, nil
        p.for_sale = false
        Housing.EmptyInterior(p.id, nil)
        old[#old + 1] = p.owner
        Housing.Commit(p, { notify = old })
        Bridge.Notify(src, ('You bought %s!'):format(p.label), 'success')
        Bridge.Log('💰 Property bought (from player)', ('**%s** bought **#%d %s** for %s'):format(Bridge.GetName(src), p.id, p.label, Shared.Money(price)))
        return true
    end
    return Owner.Acquire(src, p, 'buy', p.price)
end)

lib.callback.register('pmv2_housing:rent', function(src, id)
    local p = Housing.Get(id)
    if not p or not p.for_rent or Housing.IsOccupied(p) then return false, 'Not for rent.' end
    return Owner.Acquire(src, p, 'rent', p.rent_price)
end)

-- Realtor offers (sellTo) land on the buyer through this; see client/menus.lua.

-- ── Details for the manage menu ─────────────────────────────
lib.callback.register('pmv2_housing:details', function(src, id)
    local p = Housing.Get(id)
    if not p then return nil end
    local cid = Bridge.GetCitizenId(src)
    local level = Housing.Level(p, cid)
    if not level then return nil end
    local people = {}
    for c, a in pairs(p.access) do
        people[#people + 1] = { citizenid = c, name = a.name, level = a.level, rent = a.rent, rent_due = a.rent_due }
    end
    table.sort(people, function(a, b) return (a.name or '') < (b.name or '') end)
    local util = {}
    for _, k in ipairs(Shared.UtilityKeys) do
        util[k] = { on = p.state.util[k].on, due = math.floor(p.state.util[k].due), off = p.state.util[k].shutoff == true }
    end
    local myRent = p.access[cid] and p.access[cid].rent
    return {
        id = p.id, label = p.label, type = p.type, level = level,
        owner = p.owner_name, renter = p.renter_name,
        rent_due = (level == 'renter' and p.rent_due) or (p.access[cid] and p.access[cid].rent_due) or nil,
        rentAmount = (level == 'renter' and p.data.rentAmount) or myRent,
        people = people, util = util, taxDue = math.floor(p.state.taxDue),
        dirt = math.floor(p.state.dirt), price = p.price,
        listed = p.data.sellerListing ~= nil, sellBack = Owner.SellBackValue(p),
        now = os.time(), perms = Config.Access[level],
    }
end)

-- ── Keys ─────────────────────────────────────────────────────
--- Gives a character access by citizenid (works for offline characters too, e.g. from the phone).
function Owner.Grant(p, tcid, name, level, rent)
    if not tcid then return false, 'Player not found.' end
    if Housing.Level(p, tcid) then return false, 'They already have access.' end
    local count = 0
    for _, a in pairs(p.access) do if a.level == level then count = count + 1 end end
    local max = level == 'tenant' and Config.Limits.maxTenantsPerProperty or Config.Limits.maxKeyholders
    if count >= max then return false, ('Max %d %ss.'):format(max, level) end
    local a = { citizenid = tcid, name = name or tcid, level = level, rent = rent or 0, rent_missed = 0 }
    if level == 'tenant' and (rent or 0) > 0 then a.rent_due = nextDue() end
    p.access[tcid] = a
    DB.SetAccess(p.id, a)
    Housing.Commit(p, { notify = { tcid } })
    return true, tcid
end

local function grant(p, target, level, rent)
    return Owner.Grant(p, Bridge.GetCitizenId(target), Bridge.GetName(target), level, rent)
end

lib.callback.register('pmv2_housing:giveKey', function(src, id, target)
    local p, _, err = mustBe(src, id, { 'owner', 'renter' })
    if not p then return false, err end
    target = nearbyTarget(src, target)
    if not target then return false, 'They need to be next to you.' end
    local ok, res = grant(p, target, 'keyholder')
    if ok then
        Bridge.Notify(target, ('You got a key to %s.'):format(p.label), 'success')
        Bridge.Log('🗝️ Key given', ('**%s** gave **%s** a key to **#%d %s**'):format(Bridge.GetName(src), Bridge.GetName(target), p.id, p.label))
    end
    return ok, res
end)

lib.callback.register('pmv2_housing:removeAccess', function(src, id, tcid)
    local p, _, err = mustBe(src, id, { 'owner', 'renter' })
    if not p then return false, err end
    local a = p.access[tcid]
    if not a then return false end
    if a.level == 'tenant' and Housing.Level(p, Bridge.GetCitizenId(src)) ~= 'owner' then return false, 'Only the owner can remove tenants.' end
    p.access[tcid] = nil
    DB.RemoveAccess(p.id, tcid)
    Housing.Commit(p, { notify = { tcid } })
    local s = Bridge.GetSource(tcid)
    if s then Bridge.Notify(s, ('You no longer have access to %s.'):format(p.label), 'error') end
    return true
end)

-- Change the locks: every keyholder loses access (tenants keep theirs).
lib.callback.register('pmv2_housing:changeLocks', function(src, id)
    local p, _, err = mustBe(src, id, { 'owner', 'renter' })
    if not p then return false, err end
    local removed = {}
    for cid, a in pairs(p.access) do
        if a.level == 'keyholder' then
            p.access[cid] = nil
            DB.RemoveAccess(p.id, cid)
            removed[#removed + 1] = cid
        end
    end
    Housing.Commit(p, { notify = removed })
    Bridge.Log('🔒 Locks changed', ('**%s** changed the locks on **#%d %s** (%d keys voided)'):format(Bridge.GetName(src), p.id, p.label, #removed))
    return true, #removed
end)

-- ── Tenants (owner rents rooms out, like RTX) ───────────────
lib.callback.register('pmv2_housing:addTenant', function(src, id, target, rent)
    local p, _, err = mustBe(src, id, { 'owner' })
    if not p then return false, err end
    target = nearbyTarget(src, target)
    if not target then return false, 'They need to be next to you.' end
    rent = int(rent, Config.Rent.tenantMinRent, Config.Rent.tenantMaxRent)

    local accepted = lib.callback.await('pmv2_housing:offer', target, {
        label = p.label, price = rent, mode = 'tenant', from = Bridge.GetName(src), interval = Config.Rent.intervalHours,
    })
    if not accepted then return false, 'They declined.' end
    if rent > 0 then
        if Bridge.GetBank(target) < rent then return false, "They can't afford the first payment." end
        if not Bridge.RemoveBank(target, rent, 'Rent: ' .. p.label) then return false, 'Payment failed.' end
        Bridge.Pay(p.owner, rent, ('Rent from %s (%s)'):format(Bridge.GetName(target), p.label))
    end
    local ok, res = grant(p, target, 'tenant', rent)
    if ok then
        Bridge.Notify(target, ('You moved into %s.'):format(p.label), 'success')
        Bridge.Log('🏘️ Tenant added', ('**%s** added **%s** as a tenant at **#%d %s** for %s/%dh'):format(
            Bridge.GetName(src), Bridge.GetName(target), p.id, p.label, Shared.Money(rent), Config.Rent.intervalHours))
    end
    return ok, res
end)

lib.callback.register('pmv2_housing:setTenantRent', function(src, id, tcid, rent)
    local p, _, err = mustBe(src, id, { 'owner' })
    if not p then return false, err end
    local a = p.access[tcid]
    if not a or a.level ~= 'tenant' then return false end
    a.rent = int(rent, Config.Rent.tenantMinRent, Config.Rent.tenantMaxRent)
    if a.rent > 0 and not a.rent_due then a.rent_due = nextDue() end
    DB.SetAccess(p.id, a)
    local s = Bridge.GetSource(tcid)
    if s then Bridge.Notify(s, ('Your rent at %s is now %s.'):format(p.label, Shared.Money(a.rent))) end
    return true
end)

-- Leave: tenants/keyholders hand back their key, renters end their rental.
lib.callback.register('pmv2_housing:leave', function(src, id)
    local p = Housing.Get(id)
    if not p then return false end
    local cid = Bridge.GetCitizenId(src)
    local level = Housing.Level(p, cid)
    if level == 'tenant' or level == 'keyholder' then
        p.access[cid] = nil
        DB.RemoveAccess(p.id, cid)
        Housing.Commit(p, { notify = { cid } })
        if p.owner then
            local os_ = Bridge.GetSource(p.owner)
            if os_ then Bridge.Notify(os_, ('%s moved out of %s.'):format(Bridge.GetName(src), p.label)) end
        end
        return true
    elseif level == 'renter' then
        Owner.ClearOwnership(p, nil)
        Bridge.Log('📦 Rental ended', ('**%s** ended their rental of **#%d %s**'):format(Bridge.GetName(src), p.id, p.label))
        return true
    end
    return false
end)

-- ── Selling ──────────────────────────────────────────────────
function Owner.SellBackValue(p)
    local base = p.data.boughtFor or p.price
    local value = base * Config.Sale.sellBackPercent / 100
    local dirt = p.state.dirt
    if dirt > Config.Sale.dirtPenaltyAt then
        local share = (dirt - Config.Sale.dirtPenaltyAt) / (100 - Config.Sale.dirtPenaltyAt)
        value = value * (1 - share * Config.Sale.dirtPenaltyMax / 100)
    end
    return math.floor(value)
end

lib.callback.register('pmv2_housing:sellBack', function(src, id)
    local p, cid, err = mustBe(src, id, { 'owner' })
    if not p then return false, err end
    local total = Billing.TotalDue(p)
    local value = Owner.SellBackValue(p) - total
    Owner.ClearOwnership(p, nil)
    if value > 0 then Bridge.Pay(cid, value, 'Sold to the bank: ' .. p.label) end
    Bridge.Log('🏦 Sold to bank', ('**%s** sold **#%d %s** back to the bank for %s (after %s unpaid bills)'):format(
        Bridge.GetName(src), p.id, p.label, Shared.Money(math.max(value, 0)), Shared.Money(total)))
    return true, math.max(value, 0)
end)

lib.callback.register('pmv2_housing:transfer', function(src, id, target)
    local p, cid, err = mustBe(src, id, { 'owner' })
    if not p then return false, err end
    target = nearbyTarget(src, target)
    if not target then return false, 'They need to be next to you.' end
    local tcid = Bridge.GetCitizenId(target)
    if countOwned(tcid, 'owner') >= Config.Limits.maxOwned then return false, 'They already own the max properties.' end
    local fee = math.floor((p.data.boughtFor or p.price) * Config.Sale.transferFee / 100)
    if Bridge.GetBank(src) < fee then return false, ('The transfer fee is %s.'):format(Shared.Money(fee)) end

    local accepted = lib.callback.await('pmv2_housing:offer', target, {
        label = p.label, price = 0, mode = 'transfer', from = Bridge.GetName(src),
    })
    if not accepted then return false, 'They declined.' end
    if not Bridge.RemoveBank(src, fee, 'Transfer fee: ' .. p.label) then return false, 'Payment failed.' end
    Bridge.AddSociety(Config.Realtor.society, fee, 'Transfer fee ' .. p.label)

    p.owner, p.owner_name = tcid, Bridge.GetName(target)
    p.data.sellerListing = nil
    p.for_sale = false
    if p.access[tcid] then p.access[tcid] = nil; DB.RemoveAccess(p.id, tcid) end
    Housing.Commit(p, { notify = { cid, tcid } })
    Bridge.Notify(target, ('You now own %s.'):format(p.label), 'success')
    Bridge.Log('🤝 Property transferred', ('**%s** gave **#%d %s** to **%s** (fee %s)'):format(Bridge.GetName(src), p.id, p.label, Bridge.GetName(target), Shared.Money(fee)))
    return true
end)

-- Owner lists their own property on the market (buyer pays the owner).
lib.callback.register('pmv2_housing:listForSale', function(src, id, price)
    local p, cid, err = mustBe(src, id, { 'owner' })
    if not p then return false, err end
    if price == false then
        p.data.sellerListing, p.for_sale = nil, false
    else
        p.price = int(price, 1, MAX_PRICE)
        p.data.sellerListing = { by = cid }
        p.for_sale = true
    end
    Housing.Commit(p, { doors = false, garage = false })
    return true
end)
