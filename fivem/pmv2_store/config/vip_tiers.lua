-- ─────────────────────────────────────────────────────────────
--  VIP TIERS
--  rank  : higher = better. Used for `minTier` locks and stacking.
--  perks : free-form key/values. Other scripts read them with
--            exports.pmv2_store:GetPerk(source, 'paycheckMultiplier', 1.0)
-- ─────────────────────────────────────────────────────────────
Config.Tiers = {
    bronze = {
        label = 'Bronze', rank = 1, color = '#cd7f32',
        perks = { paycheckMultiplier = 1.10, extraGarageSlots = 2, queuePriority = 10, chatTag = 'BRONZE' },
    },
    silver = {
        label = 'Silver', rank = 2, color = '#c0c7d1',
        perks = { paycheckMultiplier = 1.20, extraGarageSlots = 5, queuePriority = 25, chatTag = 'SILVER' },
    },
    gold = {
        label = 'Gold', rank = 3, color = '#f5c542',
        perks = { paycheckMultiplier = 1.35, extraGarageSlots = 10, queuePriority = 50, chatTag = 'GOLD' },
    },
}

-- ─────────────────────────────────────────────────────────────
--  VOUCHER POOLS  (only used if Config.Economy.mode is 'voucher' or 'both')
-- ─────────────────────────────────────────────────────────────
Config.Pools = {
    monthly_pick = { label = 'Monthly Pick' },
}
