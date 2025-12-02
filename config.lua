Config = {}

Config.Debug = false
--==============================================================
--  rsg-economy / Shared Configuration
--==============================================================

-- Server owner(s) – always allowed to manage treasury, taxes, VAT, etc.
Config.OwnerIdentifiers = {
    "license:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"  -- change this
}

-- Optional ACE permission that also counts as "owner/admin".
-- Example: 'group.superadmin'. If nil, only OwnerIdentifiers + group.admin.
Config.AcePermission = nil

--==============================================================
--  District arrays per state
--==============================================================

local AMBARINO_DISTRICTS = {
    GetHashKey("DISTRICT_GRIZZLIES_WEST"),
    GetHashKey("DISTRICT_GRIZZLIES_EAST"),
    0x62162401,
    0xF8D68DC1,
}

local NEW_HANOVER_DISTRICTS = {
    GetHashKey("DISTRICT_THE_HEARTLANDS"),
    GetHashKey("DISTRICT_ROANOKE_RIDGE"),
    0x07D4FF5F, -- Valentine / Heartlands
    0x0AA5F25D, -- Roanoke variant (long form)
    0x0AA5F25D, -- Roanoke variant (short form)
}

local LEMOYNE_DISTRICTS = {
    GetHashKey("DISTRICT_BAYOU_NWA"),
    GetHashKey("DISTRICT_SCARLETT_MEADOWS"),
    GetHashKey("DISTRICT_BLUEGILL_MARSH"),
    0x78BFE1AC,
    0xCC7C3314,
    0x4DFA0B50,
}

local WEST_ELIZABETH_DISTRICTS = {
    GetHashKey("DISTRICT_BIG_VALLEY"),
    GetHashKey("DISTRICT_GREAT_PLAINS"),
    GetHashKey("DISTRICT_TALL_TREES"),
    0x3108C492,
    0x6467EF09,
    0x1C68EA97,
}

local NEW_AUSTIN_DISTRICTS = {
    GetHashKey("DISTRICT_RIO_BRAVO"),
    GetHashKey("DISTRICT_CHOLLA_SPRINGS"),
    GetHashKey("DISTRICT_HENNIGANS_STEAD"),
    0xF9831C72,
    0x84D7AD0E,
    0x8016C23F,
    0x35390B10,
}

local GUARMA_DISTRICTS = {}

Config.StateDistricts = {
    ["STATE_AMBARINO"]       = AMBARINO_DISTRICTS,
    ["STATE_NEW_HANOVER"]    = NEW_HANOVER_DISTRICTS,
    ["STATE_LEMOYNE"]        = LEMOYNE_DISTRICTS,
    ["STATE_WEST_ELIZABETH"] = WEST_ELIZABETH_DISTRICTS,
    ["STATE_NEW_AUSTIN"]     = NEW_AUSTIN_DISTRICTS,
    ["STATE_GUARMA"]         = GUARMA_DISTRICTS,
}

--==============================================================
--  VAT configuration (used by vat.lua and sv_tax_helper.lua)
--==============================================================

Config.VAT = {
    EnabledGlobal = false,   -- master switch

    RegionsEnabled = {
        ["new_hanover"] = true,
        -- ["lemoyne"] = true,
    },

    RegistrationFee = 50,

    Categories = {
        sales    = true,
        trade    = false,
        property = false,
    },

    AutoSettle = false,      -- keep manual settlement for now
}

-- ==================================================
-- BUSINESS / LICENSING
-- ==================================================
Config.Business = Config.Business or {}

-- who can manage businesses (same logic you use in _auth.lua)
-- e.g. governors, admins, etc. We’ll respect CanActOnRegion anyway.
Config.Business.Managers = {
    -- example job names or groups if you want to use them later
    -- ['governor'] = true,
}

-- ==================================================
-- LAND / PROPERTY TAX
-- ==================================================
Config.LandTax = Config.LandTax or {}

-- how often property tax is applied (seconds)
Config.LandTax.IntervalSeconds = 7 * 24 * 3600  -- weekly by default

-- safety caps for property tax
Config.LandTax.MinPercent = 0.0
Config.LandTax.MaxPercent = 10.0   -- yearly or per interval rate; up to you

-- ==================================================
-- AUTO PAYMENTS / TREASURY
-- ==================================================
Config.AutoPay = Config.AutoPay or {}

-- Enable/disable the auto-pay scheduler
Config.AutoPay.Enabled = true

-- Global tick interval to check auto payments (ms)
Config.AutoPay.TickMs = 60 * 1000  -- every 60 seconds

-- ==================================================
-- REPORTS / GOVERNOR UI HOOKS
-- ==================================================
Config.Reports = Config.Reports or {}

-- default lookback window (days) for /econreport if none is given
Config.Reports.DefaultDays = 30

-- max lookback window (guardrail)
Config.Reports.MaxDays = 90

--==============================================================
--  Residency-based tax modifier
--  Residents pay a % of the region tax, non-residents pay 100%
--==============================================================

Config.ResidencyTax = {
    Enabled = true,

    -- Item that represents residency "papers"
    DocItem = 'residency_document',

    -- Which tax categories should be affected by residency
    -- (true = residency discount applies, false/nil = ignore)
    Categories = {
        sales    = true,
        property = true,
        trade    = false,  -- usually trade tax is for selling, up to you
    },

    -- Resident pays X% of the configured regional tax rate
    -- Example: regional sales tax = 10%, ResidentPercent = 50 → they pay 5%
    ResidentPercent    = 50,

    -- Non-resident pays Y% of the configured regional tax rate (normally 100)
    NonResidentPercent = 100,
}



