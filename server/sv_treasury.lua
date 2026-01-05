--======================================================================
-- rsg-economy / server/sv_treasury.lua
-- Region treasury with exports & commands
--
--   Exports:
--     RecordTax(regionHash, amount, sellerCitizenId, context, baseRevenue)
--     GetTreasuryBalance(regionHash, cb(balance))
--     WithdrawFromTreasury(regionHash, amount, src, cb(ok, newBalance))
--     ResolveRegionHash(regionArg) -> hex string (e.g. "0x41332496")
--
--   Commands:
--     /treasury [region]
--     /withdraw [region] [amount]
--======================================================================

local RSGCore      = exports['rsg-core']:GetCoreObject()
local TBL_TREASURY = 'economy_treasury'
local GOV_TABLE    = Config.TableName or 'governors'
lib.locale()

local ALIAS_TO_HASH, HASH_TO_NAME = {}, {}

local function titlecase(s) return (s:gsub("(%a)([%w_]*)", function(a,b) return a:upper()..b:lower() end)) end
local function prettyFromStateKey(k) return titlecase(k:gsub("^STATE_", ""):gsub("_", " ")) end
local function joaat(s) return GetHashKey(s) end

local function toHexHash(hash)
    if type(ensureHexHash) == 'function' then
        local h = ensureHexHash(hash)
        if h then return h end
    end
    if type(hash) == 'number' then
        return string.format("0x%08X", hash)
    end
    if type(hash) == 'string' then
        return hash
    end
    return nil
end

local function buildRegionMapsFromConfig()
    ALIAS_TO_HASH, HASH_TO_NAME = {}, {}
    if not Config or type(Config.StateDistricts) ~= "table" then
        print("[rsg-economy] [treasury] Config.StateDistricts missing; region aliases unavailable.")
        return
    end

    for stateKey, _ in pairs(Config.StateDistricts) do
        if type(stateKey) == "string" then
            local k = stateKey:upper()
            if not k:find("^STATE_") then k = "STATE_" .. k end
            local numericHash = joaat(k)
            if numericHash ~= 0 then
                local name    = prettyFromStateKey(k)
                local hexHash = toHexHash(numericHash)

                if hexHash then
                    HASH_TO_NAME[hexHash] = name

                    local base = name:lower()
                    ALIAS_TO_HASH[base]                 = hexHash
                    ALIAS_TO_HASH[base:gsub("%s+","_")] = hexHash
                    ALIAS_TO_HASH[base:gsub("%s+","")]  = hexHash
                    ALIAS_TO_HASH[k:lower()]            = hexHash
                end
            end
        end
    end

    local n = 0
    for _ in pairs(HASH_TO_NAME) do n = n + 1 end
    print(("[rsg-economy] [treasury] Region maps ready (%d states)."):format(n))
end
CreateThread(buildRegionMapsFromConfig)

local function notify(src, message, msgType)
    TriggerClientEvent('ox_lib:notify', src, {
        title       = 'Governor',
        description = message,
        type        = msgType or 'inform'
    })
end

-- Normalize any region argument (alias, decimal, hex) to a HEX STRING "0xXXXXXXXX"
local function normalizeRegion(arg)
    if not arg then return nil end
    local s = tostring(arg):gsub("^%s+",""):gsub("%s+$","")
    if s == "" then return nil end

    local lower = s:lower()

    if lower:find("^0x") then
        return toHexHash(lower)
    end

    local dec = tonumber(s)
    if dec then
        return toHexHash(dec)
    end

    if ALIAS_TO_HASH[lower] then return ALIAS_TO_HASH[lower] end

    local key = lower:gsub("%s+","_")
    if not key:find("^state_") then key = "state_" .. key end
    local h = joaat(key:upper())
    if h ~= 0 then
        return toHexHash(h)
    end

    return nil
end

local function regionNameFromHash(regionHash)
    local hex = normalizeRegion(regionHash)
    return HASH_TO_NAME[hex] or tostring(hex or regionHash or 'unknown')
end

local function isOwner(src)
    if Config and Config.AcePermission and IsPlayerAceAllowed(src, Config.AcePermission) then
        return true
    end

    local ids   = GetPlayerIdentifiers(src)
    local allow = {}
    for _, id in ipairs(Config.OwnerIdentifiers or {}) do
        allow[string.lower(id)] = true
    end

    for _, pid in ipairs(ids) do
        if allow[string.lower(pid)] then
            return true
        end
    end

    return false
end

local function getLicenseIdentifier(src)
    return string.lower(RSGCore.Functions.GetIdentifier(src, 'license') or '')
end

local function isGovernorOf(src, regionHash, cb)
    local regHex = normalizeRegion(regionHash)
    if not regHex then return cb(false) end

    MySQL.Async.fetchScalar(
        ('SELECT identifier FROM `%s` WHERE region_hash = ? LIMIT 1'):format(GOV_TABLE),
        { regHex },
        function(identifier)
            if not identifier then return cb(false) end
            local myLic = getLicenseIdentifier(src)
            cb(myLic ~= '' and myLic == string.lower(identifier))
        end
    )
end

-- Treasury primitives

local function ensureRow(regionHash, cb)
    local regHex = normalizeRegion(regionHash)
    if not regHex then
        print(('[rsg-economy] [treasury] ensureRow: invalid regionHash=%s'):format(tostring(regionHash)))
        if cb then cb(false) end
        return
    end

    MySQL.Async.execute(
        ('INSERT IGNORE INTO `%s` (region_hash, balance) VALUES (?, 0)'):format(TBL_TREASURY),
        { regHex },
        function() if cb then cb(true) end end
    )
end

local function addToTreasury(regionHash, delta, cb)
    local regHex = normalizeRegion(regionHash)
    delta        = tonumber(delta or 0) or 0
    if not regHex or delta == 0 then
        if cb then cb(false) end
        return
    end

    ensureRow(regHex, function()
        MySQL.Async.execute(
            ( [[UPDATE `%s` SET balance = balance + ? WHERE region_hash = ?]] ):format(TBL_TREASURY ),
            { delta, regHex },
            function(_) if cb then cb(true) end end
        )
    end)
end

local function getBalance(regionHash, cb)
    local regHex = normalizeRegion(regionHash)
    if not regHex then return cb(0) end

    MySQL.Async.fetchScalar(
        ('SELECT balance FROM `%s` WHERE region_hash = ? LIMIT 1'):format(TBL_TREASURY),
        { regHex },
        function(bal)
            cb(tonumber(bal or 0) or 0)
        end
    )
end

-- Exports

exports('RecordTax', function(regionHash, amount, sellerCitizenId, context, baseRevenue)
    local regHex = normalizeRegion(regionHash)
    local amt    = tonumber(amount or 0) or 0

    if not regHex or amt <= 0 then return false end

    addToTreasury(regHex, amt, nil)
    return true
end)

exports('GetTreasuryBalance', function(regionHash, cb)
    getBalance(regionHash, cb)
end)

exports('WithdrawFromTreasury', function(regionHash, amount, src, cb)
    local regHex = normalizeRegion(regionHash)
    local amt    = math.floor(tonumber(amount or 0) or 0)
    if not regHex or amt <= 0 then return cb(false, nil) end

    local function doWithdraw()
        getBalance(regHex, function(bal)
            if bal < amt then return cb(false, bal) end
            addToTreasury(regHex, -amt, function()
                getBalance(regHex, function(newBal) cb(true, newBal) end)
            end)
        end)
    end

    if isOwner(src) then return doWithdraw() end
    isGovernorOf(src, regHex, function(ok)
        if not ok then return cb(false, nil) end
        doWithdraw()
    end)
end)

exports('ResolveRegionHash', function(regionArg)
    return normalizeRegion(regionArg)
end)

RegisterNetEvent('rsg-economy:recordTax', function(regionHash, amount, sellerCitizenId, context, baseRevenue)
    exports['rsg-economy']:RecordTax(regionHash, amount, sellerCitizenId, context, baseRevenue)
end)

-- Commands

RegisterCommand('treasury', function(src, args)
    local regHex = normalizeRegion(args[1])
    if not regHex then return notify(src, locale('invalid_region_t') or 'Invalid region. Try /treasury new_hanover', 'error') end
    getBalance(regHex, function(bal)
        notify(src, (locale('treasury_for') or 'Treasury for %s: $%d'):format(regionNameFromHash(regHex), bal), 'inform')
    end)
end, false)

RegisterCommand('withdraw', function(src, args)
    local regHex = normalizeRegion(args[1])
    local amt    = tonumber(args[2] or 0) or 0
    if amt <= 0 then return notify(src, locale('amount_must_be_positive') or 'Amount must be > 0', 'error') end
    if not regHex then return notify(src, locale('invalid_region') or 'Invalid region.', 'error') end

    exports['rsg-economy']:WithdrawFromTreasury(regHex, amt, src, function(ok, newBal)
        if not ok then
            if newBal then
                notify(src, (locale('insufficient_funds') or 'Insufficient funds. Current balance: $%d'):format(newBal), 'error')
            else
                notify(src, locale('not_allowed_withdraw') or 'Only the governor of this region or an admin can withdraw.', 'error')
            end
            return
        end
        notify(src, (locale('withdrew_from_treasury') or 'Withdrew $%d from %s. New balance: $%d')
            :format(amt, regionNameFromHash(regHex), newBal or 0), 'success')
    end)
end, false)
