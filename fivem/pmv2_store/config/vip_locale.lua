-- Server-side messages use string.format placeholders (%s, %d).
Locale = {
    server = {
        no_player          = 'Could not find your character.',
        busy               = 'Please wait, your last request is still processing.',
        too_far            = 'You are too far from the store.',
        bad_store          = 'This store is not available.',
        not_in_store       = 'That item is not sold here.',
        no_discord         = 'We can\'t see your Discord account. Open the Discord app before launching FiveM, then reconnect.',

        item_not_found     = 'Item no longer exists.',
        tier_locked        = 'Requires %s VIP or higher.',
        limit_reached      = 'You already own the maximum of this item.',
        cant_carry         = 'You cannot carry that right now.',
        no_payment         = 'Not enough coins.',
        cart_empty         = 'Your basket is empty.',
        coins_busy         = 'Your coins are being updated. Try again in a second.',
        cart_too_big       = 'Too many items in one checkout (max %d).',
        delivery_failed    = 'Delivery failed, you were not charged.',
        purchased          = 'Purchased.',

        tier_granted       = 'VIP status updated: %s.',
        tier_expired       = 'Your %s VIP has expired.',
    },

    -- Strings used by the NUI.
    ui = {
        nav_home         = 'Home',
        nav_settings     = 'Settings',
        nav_vehicle      = 'Vehicle',

        home_balance     = 'YOUR BALANCE',
        home_hint        = 'Coins bought on the webstore land here automatically. No codes to redeem.',
        home_buy         = 'Get More Coins',
        home_shop        = 'Start Shopping',
        home_no_discord  = 'Open the Discord app before launching FiveM, then reconnect, so we can find your coins.',

        search           = 'Search...',
        basket           = 'BASKET',
        basket_empty     = 'Select items to add them to your basket.',
        total            = 'Total',
        balance          = 'Balance',
        after            = 'After purchase',
        purchase         = 'Purchase',
        add              = 'Add',
        added            = 'Added',
        locked           = 'Locked',
        owned            = 'Owned',
        no_items         = 'Nothing for sale here yet.',
        picks            = 'picks',

        showroom_kicker  = 'MISFITS VIP SHOWROOM',
        vehicle_note     = 'Purchased vehicles are delivered straight to your garage.',
        buy_vehicle      = 'Purchase Vehicle',

        settings_account = 'ACCOUNT',
        settings_prefs   = 'PREFERENCES',
        vip_tier         = 'VIP Tier',
        expires          = 'Expires',
        lifetime         = 'Lifetime',
        none             = 'None',
        pref_confirm     = 'Confirm before purchasing',
        pref_motion      = 'Reduce animations',
        pref_scale       = 'Interface size',

        confirm          = 'Confirm',
        cancel           = 'Cancel',
        confirm_text     = 'Spend %s on these items? This cannot be undone.',
    },
}

-- Usage: L('tier_locked', 'Gold')
function L(key, ...)
    local s = Locale.server[key] or key
    if select('#', ...) > 0 then
        return s:format(...)
    end
    return s
end
