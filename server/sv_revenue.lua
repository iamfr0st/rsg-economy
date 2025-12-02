--======================================================================
-- rsg-economy / server/sv_revenue.lua
-- Per-region revenue + ledger (tax side)
--
-- Tables:
--   economy_revenue         (region_name, balance_cents)
--   economy_revenue_ledger  (id, region_name, tax_category, amount_cents, subtotal_cents, ...)
--
-- Exports:
--   RecordCollectedTax(region_name, tax_category, tax_amount_dollars, subtotal_dollars, buyer_identifier, seller_citizenid, description)
--   GetRegionBalance(region_name)
--   TransferRevenueToTreasury(region_name)
--======================================================================

local REV_TABLE    = 'economy_revenue'
local LEDGER_TABLE = 'economy_revenue_ledger'

local function normName(s)
    s = tostring(s or ''):lower()
    s = s:gsub('[%s%-]+', '_')
    s = s:gsub('^_+', ''):gsub('_+$', '')
    return s
end

local function cents(n)
    n = tonumber(n or 0) or 0
    return math.floor(n * 100 + 0.5)
end

-- ensure we always return a "0xXXXXXXXX" style hex string when needed
local function ensureHexHash(hash)
    if type(hash) == 'number' then
        return string.format("0x%08X", hash)
    end
    if type(hash) == 'string' then
        if hash:sub(1, 2) == '0x' or hash:sub(1, 2) == '0X' then
            return hash
        end
        if hash:match('^%x+$') then
            return '0x' .. hash:upper()
        end
    end
    return nil
end

-- =========================
-- REVENUE WRITE OPERATIONS
-- =========================

-- Append one row to the ledger (no side effects)
local function LedgerAppend(region_name, tax_category, tax_dollars, subtotal_dollars, buyer_identifier, seller_citizenid, description)
    local reg       = normName(region_name or 'unknown')
    local cat       = tostring(tax_category or 'sales'):lower()
    local tax_cents = cents(tax_dollars)
    local sub_cents = cents(subtotal_dollars)

    MySQL.insert.await(([[
        INSERT INTO %s (region_name, tax_category, amount_cents, subtotal_cents, buyer_identifier, seller_citizenid, description)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]]):format(LEDGER_TABLE), {
        reg, cat, tax_cents, sub_cents, buyer_identifier, seller_citizenid, description
    })
end

-- Increase region balance by tax amount (create row if missing)
local function RevenueAdd(region_name, tax_dollars)
    local reg = normName(region_name or 'unknown')
    local amt = cents(tax_dollars)
    if amt == 0 then return end

    MySQL.query.await(([[
        INSERT INTO %s (region_name, balance_cents) VALUES (?, ?)
        ON DUPLICATE KEY UPDATE balance_cents = balance_cents + VALUES(balance_cents)
    ]]):format(REV_TABLE), { reg, amt })
end

-- Optional: get region balance in dollars
local function RevenueGet(region_name)
    local reg = normName(region_name or 'unknown')
    local row = MySQL.single.await(
        ('SELECT balance_cents FROM %s WHERE region_name = ? LIMIT 1'):format(REV_TABLE),
        { reg }
    )
    local cents_v = tonumber(row and row.balance_cents or 0) or 0
    return cents_v / 100.0
end

-- (Optional) spend/withdraw for region-controlled features
local function RevenueSpend(region_name, dollars)
    region_name = normName(region_name)
    dollars     = tonumber(dollars or 0) or 0
    if dollars <= 0 then
        return false
    end

    local amount_cents = cents(dollars)

    local row = MySQL.single.await(
        ('SELECT balance_cents FROM %s WHERE region_name = ? LIMIT 1'):format(REV_TABLE),
        { region_name }
    )

    local current = row and tonumber(row.balance_cents or 0) or 0
    if current < amount_cents then
        return false
    end

    MySQL.update.await(
        ('UPDATE %s SET balance_cents = balance_cents - ? WHERE region_name = ?'):format(REV_TABLE),
        { amount_cents, region_name }
    )

    return true
end

-- =========================
-- PUBLIC EXPORTS
-- =========================

-- Record and credit tax revenue: append ledger + add to balance.
exports('RecordCollectedTax', function(region_name, tax_category, tax_amount_dollars, subtotal_dollars, buyer_identifier, seller_citizenid, description)
    -- We no longer skip anything here; if region_name is 'unknown', it still logs
    LedgerAppend(region_name, tax_category, tax_amount_dollars, subtotal_dollars, buyer_identifier, seller_citizenid, description)
    RevenueAdd(region_name, tax_amount_dollars)

    if Config and Config.Debug then
        print(('[rsg-economy] RecordCollectedTax reg=%s cat=%s tax=%.2f subtotal=%.2f buyer=%s seller=%s desc=%s')
            :format(
                tostring(region_name or 'unknown'),
                tostring(tax_category or 'sales'),
                tonumber(tax_amount_dollars or 0) or 0,
                tonumber(subtotal_dollars or 0) or 0,
                tostring(buyer_identifier or 'nil'),
                tostring(seller_citizenid or 'nil'),
                tostring(description or '')
            ))
    end
end)

exports('GetRegionBalance', function(region_name)
    return RevenueGet(region_name)
end)

-- Move entire revenue balance into the region treasury (whole dollars)
exports('TransferRevenueToTreasury', function(region_name)
    -- 1) Current revenue in dollars
    local balance = RevenueGet(region_name)
    balance = tonumber(balance or 0) or 0

    local amount = math.floor(balance + 0.5)
    if amount <= 0 then
        return 0
    end

    -- 2) Deduct from revenue
    local ok = RevenueSpend(region_name, amount)
    if not ok then
        return 0
    end

    -- 3) Map region_name -> regionHash (HEX string), then push into treasury
    local regionHash = exports['rsg-economy']:ResolveRegionHash(region_name)
    regionHash = ensureHexHash(regionHash)

    if regionHash then
        exports['rsg-economy']:RecordTax(regionHash, amount, nil, 'revenue_to_treasury', balance)
    else
        print(('[rsg-economy] TransferRevenueToTreasury: could not resolve hex regionHash for "%s"'):format(tostring(region_name or 'unknown')))
    end

    return amount
end)
