Shop = {}

local busy = {}          -- citizenid -> true while a request is processing (shared with the showroom)
Shop.busy = busy
local itemsById = {}

local function indexItems()
    itemsById = {}
    for _, item in ipairs(Config.Items) do
        if itemsById[item.id] then
            print(('[pmv2_store] WARNING: duplicate item id "%s" in config/vip_shop.lua'):format(item.id))
        end
        itemsById[item.id] = item
    end
end
indexItems()

function Shop.Item(id) return itemsById[id] end

local function modeAllows(method)
    local mode = Config.Economy.mode
    return mode == 'both' or mode == method
end

local function categoryById(id)
    for _, c in ipairs(Config.Categories) do
        if c.id == id then return c end
    end
end

-- ─────────────────────────────────────────────────────────────
--  CONTEXT: which store the player is using (showroom cars are in showroom.lua).
--  The server re-checks the player's real position on EVERY request, so a
--  modded client can't open or buy from a store it isn't standing at.
-- ─────────────────────────────────────────────────────────────
local function distanceTo(src, c)
    local pos = GetEntityCoords(GetPlayerPed(src))
    return #(pos - vec3(c.x, c.y, c.z))
end

---@return table|nil ctx, string|nil errKey
local function resolveCtx(src, raw)
    if type(raw) ~= 'table' then return nil, 'bad_store' end

    if type(raw.shop) == 'string' then
        local shop = Config.Shops[raw.shop]
        if not shop then return nil, 'bad_store' end
        if distanceTo(src, shop.coords) > Config.Interaction.maxDistance then return nil, 'too_far' end
        local allowed = {}
        for _, cat in ipairs(shop.categories or {}) do allowed[cat] = true end
        return {
            kind = 'shop', key = raw.shop, def = shop, label = shop.label,
            allows = function(item) return allowed[item.category] == true end,
        }
    end

    return nil, 'bad_store'
end

local function buildPages(ctx)
    local ui = Locale.ui
    local pages = {}
    -- `redeem` is the old misfits_vip name for this flag; still honored so old configs work
    local showHome = ctx.def.home
    if showHome == nil then showHome = ctx.def.redeem end
    if showHome ~= false then
        pages[#pages + 1] = { id = 'home', kind = 'home', label = ui.nav_home, icon = 'home' }
    end
    for _, catId in ipairs(ctx.def.categories or {}) do
        local cat = categoryById(catId)
        if cat then
            pages[#pages + 1] = { id = cat.id, kind = 'category', category = cat.id, label = cat.label, icon = cat.icon or 'box' }
        end
    end
    pages[#pages + 1] = { id = 'settings', kind = 'settings', label = ui.nav_settings, icon = 'gear' }
    return pages
end

local function heroFor(ctx)
    local base = Config.Theme.hero or {}
    local over = ctx.def.hero or {}
    return {
        kicker = over.kicker or base.kicker,
        title  = over.title or base.title,
        text   = over.text or base.text,
        note   = over.note or base.note,
    }
end

-- ── Payload sent to the UI ───────────────────────────────────
local function buildPayload(src, ctx)
    local citizenid = Bridge.GetCitizenId(src)
    if not citizenid then return { error = L('no_player') } end

    MoveOldVipCoins(src, citizenid)
    local coins, coinErr = Store.GetCoins(src)
    local vouchers = Vouchers.List(citizenid)
    local counts = DB.PurchaseCounts(citizenid)

    local picksByPool, voucherOut = {}, {}
    for _, v in ipairs(vouchers) do
        local left = v.picks_total - v.picks_used
        picksByPool[v.pool] = (picksByPool[v.pool] or 0) + left
        voucherOut[#voucherOut + 1] = {
            id = v.id, pool = v.pool,
            label = Config.Pools[v.pool] and Config.Pools[v.pool].label or v.pool,
            left = left, total = v.picks_total, expiresAt = v.expires_at,
        }
    end

    local items = {}
    for _, item in ipairs(Config.Items) do
        if ctx.allows(item) then
            local owned = counts[item.id] or 0
            local pickCost = item.pickCost or 1
            local voucherPicks = 0
            if item.pools and modeAllows('voucher') then
                for _, pool in ipairs(item.pools) do voucherPicks = voucherPicks + (picksByPool[pool] or 0) end
            end
            items[#items + 1] = {
                id = item.id, category = item.category, label = item.label,
                description = item.description, image = item.image,
                contents = Rewards.DescribeAll(item.rewards), specs = item.specs,
                price = modeAllows('credits') and item.price or nil,
                pickCost = (item.pools and modeAllows('voucher')) and pickCost or nil,
                limit = item.limit, owned = owned,
                stackable = item.stackable or false, maxQty = item.maxQty or 1,
                soldOut = item.limit and owned >= item.limit or false,
                canVoucher = (item.pools ~= nil and modeAllows('voucher') and voucherPicks >= pickCost),
                canCredits = (modeAllows('credits') and item.price ~= nil),
            }
        end
    end

    local pages = buildPages(ctx)
    local start = pages[1].id
    if ctx.def.startPage then
        local want = ctx.def.startPage == 'redeem' and 'home' or ctx.def.startPage
        for _, p in ipairs(pages) do if p.id == want then start = p.id end end
    end

    return {
        theme = Config.Theme,
        ui = Locale.ui,
        imageBase = Config.Shop.imageBase,
        maxCart = Config.Shop.maxCart,
        store = { kind = ctx.kind, label = ctx.label },
        pages = pages,
        startPage = start,
        hero = heroFor(ctx),
        items = items,
        economy = { mode = Config.Economy.mode, creditsName = Config.Economy.creditsName },
        player = {
            name = Bridge.GetCharName(src),
            credits = coins,
            noDiscord = coinErr == 'no_discord',
            vouchers = voucherOut,
        },
        serverTime = os.time(),
    }
end

lib.callback.register('pmv2_store:vip:open', function(src, rawCtx)
    local ctx, err = resolveCtx(src, rawCtx)
    if not ctx then return { error = L(err) } end
    return buildPayload(src, ctx)
end)

local SPEND_ERRORS = { no_discord = 'no_discord', busy = 'coins_busy', not_enough_coins = 'no_payment', invalid_amount = 'no_payment' }
function Shop.SpendError(why) return L(SPEND_ERRORS[why] or 'no_payment') end

-- ── Purchasing ───────────────────────────────────────────────
---@return table result { id, label, ok, message }
local function buyOne(src, citizenid, item, method)
    local result = { id = item.id, label = item.label, ok = false }

    if item.limit and DB.CountPurchases(citizenid, item.id) >= item.limit then
        result.message = L('limit_reached') return result
    end

    local canReceive, why = Rewards.CanReceive(src, item.rewards)
    if not canReceive then result.message = why return result end

    -- pay
    local paidWith, cost, voucherId
    if method == 'voucher' and modeAllows('voucher') and item.pools then
        cost = item.pickCost or 1
        voucherId = Vouchers.Spend(citizenid, item.pools, cost)
        paidWith = voucherId and ('voucher:%d'):format(voucherId) or nil
    elseif method == 'credits' and modeAllows('credits') and item.price then
        cost = item.price
        -- Misfit Coins come out of the store wallet (logged to Discord by the wallet itself)
        local spent, why = Store.SpendCoins(src, cost, ('VIP shop: %s'):format(item.label))
        if spent then
            paidWith = 'coins'
        else
            result.message = L(SPEND_ERRORS[why] or 'no_payment')
            return result
        end
    end
    if not paidWith then result.message = L('no_payment') return result end

    -- deliver (refund on any failure)
    local ok, err, delivered = Rewards.ApplyAll(src, citizenid, item.rewards, 'shop:' .. item.id)
    if not ok then
        if voucherId then
            Vouchers.Refund(voucherId, cost)
        else
            local refunded, why = Store.GiveCoins(src, cost, ('Refund: %s (delivery failed)'):format(item.label))
            if not refunded then
                print(('[pmv2_store] REFUND FAILED item=%s citizen=%s cost=%d reason=%s - give the coins back by hand'):format(item.id, citizenid, cost, tostring(why)))
            end
        end
        print(('[pmv2_store] VIP delivery failed item=%s citizen=%s delivered=%d/%d err=%s'):format(
            item.id, citizenid, delivered or 0, #item.rewards, tostring(err)))
        Discord.Log('Delivery failed (refunded)', ('`%s` / item `%s`\n```%s```\nDelivered %d of %d rewards before failing. Check for partial delivery.')
            :format(citizenid, item.id, tostring(err), delivered or 0, #item.rewards))
        result.message = L('delivery_failed')
        return result
    end

    DB.LogPurchase(citizenid, item.id, paidWith, cost)
    if Config.Hooks.OnPurchase then pcall(Config.Hooks.OnPurchase, citizenid, src, item, paidWith) end
    if paidWith ~= 'coins' then -- coin purchases are already logged by the wallet
        Discord.Log('VIP shop purchase', ('**%s** (`%s`) bought **%s**'):format(Bridge.GetCharName(src), citizenid, item.label), {
            { name = 'Paid with', value = paidWith, inline = true },
            { name = 'Cost', value = tostring(cost), inline = true },
        })
    end

    result.ok = true
    result.message = L('purchased')
    return result
end

lib.callback.register('pmv2_store:vip:purchase', function(src, rawCtx, cart, method)
    local fail = function(key, ...) return { ok = false, results = {}, message = L(key, ...) } end

    local ctx, err = resolveCtx(src, rawCtx)
    if not ctx then return fail(err) end

    local citizenid = Bridge.GetCitizenId(src)
    if not citizenid then return fail('no_player') end
    if busy[citizenid] then return fail('busy') end
    if type(cart) ~= 'table' or #cart == 0 then return fail('cart_empty') end
    if method ~= 'voucher' and method ~= 'credits' then return fail('no_payment') end

    -- expand [{id, qty}] into a flat list, validating everything the client sent
    local flat = {}
    for _, entry in ipairs(cart) do
        local item = type(entry) == 'table' and itemsById[entry.id]
        if item then
            if not ctx.allows(item) then return fail('not_in_store') end
            local qty = 1
            if item.stackable then
                qty = math.max(1, math.min(math.floor(tonumber(entry.qty) or 1), item.maxQty or 1))
            end
            for _ = 1, qty do flat[#flat + 1] = item end
        end
    end
    if #flat == 0 then return fail('item_not_found') end
    if #flat > Config.Shop.maxCart then return fail('cart_too_big', Config.Shop.maxCart) end

    busy[citizenid] = true
    local results, anyOk = {}, false
    for _, item in ipairs(flat) do
        local ok, res = pcall(buyOne, src, citizenid, item, method)
        if not ok then
            print(('[pmv2_store] VIP purchase error: %s'):format(tostring(res)))
            res = { id = item.id, label = item.label, ok = false, message = L('delivery_failed') }
        end
        results[#results + 1] = res
        anyOk = anyOk or res.ok
    end
    busy[citizenid] = nil

    return { ok = anyOk, results = results }
end)
