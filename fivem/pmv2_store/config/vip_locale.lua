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
        limit_reached      = 'You already own the maximum of this item.',
        cant_carry         = 'You cannot carry that right now.',
        no_payment         = 'Not enough coins.',
        cart_empty         = 'Your basket is empty.',
        coins_busy         = 'Your coins are being updated. Try again in a second.',
        cart_too_big       = 'Too many items in one checkout (max %d).',
        delivery_failed    = 'Delivery failed, you were not charged.',
        purchased          = 'Purchased.',

        -- showroom
        car_bought         = 'It\'s yours! Your %s is waiting outside.',
        car_bought_garage  = 'It\'s yours! Your %s is in your garage (%s).',
        spawn_blocked      = 'Something is parked in the delivery spot. Move it and try again.',
        test_busy          = 'You are already on a test drive.',
        test_cooldown      = 'You can test drive again in %d seconds.',
        test_failed        = 'The test car could not be brought out. Try again in a moment.',
        test_over          = 'Test drive over. Hope you liked it!',
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

        -- showroom panel
        showroom_kicker  = 'MISFITS VIP SHOWROOM',
        sr_buy           = 'Buy',
        sr_confirm       = 'Press again to confirm',
        sr_confirm_text  = 'Spend %s on this car? It spawns outside.',
        sr_test          = 'Test Drive',
        sr_cancel        = 'Cancel',
        sr_owned         = 'Already owned',
        sr_short         = 'Not enough coins',
        sr_working       = 'Working...',
        sr_balance       = 'Your balance',
        sr_top_speed     = 'Top Speed',
        sr_accel         = 'Acceleration',
        sr_braking       = 'Braking',
        sr_handling      = 'Handling',
        sr_test_left     = 'TEST DRIVE',
        sr_test_hint     = 'Get out of the car to end it early',

        settings_account = 'ACCOUNT',
        settings_prefs   = 'PREFERENCES',
        pref_confirm     = 'Confirm before purchasing',
        pref_motion      = 'Reduce animations',
        pref_scale       = 'Interface size',

        confirm          = 'Confirm',
        cancel           = 'Cancel',
        confirm_text     = 'Spend %s on these items? This cannot be undone.',
    },
}

-- Usage: L('cart_too_big', 10)
function L(key, ...)
    local s = Locale.server[key] or key
    if select('#', ...) > 0 then
        return s:format(...)
    end
    return s
end
