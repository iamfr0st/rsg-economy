--========================================================--
-- VAT MENU UI (CLIENT)
--========================================================--

RegisterNetEvent('rsg-economy:openVatMenu', function(data)
    local bizName   = data.business_name or "Business"
    local region    = data.region or "unknown"
    local s         = data.summary or {}
    local citizenid = data.citizenid

    if not lib or not lib.registerContext then
        print('[rsg-economy] ERROR: ox_lib context not available on client.')
        return
    end

    local function money(x)
        return ("$%.2f"):format(tonumber(x) or 0)
    end

    lib.registerContext({
        id = "vat_menu",
        title = ("VAT — %s (%s)"):format(bizName, region),
        canClose = true,
        options = {
            { title = "📤 Output VAT", description = money(s.output),  disabled = true },
            { title = "📥 Input VAT",  description = money(s.input),   disabled = true },
            { title = "💼 Settled",    description = money(s.settled), disabled = true },
            { title = "⚖ Net VAT Due",description = money(s.net_due), disabled = true },

            {
                title = "💰 Settle VAT",
                icon = "circle-check",
                description = (s.net_due > 0)
                    and ("Pay %s to government"):format(money(s.net_due))
                    or ("Refund %s due to you"):format(money(-s.net_due)),
                event = "vat:clientSettle",
                args = { citizenid = citizenid, region = region }
            }
        }
    })

    lib.showContext("vat_menu")
end)
