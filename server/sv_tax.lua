--======================================================================
-- rsg-economy / server/sv_tax.lua (CLEANED)
-- Multi-category tax system stored in `economy_taxes`
-- Permissions: Region Governor OR Server Owner/Admin (via CanActOnRegion)
-- Commands: /settax [region] [property|trade|sales] [percent]
--           /gettax [region]
--           /cleartax [region] [category|all]
--           /debugtax [region] [category] [base]
-- Exports : ApplyTaxByRegionName, ApplyTaxForPlayerRegion
--======================================================================

local RSGCore   = exports['rsg-core']:GetCoreObject()
local TAX_TABLE = 'economy_taxes'
local COL_CAT   = 'tax_category'
local COL_PCT   = 'tax_percent'

-- -----------------------
-- Helpers
-- -----------------------
local function normName(s)
    s = tostring(s or ''):lower()
    s = s:gsub('[%s%-]+', '_')
    s = s:gsub('^_+', ''):gsub('_+$', '')
    return s
end

local function notify(src, desc, type_)
    TriggerClientEvent('ox_lib:notify', src, {
        title       = 'Economy',
        description = desc,
        type        = type_ or 'inform',
        duration    = 6000
    })
end

local function fetchClientRegion(src)
    local ok, h, name = pcall(function()
        return lib.callback.await('rsg-economy:getRegionHash', src)
    end)
    if ok and h then return h, name end

    Wait(200)

    ok, h, name = pcall(function()
        return lib.callback.await('rsg-economy:getRegionHash', src)
    end)
    if ok and h then return h, name end

    return nil, nil
end

-----------------------------------------------------------------
-- Residency-based tax factor (rsg_residency + document check)
-----------------------------------------------------------------

-- Reads a player's residency record from the rsg_residency table.
-- We don't assume exact column names; we try a few common ones.
local function getResidencyRegionForCitizen(citizenid)
    if not citizenid or citizenid == '' then
        return nil
    end

    -- Adjust the table name if yours differs.
    local row = MySQL.single.await('SELECT * FROM rsg_residency WHERE citizenid = ? LIMIT 1', {
        citizenid
    })
    if not row then return nil end

    local region =
        row.region_alias or
        row.region_name  or
        row.region       or
        row.state        or
        row.zone         or
        row.region_hash  -- if you store the hash instead of alias

    return region
end

-- A player is considered "resident" IF:
--   1) They have the residency document item in inventory
--   2) Their rsg_residency row region matches the current tax region
local function playerHasValidResidency(Player, regionName)
    if not Config or not Config.ResidencyTax or not Config.ResidencyTax.Enabled then
        return false
    end

    if not Player or not regionName or regionName == '' then
        return false
    end

    local citizenid = Player.PlayerData.citizenid
    if not citizenid or citizenid == '' then
        return false
    end

    -- 1) Check inventory for residency document
    local docItemName = Config.ResidencyTax.DocItem or 'residency_document'
    local items       = Player.PlayerData.items or {}
    local hasDoc      = false

    for _, item in pairs(items) do
        if item and item.name == docItemName and (item.amount or 0) > 0 then
            hasDoc = true
            break
        end
    end

    if not hasDoc then
        return false
    end

    -- 2) Get residency region from rsg_residency
    local homeRegion = getResidencyRegionForCitizen(citizenid)
    if not homeRegion or homeRegion == '' then
        return false
    end

    local homeNorm   = normName(homeRegion)
    local regionNorm = normName(regionName)

    return homeNorm == regionNorm
end

-- Returns a multiplier (factor) for the tax percent:
--   effectivePct = basePct * factor
-- e.g. basePct=10%, ResidentPercent=50 → factor=0.5 → effective 5%
local function getResidencyTaxFactor(src, regionName, category)
    if not Config or not Config.ResidencyTax or not Config.ResidencyTax.Enabled then
        return 1.0
    end

    category = tostring(category or 'sales'):lower()

    -- Gate by category if configured
    if Config.ResidencyTax.Categories
       and Config.ResidencyTax.Categories[category] == false then
        return 1.0
    end

    if not regionName or regionName == '' then
        return 1.0
    end

    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return 1.0 end

    local citizenid  = Player.PlayerData.citizenid or 'unknown'
    local isResident = playerHasValidResidency(Player, regionName)

    local residentPct    = tonumber(Config.ResidencyTax.ResidentPercent    or 50)  or 50
    local nonResidentPct = tonumber(Config.ResidencyTax.NonResidentPercent or 100) or 100

    local factor = (isResident and residentPct or nonResidentPct) / 100.0

    if Config.Debug then
        print(('[rsg-economy] Residency check: src=%s citizenid=%s region=%s category=%s isResident=%s factor=%.3f')
            :format(
                tostring(src),
                tostring(citizenid),
                tostring(regionName or 'nil'),
                category,
                tostring(isResident),
                factor
            ))
    end

    return factor
end

-- -----------------------
-- DB helpers
-- -----------------------

-- Upsert one row (region_name + tax_category -> tax_percent)
local function UpsertTax(region_name, category, percent)
    region_name = normName(region_name)
    category    = tostring(category or ''):lower()

    local sql = ('INSERT INTO %s (region_name, %s, %s) VALUES (?, ?, ?) ' ..
                 'ON DUPLICATE KEY UPDATE %s = VALUES(%s)')
        :format(TAX_TABLE, COL_CAT, COL_PCT, COL_PCT, COL_PCT)

    local res = MySQL.query.await(sql, { region_name, category, percent })
    return res ~= nil
end

-- Clear one or all categories for a region
local function ClearTax(region_name, catOrAll)
    region_name = normName(region_name)
    catOrAll    = tostring(catOrAll or 'all'):lower()

    local sql, params
    if catOrAll == 'all' then
        sql    = ('DELETE FROM %s WHERE region_name = ?'):format(TAX_TABLE)
        params = { region_name }
    else
        sql    = ('DELETE FROM %s WHERE region_name = ? AND %s = ?'):format(TAX_TABLE, COL_CAT)
        params = { region_name, catOrAll }
    end

    local res = MySQL.query.await(sql, params)
    return res ~= nil
end

-- Get tax row(s) for a region; result = { property=%, trade=%, sales=% }
local function GetTaxesForRegionName(region_name)
    if not region_name or region_name == '' then
        return { property = 0, trade = 0, sales = 0 }
    end

    region_name = normName(region_name)

    local rows = MySQL.query.await(
        ('SELECT %s AS cat, %s AS pct FROM %s WHERE region_name = ?')
            :format(COL_CAT, COL_PCT, TAX_TABLE),
        { region_name }
    )

    local out = { property = 0, trade = 0, sales = 0 }
    if rows then
        for _, r in ipairs(rows) do
            local k = tostring(r.cat or ''):lower()
            if k == 'property' or k == 'trade' or k == 'sales' then
                out[k] = tonumber(r.pct or 0) or 0
            end
        end
    end

    return out
end

-- Basic calc helper
local function CalcTax(basePrice, quantity, taxPercent)
    local subtotal  = (tonumber(basePrice) or 0) * (tonumber(quantity) or 1)
    local taxAmount = subtotal * ((tonumber(taxPercent) or 0) / 100)
    local total     = subtotal + taxAmount
    return subtotal, taxAmount, total
end

-- Resolve "here" -> player's current region alias
local function resolveTargetRegion(src, regionArg)
    if not regionArg or regionArg == 'here' then
        local _, hereName = fetchClientRegion(src)
        return hereName
    end
    return regionArg
end

-- -----------------------
-- Commands
-- -----------------------

RSGCore.Commands.Add(
    'settax',
    'Set regional taxes (governor / owner only)',
    {
        { name = 'region',   help = 'regionName or "here"' },
        { name = 'category', help = 'property | trade | sales' },
        { name = 'percent',  help = 'tax percent (number)' }
    },
    true,
    function(source, args)
        local src       = source
        local regionArg = args[1]
        local category  = tostring(args[2] or ''):lower()
        local percent   = tonumber(args[3])

        if (category ~= 'property' and category ~= 'trade' and category ~= 'sales') or not percent then
            return notify(src, 'Usage: /settax [regionName|here] [property|trade|sales] [percent]', 'error')
        end

        local regionName = resolveTargetRegion(src, regionArg)
        if not regionName or regionName == '' then
            return notify(src, 'Could not determine your region. Move a bit and try again.', 'error')
        end

        -- Permission check via rsg-economy _auth
        local okAuth = false
        local ok, res = pcall(function()
            return exports['rsg-economy']:CanActOnRegion(src, regionName, 'command.settax')
        end)
        if ok and res then okAuth = true end

        if not okAuth then
            return notify(src, ('Not authorized to change taxes for "%s".'):format(normName(regionName)), 'error')
        end

        local okSave = UpsertTax(regionName, category, percent)
        if not okSave then
            return notify(src, 'Failed to save tax. Check DB schema/permissions.', 'error')
        end

        notify(src, ('Set %s tax for "%s" to %s%%.'):format(category, normName(regionName), tostring(percent)), 'success')
    end,
    'user'
)

RSGCore.Commands.Add(
    'cleartax',
    'Clear regional taxes (governor / owner only)',
    {
        { name = 'region',   help = 'regionName or "here"' },
        { name = 'category', help = 'property | trade | sales | all' }
    },
    true,
    function(source, args)
        local src       = source
        local regionArg = args[1]
        local catArg    = tostring(args[2] or 'all'):lower()

        if not regionArg then
            return notify(src, 'Usage: /cleartax [regionName|here] [property|trade|sales|all]', 'error')
        end

        local regionName = resolveTargetRegion(src, regionArg)
        if not regionName or regionName == '' then
            return notify(src, 'Could not determine your region. Move a bit and try again.', 'error')
        end

        if catArg ~= 'all' and catArg ~= 'property' and catArg ~= 'trade' and catArg ~= 'sales' then
            return notify(src, 'Category must be property, trade, sales, or all.', 'error')
        end

        local okAuth = false
        local ok, res = pcall(function()
            return exports['rsg-economy']:CanActOnRegion(src, regionName, 'command.cleartax')
        end)
        if ok and res then okAuth = true end

        if not okAuth then
            return notify(src, ('Not authorized to clear taxes for "%s".'):format(normName(regionName)), 'error')
        end

        local okClear = ClearTax(regionName, catArg)
        if not okClear then
            return notify(src, 'Failed to clear tax. Check DB schema/permissions.', 'error')
        end

        notify(src, ('Cleared %s tax for "%s".'):format(catArg, normName(regionName)), 'success')
    end,
    'user'
)

RSGCore.Commands.Add(
    'gettax',
    'Check taxes for a region',
    {
        { name = 'region', help = 'regionName or "here"' }
    },
    false,
    function(source, args)
        local src        = source
        local regionArg  = args[1]
        local regionName = resolveTargetRegion(src, regionArg)

        if not regionName or regionName == '' then
            return notify(src, 'Could not determine your region. Move a bit and try again.', 'error')
        end

        local t = GetTaxesForRegionName(regionName)

        notify(src, ('Taxes for "%s" → Property: %s%% | Trade: %s%% | Sales: %s%%')
            :format(normName(regionName), t.property, t.trade, t.sales), 'inform')
    end,
    'user'
)

RSGCore.Commands.Add(
    'debugtax',
    'Debug tax calculation',
    {
        { name = 'region',   help = 'regionName or "here"' },
        { name = 'category', help = 'property | trade | sales (default sales)' },
        { name = 'base',     help = 'base amount (default 10)' }
    },
    false,
    function(source, args)
        local src        = source
        local regionArg  = args[1]
        local category   = tostring(args[2] or 'sales'):lower()
        local base       = tonumber(args[3] or 10) or 10
        local regionName = resolveTargetRegion(src, regionArg)

        if not regionName or regionName == '' then
            return notify(src, 'Could not determine your region for debugtax.', 'error')
        end

        local taxes           = GetTaxesForRegionName(regionName)
        local pct             = tonumber(taxes[category] or 0) or 0
        local _, taxAmount, _ = CalcTax(base, 1, pct)

        notify(src, ('[debugtax] reg=%s cat=%s pct=%s base=%s tax=%s')
            :format(normName(regionName), category, pct, base, taxAmount), 'inform')
    end,
    'user'
)

-- -----------------------
-- Exports used by helper
-- -----------------------

exports('ApplyTaxByRegionName', function(region_name, category, basePrice, quantity)
    local taxes = GetTaxesForRegionName(region_name)
    local pct   = tonumber(taxes[category or 'sales'] or 0) or 0
    local subtotal, tax, total = CalcTax(basePrice, quantity, pct)

    return {
        subtotal = subtotal,
        tax      = tax,
        total    = total,
        percent  = pct
    }
end)

-- src       : player id
-- category  : "property" | "trade" | "sales"
-- basePrice : per-unit price before tax
-- quantity  : number of units
exports('ApplyTaxForPlayerRegion', function(src, category, basePrice, quantity)
    category = tostring(category or 'sales'):lower()
    quantity = tonumber(quantity or 1) or 1

    -- Determine which region the player is currently in
    local _, regionAlias = fetchClientRegion(src)
    local regionName     = regionAlias and normName(regionAlias) or nil

    -- Base configured tax for that region + category
    local taxes   = GetTaxesForRegionName(regionName)
    local basePct = tonumber(taxes[category] or 0) or 0

    -- Apply residency multiplier (resident discount vs non-resident full rate)
    local factor = getResidencyTaxFactor(src, regionName or 'unknown', category)
    local pct    = basePct * factor

    -- Calculate money amounts
    local subtotal, tax, total = CalcTax(basePrice, quantity, pct)

    if Config.Debug then
        print(('[rsg-economy] ApplyTaxForPlayerRegion src=%s region=%s cat=%s basePct=%.3f factor=%.3f pct=%.3f')
            :format(src, tostring(regionName or 'unknown'), category, basePct, factor, pct))
    end

    return {
        region_name  = regionName or 'unknown',
        subtotal     = subtotal,  -- amount seller receives (pre-tax)
        tax          = tax,       -- amount going into revenue
        total        = total,     -- amount buyer pays
        percent      = pct,       -- effective percent after residency multiplier
        base_percent = basePct,   -- raw configured rate (for UI/logs if needed)
    }
end)
