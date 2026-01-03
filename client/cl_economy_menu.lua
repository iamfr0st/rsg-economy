-- cl_economy_menu.lua
-- rsg-economy / client / cl_economy_menu.lua
-- ox_lib UI wrapper for all economy commands (FIXED)

local function ensureLib()
    if not lib or not lib.registerContext then
        print('[rsg-economy] ox_lib not available on client.')
        return false
    end
    return true
end

local function openTaxMenu()
    if not ensureLib() then return end

    lib.registerContext({
        id = 'rsg_economy_tax_menu',
        title = 'Regional Taxes',
        options = {
            {
                title = 'Set Tax',
                description = 'Set property/trade/sales tax for a region.',
                onSelect = function()
                    local input = lib.inputDialog('Set Tax', {
                        { type = 'input', label = 'Region (name or "here")', default = 'here' },
                        { type = 'select', label = 'Category', options = {
                            { label = 'Sales', value = 'sales' },
                            { label = 'Trade', value = 'trade' },
                            { label = 'Property', value = 'property' },
                        }},
                        { type = 'number', label = 'Percent', default = 2.0, min = 0, max = 100 },
                    })
                    if not input then return end

                    ExecuteCommand(('settax %s %s %s'):format(input[1] or 'here', input[2] or 'sales', tonumber(input[3] or 0) or 0))
                end
            },
            {
                title = 'Clear Tax',
                description = 'Clear property/trade/sales/all for a region.',
                onSelect = function()
                    local input = lib.inputDialog('Clear Tax', {
                        { type = 'input', label = 'Region (name or "here")', default = 'here' },
                        { type = 'select', label = 'Category', default = 'all', options = {
                            { label = 'All', value = 'all' },
                            { label = 'Sales', value = 'sales' },
                            { label = 'Trade', value = 'trade' },
                            { label = 'Property', value = 'property' },
                        }},
                    })
                    if not input then return end

                    ExecuteCommand(('cleartax %s %s'):format(input[1] or 'here', input[2] or 'all'))
                end
            },
            {
                title = 'Check Taxes',
                description = 'Show tax rates for a region.',
                onSelect = function()
                    local input = lib.inputDialog('Check Taxes', {
                        { type = 'input', label = 'Region (name or "here")', default = 'here' },
                    })
                    if not input then return end
                    ExecuteCommand(('gettax %s'):format(input[1] or 'here'))
                end
            },
            {
                title = 'Debug Tax',
                description = 'Debug tax calculation (for staff).',
                onSelect = function()
                    local input = lib.inputDialog('Debug Tax', {
                        { type = 'input', label = 'Region (name or "here")', default = 'here' },
                        { type = 'select', label = 'Category', default = 'sales', options = {
                            { label = 'Sales', value = 'sales' },
                            { label = 'Trade', value = 'trade' },
                            { label = 'Property', value = 'property' },
                        }},
                        { type = 'number', label = 'Base Amount', default = 10, min = 0 },
                    })
                    if not input then return end

                    ExecuteCommand(('debugtax %s %s %s'):format(input[1] or 'here', input[2] or 'sales', tonumber(input[3] or 10) or 10))
                end
            },
        }
    })

    lib.showContext('rsg_economy_tax_menu')
end

local function openBusinessMenu()
    if not ensureLib() then return end

    lib.registerContext({
        id = 'rsg_economy_business_menu',
        title = 'Business & VAT',
        options = {
            {
                title = 'Register Business',
                description = 'Register/update your business in this region.',
                onSelect = function()
                    local input = lib.inputDialog('Register Business', {
                        { type = 'input', label = 'Region (name or "here")', default = 'here' },
                        { type = 'input', label = 'License Type (shop/market/etc)', default = 'shop' },
                        { type = 'input', label = 'Business Name', placeholder = 'My General Store' },
                    })
                    if not input then return end

                    local region      = input[1] or 'here'
                    local licenseType = input[2] or 'general'
                    local name        = input[3] or 'Business'

                    ExecuteCommand(('registerbiz %s %s "%s"'):format(region, licenseType, name))
                end
            },
            {
                title = 'Unregister Business',
                description = 'Remove your business registration in this region.',
                onSelect = function()
                    local input = lib.inputDialog('Unregister Business', {
                        { type = 'input', label = 'Region (name or "here")', default = 'here' },
                    })
                    if not input then return end
                    ExecuteCommand(('unregisterbiz %s'):format(input[1] or 'here'))
                end
            },
            {
                title = 'My Business Info',
                description = 'Show your business details in this region.',
                onSelect = function()
                    local input = lib.inputDialog('Business Info', {
                        { type = 'input', label = 'Region (name or "here")', default = 'here' },
                    })
                    if not input then return end
                    ExecuteCommand(('bizinfo %s'):format(input[1] or 'here'))
                end
            },
            {
                title = 'My VAT Dashboard',
                description = 'Opens your VAT dashboard (requires a business in your region).',
                onSelect = function()
                    -- Uses your server command that triggers rsg-economy:openVatMenu
                    ExecuteCommand('vatmenu')
                end
            }
        }
    })

    lib.showContext('rsg_economy_business_menu')
end

local function openLandMenu()
    if not ensureLib() then return end

    lib.registerContext({
        id = 'rsg_economy_land_menu',
        title = 'Land & Property Tax',
        options = {
            {
                title = 'Register Land',
                description = 'Register land/plot for property tax.',
                onSelect = function()
                    local input = lib.inputDialog('Register Land', {
                        { type = 'input',  label = 'Region (name or "here")', default = 'here' },
                        { type = 'number', label = 'Value ($)', default = 1000, min = 0 },
                        { type = 'number', label = 'Tax Rate (% per interval)', default = 1.0, min = 0 },
                        { type = 'input',  label = 'Plot Name', placeholder = 'Valentine Ranch' },
                    })
                    if not input then return end

                    ExecuteCommand(('registerland %s %s %s "%s"'):format(
                        input[1] or 'here',
                        tonumber(input[2] or 0) or 0,
                        tonumber(input[3] or 0) or 0,
                        input[4] or 'Land Plot'
                    ))
                end
            },
            {
                title = 'My Land',
                description = 'List your registered land plots.',
                onSelect = function()
                    ExecuteCommand('landinfo')
                end
            },
        }
    })

    lib.showContext('rsg_economy_land_menu')
end

local function openReportsMenu()
    if not ensureLib() then return end

    lib.registerContext({
        id = 'rsg_economy_reports_menu',
        title = 'Economy Reports',
        options = {
            {
                title = 'Region Revenue Report',
                description = 'Summary of tax revenue for a region.',
                onSelect = function()
                    local input = lib.inputDialog('Economy Report', {
                        { type = 'input',  label = 'Region (name or "here")', default = 'here' },
                        { type = 'number', label = 'Days Lookback', default = 30, min = 1, max = 90 },
                    })
                    if not input then return end

                    ExecuteCommand(('econreport %s %s'):format(input[1] or 'here', tonumber(input[2] or 30) or 30))
                end
            },
            {
                title = 'Treasury → AutoPay (future hook)',
                description = 'Configure autopayments via another UI later.',
                disabled = true
            },
        }
    })

    lib.showContext('rsg_economy_reports_menu')
end

local function openMainEconomyMenu()
    if not ensureLib() then return end

    lib.registerContext({
        id = 'rsg_economy_main_menu',
        title = 'Regional Economy',
        options = {
            { title = 'Taxes',          description = 'Set, clear, and view regional taxes.', icon = 'scale-balanced', onSelect = openTaxMenu },
            { title = 'Businesses & VAT', description = 'Register businesses and manage VAT.',  icon = 'store',          onSelect = openBusinessMenu },
            { title = 'Land / Property', description = 'Register land and view property tax.', icon = 'map',            onSelect = openLandMenu },
            { title = 'Reports',        description = 'View region revenue summaries.',       icon = 'chart-column',   onSelect = openReportsMenu },
        }
    })

    lib.showContext('rsg_economy_main_menu')
end

RegisterCommand('economy', function()
    openMainEconomyMenu()
end, false)
