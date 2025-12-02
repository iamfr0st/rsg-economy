--========================================================--
-- Client VAT Audit Panel (ox_lib)
--========================================================--

local function fmtMoney(val)
    return ("$%.2f"):format(val or 0)
end

-- Main audit panel: list all businesses in region
RegisterNetEvent('rsg-economy:vatAuditOpen', function(data)
    local region      = data.region or 'unknown'
    local businesses  = data.businesses or {}

    if not lib or not lib.registerContext then
        print('[rsg-economy] ox_lib context not available on client.')
        return
    end

    local opts = {}

    for _, biz in ipairs(businesses) do
        local state
        if biz.net > 0.01 then
            state = ('OWES %s'):format(fmtMoney(biz.net))
        elseif biz.net < -0.01 then
            state = ('REFUND %s'):format(fmtMoney(-biz.net))
        else
            state = 'Settled'
        end

        local desc = ('Output: %s | Input: %s | Settled: %s | %s'):format(
            fmtMoney(biz.output),
            fmtMoney(biz.input),
            fmtMoney(biz.settled),
            state
        )

        opts[#opts+1] = {
            title       = biz.business_name or ('Business #' .. tostring(biz.business_id)),
            description = desc,
            icon        = (biz.net > 0.01 and 'triangle-exclamation')
                       or (biz.net < -0.01 and 'circle-arrow-left')
                       or 'circle-check',
            arrow       = true,
            event       = 'rsg-economy:vatAuditDetail',
            args        = {
                business_id   = biz.business_id,
                business_name = biz.business_name,
                region        = region
            }
        }
    end

    lib.registerContext({
        id = 'vat_audit_main',
        title = ('VAT Audit — %s'):format(region),
        canClose = true,
        options = opts
    })
    lib.showContext('vat_audit_main')
end)

-- Detail view: per-business ledger
RegisterNetEvent('rsg-economy:vatAuditDetail', function(args)
    local business_id   = args.business_id
    local business_name = args.business_name or ('Business #' .. tostring(business_id))
    local region        = args.region or 'unknown'

    local ledger = lib.callback.await('rsg-economy:getVatLedger', false, business_id, region) or {}

    local opts = {}

    if #ledger == 0 then
        opts[#opts+1] = {
            title = 'No VAT ledger entries.',
            description = 'This business has no recorded INPUT/OUTPUT/SETTLEMENT entries yet.',
            disabled = true
        }
    else
        for _, row in ipairs(ledger) do
            local dir = row.direction or '?'
            local tag = (dir == 'OUTPUT' and 'Sale')
                     or (dir == 'INPUT' and 'Expense')
                     or (dir == 'SETTLEMENT' and 'Settle')
                     or dir

            local title = ('[%s] %s'):format(tag, fmtMoney(row.tax_amount or 0))
            local desc = ('Base: %s | Rate: %.2f%% | %s\n%s'):format(
                fmtMoney(row.base_amount or 0),
                tonumber(row.tax_rate or 0) or 0,
                row.ref_text or '',
                row.created_at or ''
            )

            opts[#opts+1] = {
                title       = title,
                description = desc,
                disabled    = true
            }
        end
    end

    lib.registerContext({
        id = 'vat_audit_detail_' .. tostring(business_id),
        title = ('VAT Ledger — %s (%s)'):format(business_name, region),
        menu  = 'vat_audit_main',
        canClose = true,
        options = opts
    })
    lib.showContext('vat_audit_detail_' .. tostring(business_id))
end)
