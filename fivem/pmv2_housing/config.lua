Config = {}

Config.Debug = false

-- ─────────────────────────────────────────────────────────────
--  WHO CAN CREATE / LIST PROPERTIES
-- ─────────────────────────────────────────────────────────────
Config.Realtor = {
    jobs = { realestate = 0 },        -- job = minimum grade. Realtors create, edit, list and sell.
    adminAce = 'pmv2housing.admin',   -- ace that can do everything a realtor can, plus delete
    command = 'housing',              -- /housing opens the realtor menu
    commission = 10,                  -- % of every sale/realtor-rent payment that goes to the realtor who sold it
    society = 'realestate',           -- the rest goes to this job's society account (see server/bridge.lua)
}

-- ─────────────────────────────────────────────────────────────
--  PROPERTY RULES
-- ─────────────────────────────────────────────────────────────
Config.Limits = {
    maxOwned = 3,                     -- properties one character can own
    maxRented = 1,                    -- properties one character can rent from the realtor
    maxTenantsPerProperty = 4,
    maxKeyholders = 6,
}

Config.Sale = {
    sellBackPercent = 70,             -- % of the purchase price paid back when selling to the bank
    dirtPenaltyAt = 50,               -- dirt % above which sell-back value starts dropping
    dirtPenaltyMax = 15,              -- max % taken off sell-back value at 100% dirt
    transferFee = 2,                  -- % of property value charged when transferring to another player
    clearStashOnReset = false,        -- wipe the stash when a property is sold back, repossessed or reset
}

-- Default stash for new properties (realtor can change it per property).
Config.Stash = { slots = 50, weight = 250000 }

-- What each level of access can do.
Config.Access = {
    owner     = { enter = true, stash = true, wardrobe = true, garage = true, utilities = true, manage = true },
    renter    = { enter = true, stash = true, wardrobe = true, garage = true, utilities = true, manage = true },
    tenant    = { enter = true, stash = true, wardrobe = true, garage = true, utilities = false, manage = false },
    keyholder = { enter = true, stash = false, wardrobe = false, garage = true, utilities = false, manage = false },
}

-- ─────────────────────────────────────────────────────────────
--  RENT  (realtor rentals and owner -> tenant rent)
-- ─────────────────────────────────────────────────────────────
Config.Rent = {
    intervalHours = 24,               -- real hours between rent payments
    missedLimit = 3,                  -- missed payments in a row before an eviction
    tenantMinRent = 0,
    tenantMaxRent = 50000,
}

-- ─────────────────────────────────────────────────────────────
--  UTILITIES, BILLS & DIRT  (all rates are adjustable here)
--  Bills build up every tick. Players pay at the utility points you place
--  in the creator, or from the property menu.
-- ─────────────────────────────────────────────────────────────
Config.Utilities = {
    enabled = true,
    tickMinutes = 15,                 -- how often bills and dirt are calculated

    -- cost per real hour while the utility is switched ON
    electricity = { label = 'Electricity', perHour = 12,  icon = 'bolt' },
    water       = { label = 'Water',       perHour = 6,   icon = 'droplet' },
    internet    = { label = 'Internet',    perHour = 4,   icon = 'wifi' },

    -- property tax: % of the property's price per real day (owned properties only)
    taxPercentPerDay = 0.25,

    society = 'government',           -- job account bill payments go to (see Bridge.AddSociety)

    -- unpaid balance per utility before it gets shut off
    shutoffAt = 1500,

    -- final warning / repossession, based on the property's TOTAL unpaid balance
    finalWarningAt = 7500,
    repossessAt = 15000,              -- 0 = never repossess
}

Config.Dirt = {
    enabled = true,
    perHour = 1.5,                    -- dirt % added per real hour (0-100)
    onlyWhenUsed = true,              -- only gets dirty when someone was inside since the last tick
    cleanSeconds = 20,                -- how long one clean takes
    cleanAmount = 35,                 -- dirt % removed per clean
    needsWater = true,                -- cleaning needs the water to be on
    warnAt = 60,                      -- players are told the place is dirty above this
}

-- ─────────────────────────────────────────────────────────────
--  INTERIORS
-- ─────────────────────────────────────────────────────────────
-- Every shell/IPL property gets its own routing bucket, so 50 people can own the same
-- interior without seeing each other.
Config.BucketOffset = 7000

-- Where shells are spawned (under the map, out of the way). Each property is in its own bucket.
Config.ShellOrigin = vector3(-1500.0, -3000.0, -150.0)

-- Shells you own (streamed by another resource). `exit` = offset from the shell origin
-- to the inside of the front door. Use /houseoffset while standing inside a shell to get it.
Config.Shells = {
    -- K4MB1 starter shells (free pack) - replace/add the shells you actually have
    { model = 'shell_v16low', label = 'Starter (Low)',     exit = vec4(4.69, -6.49, 1.5, 359.0) },
    { model = 'shell_v16mid', label = 'Starter (Mid)',     exit = vec4(1.56, -14.0, 1.5, 0.0) },
    { model = 'shell_trevor', label = "Trevor's Trailer",  exit = vec4(0.25, -3.5, 1.5, 0.0) },
    { model = 'shell_lester', label = "Lester's House",    exit = vec4(-1.65, -5.85, 1.5, 0.0) },
    { model = 'shell_ranch',  label = 'Ranch',             exit = vec4(-1.2, -5.8, 2.5, 270.0) },
    { model = 'shell_michael',label = 'Michael Style',     exit = vec4(-9.5, 5.5, 4.0, 270.0) },
}

-- GTA interiors. `exit` = where you stand when you come in. Bob74_ipl must be running
-- for the themed apartments. Stand in each one and check the spot before going live; add any
-- interior with the creator's "Custom IPL (I'm standing in it)" option.
Config.IPLs = {
    { key = 'low_apartment',  label = 'Low End Apartment',      exit = vec4(266.1, -1007.6, -101.0, 357.0) },
    { key = 'mid_apartment',  label = 'Medium Apartment',       exit = vec4(346.5, -1012.6, -99.2, 357.0) },
    { key = 'eclipse_modern', label = 'Eclipse Towers (Modern)', exit = vec4(-786.9, 315.8, 217.6, 270.0) },
    { key = 'integrity_high', label = '4 Integrity Way (High)', exit = vec4(-31.5, -595.2, 80.0, 250.0) },
}

-- ─────────────────────────────────────────────────────────────
--  STARTER APARTMENTS
-- ─────────────────────────────────────────────────────────────
Config.Starter = {
    enabled = false,
    building = nil,                   -- property id of the apartment building new characters get a unit in
    rentFree = true,                  -- starter units cost nothing
}

-- ─────────────────────────────────────────────────────────────
--  WARDROBE (client/bridge.lua)  -  which clothing script opens outfits
--  'illenium' | 'fivem-appearance' | 'qb-clothing' | 'rcore' | 'custom'
-- ─────────────────────────────────────────────────────────────
Config.Wardrobe = 'illenium'

-- ─────────────────────────────────────────────────────────────
--  MISC
-- ─────────────────────────────────────────────────────────────
Config.Blips = {
    forSale = { sprite = 374, color = 2, scale = 0.6, label = 'Property For Sale' },
    forRent = { sprite = 374, color = 5, scale = 0.6, label = 'Property For Rent' },
    owned   = { sprite = 40,  color = 27, scale = 0.7, label = 'My Property' },
}

Config.PreviewSeconds = 60           -- how long a viewing inside a listed shell/IPL lasts
Config.DoorbellSeconds = 60          -- how long a ring stays answerable
Config.ZoneDistance = 40.0           -- entrance zones only exist when you're this close
