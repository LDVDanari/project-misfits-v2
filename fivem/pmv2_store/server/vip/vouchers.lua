-- Voucher "picks" (only used when Config.Economy.mode is 'voucher' or 'both').
Vouchers = {}

local DAY = 86400
local function now() return os.time() end

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

--   exports.pmv2_store:GiveVoucher(citizenid, 'monthly_pick', 1, 45)
exports('GiveVoucher', function(cid, pool, picks, days) return Vouchers.Give(cid, pool, picks, days, 'export') end)
