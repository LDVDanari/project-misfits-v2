DB = {}

-- Vouchers and purchase limits are kept per character (citizenid).
-- The table names are the same ones misfits_vip used, so purchase history carries over.
-- misfits_vip_players is only read for old coin balances (see init.lua).
-- Coins are NOT stored here: they live in the store wallet (pmv2_store_wallets).

local schema = {
    [[CREATE TABLE IF NOT EXISTS `misfits_vip_players` (
        `citizenid` VARCHAR(50) NOT NULL,
        `tier` VARCHAR(50) NULL,
        `expires_at` BIGINT NULL,
        `credits` INT NOT NULL DEFAULT 0, -- old misfits_vip balance, moved into the store wallet on load
        PRIMARY KEY (`citizenid`)
    )]],
    [[CREATE TABLE IF NOT EXISTS `misfits_vip_vouchers` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `citizenid` VARCHAR(50) NOT NULL,
        `pool` VARCHAR(50) NOT NULL,
        `picks_total` INT NOT NULL,
        `picks_used` INT NOT NULL DEFAULT 0,
        `source` VARCHAR(100) NULL,
        `expires_at` BIGINT NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_citizen` (`citizenid`)
    )]],
    [[CREATE TABLE IF NOT EXISTS `misfits_vip_purchases` (
        `id` INT NOT NULL AUTO_INCREMENT,
        `citizenid` VARCHAR(50) NOT NULL,
        `item_id` VARCHAR(80) NOT NULL,
        `paid_with` VARCHAR(40) NOT NULL,
        `cost` INT NOT NULL DEFAULT 0,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_citizen_item` (`citizenid`, `item_id`)
    )]],
}

function DB.Init()
    for i = 1, #schema do
        MySQL.query.await(schema[i])
    end
end

-- ── Old misfits_vip balances ────────────────────────────────
--- Old misfits_vip coin balance. Zeroes it in the same statement that reads it,
--- so only one caller ever gets the amount. Returns the amount (0 if none).
function DB.TakeOldCredits(citizenid)
    local amount = MySQL.scalar.await('SELECT credits FROM misfits_vip_players WHERE citizenid = ?', { citizenid })
    amount = tonumber(amount) or 0
    if amount <= 0 then return 0 end
    local affected = MySQL.update.await(
        'UPDATE misfits_vip_players SET credits = 0 WHERE citizenid = ? AND credits = ?',
        { citizenid, amount }
    )
    return (affected or 0) > 0 and amount or 0
end

function DB.RestoreOldCredits(citizenid, amount)
    MySQL.update.await('UPDATE misfits_vip_players SET credits = credits + ? WHERE citizenid = ?', { amount, citizenid })
end

-- ── Vouchers ─────────────────────────────────────────────────
function DB.GiveVoucher(citizenid, pool, picks, expiresAt, source)
    return MySQL.insert.await(
        'INSERT INTO misfits_vip_vouchers (citizenid, pool, picks_total, source, expires_at) VALUES (?, ?, ?, ?, ?)',
        { citizenid, pool, picks, source, expiresAt }
    )
end

function DB.ActiveVouchers(citizenid, now)
    return MySQL.query.await(
        [[SELECT id, pool, picks_total, picks_used, expires_at FROM misfits_vip_vouchers
          WHERE citizenid = ? AND picks_used < picks_total AND (expires_at IS NULL OR expires_at > ?)
          ORDER BY (expires_at IS NULL), expires_at ASC, id ASC]],
        { citizenid, now }
    ) or {}
end

--- Atomic spend of `cost` picks from one voucher.
function DB.SpendVoucher(id, cost, now)
    local affected = MySQL.update.await(
        [[UPDATE misfits_vip_vouchers SET picks_used = picks_used + ?
          WHERE id = ? AND picks_used + ? <= picks_total AND (expires_at IS NULL OR expires_at > ?)]],
        { cost, id, cost, now }
    )
    return (affected or 0) > 0
end

function DB.RefundVoucher(id, cost)
    MySQL.update.await('UPDATE misfits_vip_vouchers SET picks_used = GREATEST(picks_used - ?, 0) WHERE id = ?', { cost, id })
end

-- ── Purchases ────────────────────────────────────────────────
function DB.CountPurchases(citizenid, itemId)
    return MySQL.scalar.await('SELECT COUNT(*) FROM misfits_vip_purchases WHERE citizenid = ? AND item_id = ?', { citizenid, itemId }) or 0
end

function DB.PurchaseCounts(citizenid)
    local rows = MySQL.query.await('SELECT item_id, COUNT(*) AS c FROM misfits_vip_purchases WHERE citizenid = ? GROUP BY item_id', { citizenid }) or {}
    local out = {}
    for i = 1, #rows do out[rows[i].item_id] = rows[i].c end
    return out
end

function DB.LogPurchase(citizenid, itemId, paidWith, cost)
    MySQL.insert.await('INSERT INTO misfits_vip_purchases (citizenid, item_id, paid_with, cost) VALUES (?, ?, ?, ?)', { citizenid, itemId, paidWith, cost })
end
