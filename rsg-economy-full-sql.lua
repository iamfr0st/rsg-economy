-- --------------------------------------------------------

--
-- Table structure for table `economy_auto_payments`
--

CREATE TABLE `economy_auto_payments` (
  `id` int(10) UNSIGNED NOT NULL,
  `region_name` varchar(64) NOT NULL,
  `kind` varchar(32) NOT NULL,
  `label` varchar(100) NOT NULL,
  `amount_cents` int(11) NOT NULL DEFAULT 0,
  `interval_secs` int(11) NOT NULL DEFAULT 86400,
  `enabled` tinyint(1) NOT NULL DEFAULT 1,
  `last_run_at` int(10) UNSIGNED NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

--
-- Indexes for table `economy_auto_payments`
--
ALTER TABLE `economy_auto_payments`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_econauto_region` (`region_name`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `economy_auto_payments`
--
ALTER TABLE `economy_auto_payments`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;
COMMIT;

-- --------------------------------------------------------

--
-- Table structure for table `economy_businesses`
--

CREATE TABLE `economy_businesses` (
  `id` int(10) UNSIGNED NOT NULL,
  `citizenid` varchar(64) NOT NULL,
  `region_name` varchar(64) NOT NULL,
  `name` varchar(128) NOT NULL,
  `vat_registered` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

--
-- Indexes for table `economy_businesses`
--
ALTER TABLE `economy_businesses`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_business_owner_region` (`citizenid`,`region_name`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `economy_businesses`
--
ALTER TABLE `economy_businesses`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=12;
COMMIT;

-- --------------------------------------------------------

--
-- Table structure for table `economy_land_plots`
--

CREATE TABLE `economy_land_plots` (
  `id` int(10) UNSIGNED NOT NULL,
  `citizenid` varchar(50) NOT NULL,
  `region_name` varchar(64) NOT NULL,
  `plot_name` varchar(100) NOT NULL,
  `value_dollars` int(11) NOT NULL DEFAULT 0,
  `property_rate` decimal(6,3) NOT NULL DEFAULT 0.000,
  `last_tax_time` int(10) UNSIGNED NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `economy_land_plots`
--
ALTER TABLE `economy_land_plots`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_econland_citizen` (`citizenid`),
  ADD KEY `idx_econland_region` (`region_name`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `economy_land_plots`
--
ALTER TABLE `economy_land_plots`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;
COMMIT;

-- --------------------------------------------------------

--
-- Table structure for table `economy_revenue`
--

CREATE TABLE `economy_revenue` (
  `region_name` varchar(64) NOT NULL,
  `balance_cents` bigint(20) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

--
-- Dumping data for table `economy_revenue`
--

INSERT INTO `economy_revenue` (`region_name`, `balance_cents`) VALUES
('lemoyne', 55),
('new_hanover', 28464);

--
-- Indexes for dumped tables
--

--
-- Indexes for table `economy_revenue`
--
ALTER TABLE `economy_revenue`
  ADD PRIMARY KEY (`region_name`);
COMMIT;

-- --------------------------------------------------------

--
-- Table structure for table `economy_revenue_ledger`
--

CREATE TABLE `economy_revenue_ledger` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `occurred_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `region_name` varchar(64) NOT NULL,
  `tax_category` varchar(16) NOT NULL,
  `amount_cents` bigint(20) NOT NULL,
  `subtotal_cents` bigint(20) NOT NULL,
  `buyer_identifier` varchar(64) DEFAULT NULL,
  `seller_citizenid` varchar(64) DEFAULT NULL,
  `description` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

--
-- Indexes for table `economy_revenue_ledger`
--
ALTER TABLE `economy_revenue_ledger`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_region_time` (`region_name`,`occurred_at`),
  ADD KEY `idx_region_cat_time` (`region_name`,`tax_category`,`occurred_at`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `economy_revenue_ledger`
--
ALTER TABLE `economy_revenue_ledger`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=472;
COMMIT;

-- --------------------------------------------------------

--
-- Table structure for table `economy_taxes`
--

CREATE TABLE `economy_taxes` (
  `id` int(10) UNSIGNED NOT NULL,
  `region_name` varchar(64) NOT NULL,
  `tax_category` varchar(16) NOT NULL,
  `tax_percent` decimal(6,3) NOT NULL DEFAULT 0.000
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

--
-- Indexes for table `economy_taxes`
--
ALTER TABLE `economy_taxes`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_region_cat` (`region_name`,`tax_category`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `economy_taxes`
--
ALTER TABLE `economy_taxes`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=17;
COMMIT;

-- --------------------------------------------------------

--
-- Table structure for table `economy_treasury`
--

CREATE TABLE `economy_treasury` (
  `region_hash` varchar(16) NOT NULL,
  `balance` bigint(20) NOT NULL DEFAULT 0,
  `updated_at` timestamp NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `lawman_fund_cents` bigint(20) NOT NULL DEFAULT 0,
  `medic_fund_cents` bigint(20) NOT NULL DEFAULT 0,
  `region_name` varchar(64) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `economy_treasury`
--
ALTER TABLE `economy_treasury`
  ADD PRIMARY KEY (`region_hash`);
COMMIT;

-- --------------------------------------------------------

--
-- Table structure for table `economy_vat_accounts`
--

CREATE TABLE `economy_vat_accounts` (
  `id` int(10) UNSIGNED NOT NULL,
  `business_id` int(10) UNSIGNED NOT NULL,
  `region_name` varchar(64) NOT NULL,
  `vat_input_cents` bigint(20) NOT NULL DEFAULT 0,
  `vat_output_cents` bigint(20) NOT NULL DEFAULT 0,
  `vat_settled_cents` bigint(20) NOT NULL DEFAULT 0,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

--
-- Indexes for table `economy_vat_accounts`
--
ALTER TABLE `economy_vat_accounts`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_business_region` (`business_id`,`region_name`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `economy_vat_accounts`
--
ALTER TABLE `economy_vat_accounts`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `economy_vat_accounts`
--
ALTER TABLE `economy_vat_accounts`
  ADD CONSTRAINT `fk_vat_accounts_business` FOREIGN KEY (`business_id`) REFERENCES `economy_businesses` (`id`) ON DELETE CASCADE;
COMMIT;

-- --------------------------------------------------------

--
-- Table structure for table `economy_vat_ledger`
--

CREATE TABLE `economy_vat_ledger` (
  `id` int(10) UNSIGNED NOT NULL,
  `business_id` int(10) UNSIGNED NOT NULL,
  `region_name` varchar(64) NOT NULL,
  `direction` enum('INPUT','OUTPUT','SETTLEMENT') NOT NULL,
  `base_amount` decimal(10,2) NOT NULL DEFAULT 0.00,
  `tax_amount` decimal(10,2) NOT NULL DEFAULT 0.00,
  `tax_rate` decimal(5,2) NOT NULL DEFAULT 0.00,
  `ref_text` varchar(255) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

--
-- Indexes for table `economy_vat_ledger`
--
ALTER TABLE `economy_vat_ledger`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_vat_business_region` (`business_id`,`region_name`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `economy_vat_ledger`
--
ALTER TABLE `economy_vat_ledger`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=174;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `economy_vat_ledger`
--
ALTER TABLE `economy_vat_ledger`
  ADD CONSTRAINT `fk_vat_ledger_business` FOREIGN KEY (`business_id`) REFERENCES `economy_businesses` (`id`) ON DELETE CASCADE;
COMMIT;
