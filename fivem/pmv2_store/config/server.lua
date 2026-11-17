-- ─────────────────────────────────────────────────────────────
--  SERVER-ONLY CONFIG  -  this file is NEVER sent to players.
--  Anything secret goes here, not in config.lua (which every player downloads).
-- ─────────────────────────────────────────────────────────────

-- Discord log channel webhook. Logs coins spent, staff coin changes, script grants, deliveries,
-- packages marked done, failed deliveries and blocked exploit attempts. '' = logging off.
-- You can also leave this '' and put it in server.cfg instead:
--   set pmv2_store_webhook "https://discord.com/api/webhooks/..."
local WEBHOOK = ''

-- Other resources allowed to GIVE or SPEND coins, give vouchers or add delivery types through
-- exports (AddCoins, SpendCoins, GiveVoucher, RegisterDeliveryHandler). Anything not listed is
-- blocked and reported in the logs. 'name*' matches every resource starting with name.
-- Reading balances (GetCoins / GetDiscordId) is always allowed.
Config.TrustedResources = {
    'pmv2_*',
}

-- Anti-spam: how many store requests a player can make per window before they're blocked
-- for that window and reported to the Discord log as a possible exploit.
Config.FloodLimit = { requests = 40, windowSeconds = 10 }

-- ── don't edit below ─────────────────────────────────────────
do
    local fromShared = Config.LogWebhook
    if type(fromShared) == 'string' and fromShared ~= '' then
        print('^1[pmv2_store] SECURITY: Config.LogWebhook is set in config.lua, which every player downloads. ' ..
              'Move it into config/server.lua (or the pmv2_store_webhook convar) and delete it from config.lua.^7')
    end
    local fromConvar = GetConvar('pmv2_store_webhook', '')
    Config.LogWebhook = (WEBHOOK ~= '' and WEBHOOK) or (fromConvar ~= '' and fromConvar) or fromShared or ''
end
