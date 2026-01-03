-- sh_tax_helper.lua
--======================================================================
-- rsg-economy / shared/sh_tax_helper.lua
-- Centralized tax + ledger utility for all resources
--
-- IMPORTANT:
--   This file is SAFE to load in shared_scripts.
--   - Server: performs actual ApplyAndRecordTax logic and records revenue/VAT.
--   - Client: provides a lightweight stub to avoid runtime errors if called.
--
-- Exports:
--   ApplyAndRecordTax(src, category, basePrice, amount, sellerCitizenId, description)
--   IsRegionVATEnabled(region_name)
--======================================================================

local IS_SERVER = IsDuplicityVersion()

-- internal: safe number
local function N(x, d)
    d = d or 0
    local n = tonumber(x)
    return n and n or d
end

-- internal: round to cents
local function round2(n)
    return math.floor((N(n, 0) + 0.0000001) * 100 + 0.5) / 100
end

-- ✅ Local checker (config-based VAT enable)
local function isVATRegionEnabled(region_name)
    if not Config or not Config.VAT then return false end
    if Config.VAT.EnabledGlobal then return true end
    local map = Config.VAT.RegionsEnabled
    if type(map) == 'table' then
        local v = map[string.lower(region_name or 'unknown')]
        if v ~= nil then return v == true end
    end
    return false
end

-- ✅ Category + region gate
local function isVATActive(region_name, category)
    if not Config or not Config.VAT then return false end
    if not (Config.VAT.Categories and Config.VAT.Categories[category]) then return false end
    return isVATRegionEnabled(region_name)
end

-- =========================================================
-- CLIENT SIDE: stub (prevents shared load crashes)
-- =========================================================
if not IS_SERVER then
    -- Client cannot safely compute region taxes (server owns DB + player data),
    -- and cannot RecordCollectedTax. So we return a minimal "no-tax" result.
    -- If you want client callers to get real results, call a server callback.
    local function ApplyAndRecordTax(_, category, basePrice, amount, _, _)
        local cat  = tostring(category or 'sales')
        local amt  = N(amount, 1)
        local unit = N(basePrice, 0)
        local gross = round2(unit * amt)

        if cat == 'trade' then
            return {
                region_name = 'unknown',
                percent     = 0,
                tax         = 0,
                subtotal    = gross,
                total       = gross,
                mode        = 'deduct',
                gross       = gross,
                net         = gross
            }
        end

        return {
            region_name = 'unknown',
            percent     = 0,
            tax         = 0,
            subtotal    = gross,
            total       = gross,
            mode        = 'add',
            gross       = gross,
            net         = gross
        }
    end

    exports('ApplyAndRecordTax', ApplyAndRecordTax)
    exports('IsRegionVATEnabled', isVATRegionEnabled)
    return
end

-- =========================================================
-- SERVER SIDE: full implementation
-- =========================================================

local RSGCore = exports['rsg-core']:GetCoreObject()

function ApplyAndRecordTax(src, category, basePrice, amount, sellerCitizenId, description)
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return nil end

    local cat  = tostring(category or 'sales'):lower()
    local amt  = N(amount, 1)
    local unit = N(basePrice, 0)
    local grossBase = round2(unit * amt)

    -------------------------------------------------
    -- Ask rsg-economy to compute tax for this region
    -------------------------------------------------
    local res
    local ok = pcall(function()
        res = exports['rsg-economy']:ApplyTaxForPlayerRegion(src, cat, unit, amt)
    end)

    if not ok or type(res) ~= 'table' then
        res = {
            region_name = 'unknown',
            subtotal    = grossBase,
            tax         = 0,
            total       = grossBase,
            percent     = 0
        }
    end

    local region = res.region_name or 'unknown'
    local gross  = round2(N(res.subtotal, grossBase))
    local tax    = round2(N(res.tax, 0))
    local pct    = N(res.percent, 0)

    -----------------------------------------
    -- Transform into SALES vs TRADE semantics
    -----------------------------------------
    local mode, payout_subtotal, counterparty_total, net

    if cat == 'trade' then
        mode               = 'deduct'
        net                = round2(gross - tax)
        payout_subtotal    = net
        counterparty_total = gross
    else
        mode               = 'add'
        net                = gross
        payout_subtotal    = gross
        counterparty_total = round2(gross + tax)
    end

    -------------------------------------------------
    -- Record into revenue / ledger (if tax > 0)
    -------------------------------------------------
    do
        local buyerIdentifier = nil
        if GetPlayerIdentifier then
            local okid, id = pcall(function() return GetPlayerIdentifier(src, 0) end)
            if okid then buyerIdentifier = id end
        end

        if tax > 0 then
            pcall(function()
                exports['rsg-economy']:RecordCollectedTax(
                    region,
                    cat,
                    tax,
                    gross,
                    buyerIdentifier,
                    sellerCitizenId,
                    description or ('transaction: ' .. cat)
                )
            end)
        end
    end

    -------------------------------------------------
    -- VAT side-booking (optional, does NOT block revenue)
    -------------------------------------------------
    if isVATActive(region, cat) and tax > 0 then
        local buyerCitizenId      = Player.PlayerData.citizenid
        local sellerCitizenIdNorm = sellerCitizenId

        if sellerCitizenIdNorm then
            pcall(function()
                exports['rsg-economy']:VAT_RecordOutput(
                    sellerCitizenIdNorm, region, gross, tax, pct, description or (cat .. ' sale')
                )
            end)
        end

        pcall(function()
            exports['rsg-economy']:VAT_RecordInput(
                buyerCitizenId, region, gross, tax, pct, description or (cat .. ' purchase')
            end)
        end)
    end

    -------------------------------------------------
    -- Notifications
    -------------------------------------------------
    if tax > 0 and src and src > 0 then
        local msg
        if cat == 'trade' then
            msg = ('Trade tax %.2f%% deducted: $%.2f from your payout.'):format(pct, tax)
        else
            msg = ('Sales tax %.2f%% added: $%.2f on your payment.'):format(pct, tax)
        end

        TriggerClientEvent('ox_lib:notify', src, {
            title       = 'Tax',
            description = msg,
            type        = 'inform',
            duration    = 6000
        })
    end

    return {
        region_name = region,
        percent     = pct,
        tax         = tax,
        subtotal    = payout_subtotal,
        total       = counterparty_total,
        mode        = mode,
        gross       = gross,
        net         = net,
    }
end

exports('ApplyAndRecordTax', ApplyAndRecordTax)
exports('IsRegionVATEnabled', isVATRegionEnabled)
