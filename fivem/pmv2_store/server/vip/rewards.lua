Rewards = {}

local function commas(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    out = out:gsub('^,', '')
    return out
end

local function pluralLabel(r)
    if r.label then return r.label end
    if r.type == 'item' then
        local count = r.count or 1
        return count > 1 and ('%dx %s'):format(count, Bridge.ItemLabel(r.name)) or Bridge.ItemLabel(r.name)
    elseif r.type == 'money' then
        return ('$%s (%s)'):format(commas(r.amount), r.account or 'bank')
    elseif r.type == 'vehicle' then
        return ('Vehicle: %s'):format(r.model)
    elseif r.type == 'voucher' then
        local p = Config.Pools[r.pool]
        return ('%dx %s'):format(r.picks or 1, p and p.label or r.pool)
    elseif r.type == 'credits' then
        return ('%d %s'):format(r.amount or 0, Config.Economy.creditsName)
    end
    return r.handler or r.type
end

---@return string
function Rewards.Describe(r) return pluralLabel(r) end

---@return string[]
function Rewards.DescribeAll(list)
    local out = {}
    for i = 1, #list do out[i] = pluralLabel(list[i]) end
    return out
end

--- Pre-flight: make sure delivery should succeed before anything is charged.
---@return boolean ok, string|nil reason
function Rewards.CanReceive(src, list)
    for i = 1, #list do
        local r = list[i]
        if r.type == 'item' and not Bridge.CanCarry(src, r.name, r.count or 1) then
            return false, L('cant_carry')
        end
    end
    return true
end

--- Delivers ONE reward. Returns true, or false + reason.
function Rewards.Apply(src, citizenid, r, sourceTag)
    local t = r.type
    if t == 'item' then
        return Bridge.AddItem(src, r.name, r.count or 1, r.metadata)
    elseif t == 'money' then
        return Bridge.AddMoney(src, r.account or 'bank', r.amount or 0, 'pmv2_store vip shop')
    elseif t == 'vehicle' then
        local ok, res = Bridge.AddVehicle(src, r.model, r.garage)
        return ok, ok and nil or res
    elseif t == 'voucher' then
        return Vouchers.Give(citizenid, r.pool, r.picks or 1, r.expiresDays, sourceTag or 'reward')
    elseif t == 'credits' then
        -- Misfit Coins go into the store wallet (the same balance as /coins and the webstore)
        local ok, res = Store.GiveCoins(src, r.amount or 0, ('VIP shop: %s'):format(sourceTag or 'reward'))
        return ok, ok and nil or res
    elseif t == 'custom' then
        local handler = Config.Handlers[r.handler]
        if not handler then return false, 'unknown_handler:' .. tostring(r.handler) end
        local ok, res, reason = pcall(handler, src, citizenid, r)
        if not ok then return false, tostring(res) end
        return res ~= false, reason
    end
    return false, 'unknown_reward_type:' .. tostring(t)
end

--- Delivers a list in order. Stops at the first failure.
---@return boolean ok, string|nil reason, integer delivered
function Rewards.ApplyAll(src, citizenid, list, sourceTag)
    local delivered = 0
    for i = 1, #list do
        local ok, reason = Rewards.Apply(src, citizenid, list[i], sourceTag)
        if not ok then return false, reason or 'failed', delivered end
        delivered = delivered + 1
    end
    return true, nil, delivered
end
