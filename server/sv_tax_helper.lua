--======================================================================
-- rsg-economy / server/tax_helper.lua
-- Centralized tax + ledger utility for all resources
-- Handles:
--   - SALES / PROPERTY: tax added on top (buyer pays)
--   - TRADE          : tax deducted from earnings (seller pays)
-- Call from other resources via:
--   exports['rsg-economy']:ApplyAndRecordTax(...)
--======================================================================

lib.locale()
local RSGCore = exports['rsg-core']:GetCoreObject()

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

--[[

ApplyAndRecordTax(
    src,             -- player id (buyer for sales/property; seller for trade)
    category,        -- 'sales' | 'property' | 'trade'
    basePrice,       -- pre-tax price per unit (or total, with amount=1)
    amount,          -- units (default 1)
    sellerCitizenId, -- optional: business/stall owner for sales, or player for trade
    description      -- optional ledger note

Return:
{
    region_name,  -- normalized region name
    percent,      -- tax percent
    tax,          -- tax amount
    subtotal,     -- WHAT THE CALLER SHOULD PAY OUT
    total,        -- WHAT THE COUNTERPART PAYS (sales/property) OR GROSS TOTAL (trade)
    mode,         -- 'add' for sales/property, 'deduct' for trade
    gross,        -- base * amount
    net,          -- for trade: gross - tax ; for others: same as gross
}
--]]

function ApplyAndRecordTax(src, category, basePrice, amount, sellerCitizenId, description)
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return nil end

    local cat  = tostring(category or 'sales')
    local amt  = N(amount, 1)
    local unit = N(basePrice, 0)
    local grossBase = round2(unit * amt)

    -------------------------------------------------
    -- Ask rsg-economy to compute tax for this region
    -------------------------------------------------
    local res
    local ok = pcall(function()
        -- ApplyTaxForPlayerRegion returns:
        -- { region_name, subtotal, tax, total, percent }
        res = exports['rsg-economy']:ApplyTaxForPlayerRegion(src, cat, unit, amt)
    end)

    if not ok or type(res) ~= 'table' then
        -- graceful fallback: 0% tax
        res = {
            region_name = 'unknown',
            subtotal    = grossBase,
            tax         = 0,
            total       = grossBase,
            percent     = 0
        }
    end

    local region = res.region_name or 'unknown'
    local gross  = round2(N(res.subtotal, grossBase)) -- should equal grossBase
    local tax    = round2(N(res.tax, 0))
    local pct    = N(res.percent, 0)

    -----------------------------------------
    -- Transform into SALES vs TRADE semantics
    -----------------------------------------
    local mode, payout_subtotal, counterparty_total, net

    if cat == 'trade' then
        -- >>> TRADE: deduct tax from the seller's earnings <<<
        mode               = 'deduct'
        net                = round2(gross - tax)     -- player receives this
        payout_subtotal    = net                     -- what scripts should pay out
        counterparty_total = gross                   -- gross trade value (for logs/UI)
    else
        -- >>> SALES/PROPERTY: add tax on top for the buyer <<<
        mode               = 'add'
        net                = gross                   -- not really used for sales
        payout_subtotal    = gross                   -- seller receives base (pre-tax)
        counterparty_total = round2(gross + tax)     -- buyer pays
    end

    -------------------------------------------------
    -- Record into revenue / ledger (ALWAYS, if tax>0)
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
                    gross, -- always gross base for reporting
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

        -- In this simplified version we treat both sides as potential businesses.
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
            )
        end)
    end

    -------------------------------------------------
    -- Notifications (your request)
    --  - SALES/PROPERTY: notify buyer that tax was added
    --  - TRADE: notify seller that tax was deducted
    -------------------------------------------------
    if tax > 0 and src and src > 0 then
        local msg
        if cat == 'trade' then
            msg = (locale('trade_tax_deducted') or 'Trade tax %.2f%% deducted: $%.2f from your payout.')
                :format(pct, tax)
        else
            msg = (locale('sales_tax_added') or 'Sales tax %.2f%% added: $%.2f on your payment.')
                :format(pct, tax)
        end

        TriggerClientEvent('ox_lib:notify', src, {
            title       = locale('tax') or 'Tax',
            description = msg,
            type        = 'inform',
            duration    = 6000
        })
    end

    return {
        region_name = region,
        percent     = pct,
        tax         = tax,
        subtotal    = payout_subtotal,   -- PAY THIS to the recipient
        total       = counterparty_total,
        mode        = mode,
        gross       = gross,
        net         = net,
    }
end

exports('ApplyAndRecordTax', ApplyAndRecordTax)
exports('IsRegionVATEnabled', isVATRegionEnabled)
