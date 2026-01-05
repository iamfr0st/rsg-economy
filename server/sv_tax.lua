-- sv_tax.lua

--======================================================================
-- rsg-economy / server/sv_tax.lua (CLEANED)
-- Multi-category tax system stored in `economy_taxes`
--======================================================================

local RSGCore   = exports['rsg-core']:GetCoreObject()
local TAX_TABLE = 'economy_taxes'
local COL_CAT   = 'tax_category'
local COL_PCT   = 'tax_percent'
lib.locale()

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

-- HARDENED: try governor callback first, then economy callback; retry once.
local function fetchClientRegion(src)
    local function tryCall(cbName)
        local ok, h, name = pcall(function()
            return lib.callback.await(cbName, src)
        end)
        if ok and h then
            return h, name
        end
        return nil, nil
    end

    local h, name = tryCall('rsg-governor:getRegionHash')
    if h then return h, name end

    h, name = tryCall('rsg-economy:getRegionHash')
    if h then return h, name end

    Wait(200)

    h, name = tryCall('rsg-governor:getRegionHash')
    if h then return h, name end

    h, name = tryCall('rsg-economy:getRegionHash')
    if h then return h, name end

    return nil, nil
end

-----------------------------------------------------------------
-- Residency-based tax factor (rsg_residency + document check)
-----------------------------------------------------------------

local function getResidencyRegionForCitizen(citizenid)
    if not citizenid or citizenid == '' then
        return nil
    end

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
        row.region_hash

    return region
end

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

    local homeRegion = getResidencyRegionForCitizen(citizenid)
    if not homeRegion or homeRegion == '' then
        return false
    end

    local homeNorm   = normName(homeRegion)
    local regionNorm = normName(regionName)

    return homeNorm == regionNorm
end

local function getResidencyTaxFactor(src, regionName, category)
    if not Config or not Config.ResidencyTax or not Config.ResidencyTax.Enabled then
        return 1.0
    end

    category = tostring(category or 'sales'):lower()

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

local function UpsertTax(region_name, category, percent)
    region_name = normName(region_name)
    category    = tostring(category or ''):lower()

    local sql = ('INSERT INTO %s (region_name, %s, %s) VALUES (?, ?, ?) ' ..
                 'ON DUPLICATE KEY UPDATE %s = VALUES(%s)')
        :format(TAX_TABLE, COL_CAT, COL_PCT, COL_PCT, COL_PCT)

    local res = MySQL.query.await(sql, { region_name, category, percent })
    return res ~= nil
end

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

local function CalcTax(basePrice, quantity, taxPercent)
    local subtotal  = (tonumber(basePrice) or 0) * (tonumber(quantity) or 1)
    local taxAmount = subtotal * ((tonumber(taxPercent) or 0) / 100)
    local total     = subtotal + taxAmount
    return subtotal, taxAmount, total
end

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
    locale('set_tax_go') or 'Set regional taxes (governor / owner only)',
    {
        { name = locale('region') or 'region',   help = locale('region_label') or 'regionName or "here"' },
        { name = locale('category') or 'category', help = locale('category_label_pts') or 'property | trade | sales' },
        { name = locale('percent') or 'percent',  help = locale('percent_label_n') or 'tax percent (number)' }
    },
    true,
    function(source, args)
        local src       = source
        local regionArg = args[1]
        local category  = tostring(args[2] or ''):lower()
        local percent   = tonumber(args[3])

        if (category ~= 'property' and category ~= 'trade' and category ~= 'sales') or not percent then
            return notify(src, locale('set_tax_usage') or 'Usage: /settax [regionName|here] [property|trade|sales] [percent]', 'error')
        end

        local regionName = resolveTargetRegion(src, regionArg)
        if not regionName or regionName == '' then
            return notify(src, locale('unable_to_detect_region') or 'Could not determine your region. Move a bit and try again.', 'error')
        end

        local okAuth = false
        local ok, res = pcall(function()
            return exports['rsg-economy']:CanActOnRegion(src, regionName, 'command.settax')
        end)
        if ok and res then okAuth = true end

        if not okAuth then
            return notify(src, (locale('not_allowed_manage_taxes') or 'Not authorized to change taxes for "%s".'):format(normName(regionName)), 'error')
        end

        local okSave = UpsertTax(regionName, category, percent)
        if not okSave then
            return notify(src, locale('failed_save_tax') or 'Failed to save tax. Check DB schema/permissions.', 'error')
        end

        notify(src, (locale("set_tax_for") or 'Set %s tax for "%s" to %s%%.'):format(category, normName(regionName), tostring(percent)), 'success')
    end,
    'user'
)

RSGCore.Commands.Add(
    'cleartax',
    locale('clear_tax_command') or 'Clear regional taxes (governor / owner only)',
    {
        { name = 'region',   help = locale('region_label') or 'regionName or "here"' },
        { name = 'category', help = locale('category_label_pts') or 'property | trade | sales | all' }
    },
    true,
    function(source, args)
        local src       = source
        local regionArg = args[1]
        local catArg    = tostring(args[2] or 'all'):lower()

        if not regionArg then
            return notify(src, locale('clear_tax_usage') or 'Usage: /cleartax [regionName|here] [property|trade|sales|all]', 'error')
        end

        local regionName = resolveTargetRegion(src, regionArg)
        if not regionName or regionName == '' then
            return notify(src, locale('unable_to_detect_region') or 'Could not determine your region. Move a bit and try again.', 'error')
        end

        if catArg ~= 'all' and catArg ~= 'property' and catArg ~= 'trade' and catArg ~= 'sales' then
            return notify(src, locale('category_label_pts') or 'Category must be property, trade, sales, or all.', 'error')
        end

        local okAuth = false
        local ok, res = pcall(function()
            return exports['rsg-economy']:CanActOnRegion(src, regionName, 'command.cleartax')
        end)
        if ok and res then okAuth = true end

        if not okAuth then
            return notify(src, (locale('not_allowed_manage_taxes') or 'Not authorized to clear taxes for "%s".'):format(normName(regionName)), 'error')
        end

        local okClear = ClearTax(regionName, catArg)
        if not okClear then
            return notify(src, locale('failed_clear_tax') or 'Failed to clear tax. Check DB schema/permissions.', 'error')
        end

        notify(src, (locale('cleared_tax_for') or 'Cleared %s tax for "%s".'):format(catArg, normName(regionName)), 'success')
    end,
    'user'
)

RSGCore.Commands.Add(
    'gettax',
    locale('check_taxes_command') or 'Check taxes for a region',
    {
        { name = 'region', help = locale('region_label') or 'regionName or "here"' }
    },
    false,
    function(source, args)
        local src        = source
        local regionArg  = args[1]
        local regionName = resolveTargetRegion(src, regionArg)

        if not regionName or regionName == '' then
            return notify(src, locale('unable_to_detect_region') or 'Could not determine your region. Move a bit and try again.', 'error')
        end

        local t = GetTaxesForRegionName(regionName)

        notify(src, (locale('check_taxes_pts') or 'Taxes for "%s" → Property: %s%% | Trade: %s%% | Sales: %s%%')
            :format(normName(regionName), t.property, t.trade, t.sales), 'inform')
    end,
    'user'
)

RSGCore.Commands.Add(
    'debugtax',
    locale('debug_tax_command') or 'Debug tax calculation',
    {
        { name = 'region',   help = locale('region_label') or 'regionName or "here"' },
        { name = 'category', help = locale('category_label_pts') or 'property | trade | sales (default sales)' },
        { name = 'base',     help = locale('base_amount_label') or 'base amount (default 10)' }
    },
    false,
    function(source, args)
        local src        = source
        local regionArg  = args[1]
        local category   = tostring(args[2] or 'sales'):lower()
        local base       = tonumber(args[3] or 10) or 10
        local regionName = resolveTargetRegion(src, regionArg)

        if not regionName or regionName == '' then
            return notify(src, locale('unable_to_detect_region') or 'Could not determine your region for debugtax.', 'error')
        end

        local taxes           = GetTaxesForRegionName(regionName)
        local pct             = tonumber(taxes[category] or 0) or 0
        local _, taxAmount, _ = CalcTax(base, 1, pct)

        notify(src, (locale('debug_tax_notify') or '[debugtax] reg=%s cat=%s pct=%s base=%s tax=%s')
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

exports('ApplyTaxForPlayerRegion', function(src, category, basePrice, quantity)
    category = tostring(category or 'sales'):lower()
    quantity = tonumber(quantity or 1) or 1

    local _, regionAlias = fetchClientRegion(src)
    local regionName     = regionAlias and normName(regionAlias) or nil

    local taxes   = GetTaxesForRegionName(regionName)
    local basePct = tonumber(taxes[category] or 0) or 0

    local factor = getResidencyTaxFactor(src, regionName or 'unknown', category)
    local pct    = basePct * factor

    local subtotal, tax, total = CalcTax(basePrice, quantity, pct)

    if Config.Debug then
        print(('[rsg-economy] ApplyTaxForPlayerRegion src=%s region=%s cat=%s basePct=%.3f factor=%.3f pct=%.3f')
            :format(src, tostring(regionName or 'unknown'), category, basePct, factor, pct))
    end

    return {
        region_name  = regionName or 'unknown',
        subtotal     = subtotal,
        tax          = tax,
        total        = total,
        percent      = pct,
        base_percent = basePct,
    }
end)
