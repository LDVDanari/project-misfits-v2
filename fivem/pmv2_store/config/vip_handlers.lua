-- ─────────────────────────────────────────────────────────────
--  SERVER-ONLY customization: custom reward handlers + lifecycle hooks.
--  This file is where you wire the shop into ANY other resource.
-- ─────────────────────────────────────────────────────────────

Config.Handlers = {}
Config.Hooks    = {}

--- Custom reward handlers. Referenced from items as:
---   { type = 'custom', handler = 'chat_color', ...your own fields... }
--- Return true on success, or false + reason on failure (the buyer is refunded).
---@param src number       player server id
---@param citizenid string
---@param reward table     the reward table from the config (read your own fields off it)
Config.Handlers.chat_color = function(src, citizenid, reward)
    -- Example: store it wherever your chat resource reads it from.
    -- exports['my_chat']:SetColor(citizenid, reward.color)
    print(('[pmv2_store] chat_color %s -> %s'):format(citizenid, tostring(reward.color)))
    return true
end

--- Called whenever a player's VIP tier changes (grant, upgrade, removal, expiry).
--- `src` is nil if the player is offline. oldTier/newTier are tier keys or nil.
Config.Hooks.OnTierChanged = function(citizenid, src, oldTier, newTier)
    -- Example: sync an ACE group so other resources can use IsPlayerAceAllowed
    -- if src then
    --     local license = GetPlayerIdentifierByType(src, 'license')
    --     if oldTier then ExecuteCommand(('remove_principal identifier.%s group.vip_%s'):format(license, oldTier)) end
    --     if newTier then ExecuteCommand(('add_principal identifier.%s group.vip_%s'):format(license, newTier)) end
    -- end
end

--- Called after a successful shop purchase of one item.
Config.Hooks.OnPurchase = function(citizenid, src, item, paidWith)
end
