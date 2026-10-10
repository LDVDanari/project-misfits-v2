-- Everything here is sent to the UI. No HTML editing needed.
Config.Theme = {
    -- Branding
    logo          = 'img/logo.png',          -- drop your full-res logo in web/img/
    brandA        = 'MISFITS',               -- purple part of the wordmark
    brandB        = 'STORE',                 -- white part of the wordmark
    tagline       = 'Spend your Misfit Coins. Choose your next move.',
    webstoreLabel = 'Misfits Webstore',
    webstoreUrl   = 'https://projectmisfitsrp.com',  -- opens in the player's browser. '' hides the button

    -- Home page text. Each store can override this with `hero` in config/vip_locations.lua
    hero = {
        kicker = 'PROJECT MISFITS V2',
        title  = { 'Your coins.', 'Your next move.' },
        text   = 'Browse weapons, items, bundles and VIP perks, paid for with your Misfit Coins.',
        note   = { 'One balance everywhere: webstore, /coins and here.', 'Your coins follow your Discord account.' },
    },

    -- Colors (CSS variables)
    colors = {
        bg         = '#0c0a12',
        panel      = '#17121f',
        purple     = '#a855f7',
        purpleDeep = '#6d28d9',
        cyan       = '#38d6f5',
        blue       = '#3b82f6',
        gold       = '#e2b86b',
        red        = '#ef4444',
        text       = '#f1eef7',
        muted      = '#9a93a8',
        good       = '#34d399',
    },

    rarity = {
        common    = '#9aa3b5',
        uncommon  = '#34d399',
        rare      = '#38bdf8',
        epic      = '#a855f7',
        legendary = '#f5b942',
    },
}
