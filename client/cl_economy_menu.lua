-- cl_economy_menu.lua
-- rsg-economy / client / cl_economy_menu.lua
-- ox_lib UI wrapper for all economy commands (FIXED)
lib.locale()

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
        title = locale('tax_title') or 'Regional Taxes',
        options = {
            {
                title = locale('set_tax') or 'Set Tax',
                description = locale('set_tax_description') or 'Set property/trade/sales tax for a region.',
                onSelect = function()
                    local input = lib.inputDialog(locale('set_tax') or 'Set Tax', {
                        { type = 'input', label = locale('region_label') or 'Region (name or "here")', default = 'here' },
                        { type = 'select', label = locale('category_label') or 'Category', options = {
                            { label = locale('sales_label') or 'Sales', value = 'sales' },
                            { label = locale('trade_label') or 'Trade', value = 'trade' },
                            { label = locale('property_label') or 'Property', value = 'property' },
                        }},
                        { type = 'number', label = locale('percent_label') or 'Percent', default = 2.0, min = 0, max = 100 },
                    })
                    if not input then return end

                    ExecuteCommand(('settax %s %s %s'):format(input[1] or 'here', input[2] or 'sales', tonumber(input[3] or 0) or 0))
                end
            },
            {
                title = locale('clear_tax') or 'Clear Tax',
                description = locale('clear_tax_description') or 'Clear property/trade/sales/all for a region.',
                onSelect = function()
                    local input = lib.inputDialog(locale('clear_tax') or 'Clear Tax', {
                        { type = 'input', label = locale('region_label') or 'Region (name or "here")', default = 'here' },
                        { type = 'select', label = locale('category_label') or 'Category', default = 'all', options = {
                            { label = locale('all_label') or 'All', value = 'all' },
                            { label = locale('sales_label') or 'Sales', value = 'sales' },
                            { label = locale('trade_label') or 'Trade', value = 'trade' },
                            { label = locale('property_label') or 'Property', value = 'property' },
                        }},
                    })
                    if not input then return end

                    ExecuteCommand(('cleartax %s %s'):format(input[1] or 'here', input[2] or 'all'))
                end
            },
            {
                title = locale('check_taxes') or 'Check Taxes',
                description = locale('check_taxes_description') or 'Show tax rates for a region.',
                onSelect = function()
                    local input = lib.inputDialog(locale('check_taxes') or 'Check Taxes', {
                        { type = 'input', label = locale('region_label') or 'Region (name or "here")', default = 'here' },
                    })
                    if not input then return end
                    ExecuteCommand(('gettax %s'):format(input[1] or 'here'))
                end
            },
            {
                title = locale('debug_tax') or 'Debug Tax',
                description = locale('debug_tax_description') or 'Debug tax calculation (for staff).',
                onSelect = function()
                    local input = lib.inputDialog(locale('debug_tax') or 'Debug Tax', {
                        { type = 'input', label = locale('region_label') or 'Region (name or "here")', default = 'here' },
                        { type = 'select', label = locale('category_label') or 'Category', default = 'sales', options = {
                            { label = locale('sales_label') or 'Sales', value = 'sales' },
                            { label = locale('trade_label') or 'Trade', value = 'trade' },
                            { label = locale('property_label') or 'Property', value = 'property' },
                        }},
                        { type = 'number', label = locale('base_amount_label') or 'Base Amount', default = 10, min = 0 },
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
        title = locale('business_vat') or 'Business & VAT',
        options = {
            {
                title = locale('register_business') or 'Register Business',
                description = locale('register_business_description') or 'Register/update your business in this region.',
                onSelect = function()
                    local input = lib.inputDialog(locale('register_business') or 'Register Business', {
                        { type = 'input', label = locale('region_label') or 'Region (name or "here")', default = 'here' },
                        { type = 'input', label = locale('license_type_label') or 'License Type (shop/market/etc)', default = 'shop' },
                        { type = 'input', label = locale('business_name_label') or 'Business Name', placeholder = locale('business_name_label') or 'My General Store' },
                    })
                    if not input then return end

                    local region      = input[1] or 'here'
                    local licenseType = input[2] or 'general'
                    local name        = input[3] or 'Business'

                    ExecuteCommand(('registerbiz %s %s "%s"'):format(region, licenseType, name))
                end
            },
            {
                title = locale('unregister_business') or 'Unregister Business',
                description = locale('unregister_business_description') or 'Remove your business registration in this region.',
                onSelect = function()
                    local input = lib.inputDialog(locale('unregister_business') or 'Unregister Business', {
                        { type = 'input', label = locale('region_label') or 'Region (name or "here")', default = 'here' },
                    })
                    if not input then return end
                    ExecuteCommand(('unregisterbiz %s'):format(input[1] or 'here'))
                end
            },
            {
                title = locale('my_business_info') or 'My Business Info',
                description = locale('my_business_info_description') or 'Show your business details in this region.',
                onSelect = function()
                    local input = lib.inputDialog(locale('my_business_info') or 'Business Info', {
                        { type = 'input', label = locale('region_label') or 'Region (name or "here")', default = 'here' },
                    })
                    if not input then return end
                    ExecuteCommand(('bizinfo %s'):format(input[1] or 'here'))
                end
            },
            {
                title = locale('my_vat_dashboard') or 'My VAT Dashboard',
                description = locale('my_vat_dashboard_description') or 'Opens your VAT dashboard (requires a business in your region).',
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
        title = locale('land_property_tax') or 'Land & Property Tax',
        options = {
            {
                title = locale('register_land') or 'Register Land',
                description = locale('register_land_description') or 'Register land/plot for property tax.',
                onSelect = function()
                    local input = lib.inputDialog(locale('register_land') or 'Register Land', {
                        { type = 'input',  label = locale('region_label') or 'Region (name or "here")', default = 'here' },
                        { type = 'number', label = locale('value_label') or 'Value ($)', default = 1000, min = 0 },
                        { type = 'number', label = locale('tax_rate_label') or 'Tax Rate (% per interval)', default = 1.0, min = 0 },
                        { type = 'input',  label = locale('plot_name_label') or 'Plot Name', placeholder = locale('plot_name_placeholder') or 'Valentine Ranch' },
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
                title = locale('my_land') or 'My Land',
                description = locale('my_land_description') or 'List your registered land plots.',
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
        title = locale('economy_reports') or 'Economy Reports',
        options = {
            {
                title = locale('region_revenue_report') or 'Region Revenue Report',
                description = locale('region_revenue_report_description') or 'Summary of tax revenue for a region.',
                onSelect = function()
                    local input = lib.inputDialog(locale('economy_report') or 'Economy Report', {
                        { type = 'input',  label = locale('region_label') or 'Region (name or "here")', default = 'here' },
                        { type = 'number', label = locale('days_lookback_label') or 'Days Lookback', default = 30, min = 1, max = 90 },
                    })
                    if not input then return end

                    ExecuteCommand(('econreport %s %s'):format(input[1] or 'here', tonumber(input[2] or 30) or 30))
                end
            },
            {
                title = locale('treasury_autopay') or 'Treasury → AutoPay (future hook)',
                description = locale('treasury_autopay_description') or 'Configure autopayments via another UI later.',
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
        title = locale('regional_economy') or 'Regional Economy',
        options = {
            { title = locale('taxes') or 'Taxes',          description = locale('taxes_description') or 'Set, clear, and view regional taxes.', icon = 'scale-balanced', onSelect = openTaxMenu },
            { title = locale('businesses_vat') or 'Businesses & VAT', description = locale('businesses_vat_description') or 'Register businesses and manage VAT.',  icon = 'store',          onSelect = openBusinessMenu },
            { title = locale('land_property') or 'Land / Property', description = locale('land_property_description') or 'Register land and view property tax.', icon = 'map',            onSelect = openLandMenu },
            { title = locale('reports') or 'Reports',        description = locale('reports_description') or 'View region revenue summaries.',       icon = 'chart-column',   onSelect = openReportsMenu },
        }
    })

    lib.showContext('rsg_economy_main_menu')
end

RegisterCommand('economy', function()
    openMainEconomyMenu()
end, false)
