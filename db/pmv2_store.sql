-- ============================================================
-- Project Misfits v2 - Webstore database
--
-- Run this on the SAME database your FiveM server uses (oxmysql),
-- so the website and the city share purchases, coins and priority.
-- Works on MySQL 8.0.16+ and MariaDB 10.4+.
--
-- Safe to run more than once: every table uses IF NOT EXISTS.
--
-- How it fits together:
--   Stripe payment -> webhook -> pmv2_store_orders + order_items
--     coins     -> pmv2_store_coin_ledger + pmv2_store_wallets (credited instantly, spent in-city)
--     priority  -> pmv2_store_entitlements (queue reads it when the player connects)
--     packages  -> pmv2_store_entitlements (status 'pending_setup' until staff finish setup)
--     anything that must be handed over in-city -> pmv2_store_deliveries (pmv2_store resource picks it up)
--
-- Players are matched by Discord ID (they log in with Discord at checkout,
-- and FiveM sees the same Discord account as the identifier "discord:<id>").
-- ============================================================

SET NAMES utf8mb4;

-- ------------------------------------------------------------
-- Customers: one row per Discord account that has bought something
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pmv2_store_customers (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  discord_id        VARCHAR(32)  NOT NULL,              -- Discord user ID (snowflake), e.g. 123456789012345678
  discord_username  VARCHAR(64)  NULL,
  discord_avatar    VARCHAR(128) NULL,
  email             VARCHAR(255) NULL,                  -- from Stripe receipt, contact only (never used as game identity)
  fivem_license     VARCHAR(64)  NULL,                  -- filled in by the city the first time they connect, e.g. license:abc...
  last_citizenid    VARCHAR(50)  NULL,                  -- last QBox character used, for staff lookups
  created_at        DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at        DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  last_seen_ingame  DATETIME(3)  NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_customers_discord (discord_id),
  KEY idx_customers_license (fivem_license)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- Orders: one row per paid (or attempted) Stripe Checkout Session
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pmv2_store_orders (
  id                     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  order_ref              VARCHAR(16)  NOT NULL,          -- short code players give staff, e.g. PM-7K3QX2
  stripe_session_id      VARCHAR(255) NOT NULL,          -- cs_...
  stripe_payment_intent  VARCHAR(255) NULL,              -- pi_...
  customer_id            BIGINT UNSIGNED NOT NULL,
  discord_id             VARCHAR(32)  NOT NULL,          -- copy of the buyer's Discord ID for quick lookups
  email                  VARCHAR(255) NULL,
  status                 ENUM('pending','paid','partially_refunded','refunded','disputed','canceled')
                         NOT NULL DEFAULT 'pending',
  currency               CHAR(3)      NOT NULL DEFAULT 'usd',
  amount_subtotal        INT UNSIGNED NOT NULL DEFAULT 0, -- all money in cents
  amount_discount        INT UNSIGNED NOT NULL DEFAULT 0,
  amount_tax             INT UNSIGNED NOT NULL DEFAULT 0,
  amount_total           INT UNSIGNED NOT NULL DEFAULT 0,
  amount_refunded        INT UNSIGNED NOT NULL DEFAULT 0,
  promo_code             VARCHAR(64)  NULL,
  discord_ticket_id      VARCHAR(32)  NULL,              -- purchase-support ticket channel the bot opened (packages)
  staff_note             TEXT         NULL,
  created_at             DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  paid_at                DATETIME(3)  NULL,
  refunded_at            DATETIME(3)  NULL,
  updated_at             DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_orders_ref (order_ref),
  UNIQUE KEY uq_orders_session (stripe_session_id),
  KEY idx_orders_payment_intent (stripe_payment_intent),
  KEY idx_orders_customer (customer_id),
  KEY idx_orders_discord (discord_id),
  KEY idx_orders_status_created (status, created_at),
  CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id) REFERENCES pmv2_store_customers (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- Order items: one row per product line in an order
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pmv2_store_order_items (
  id                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  order_id            BIGINT UNSIGNED NOT NULL,
  product_slug        VARCHAR(64)  NOT NULL,             -- matches lib/products.js, e.g. 100-coins, gang, gold-priority
  product_title       VARCHAR(128) NOT NULL,
  kind                ENUM('coins','priority','package') NOT NULL,
  quantity            SMALLINT UNSIGNED NOT NULL DEFAULT 1,
  unit_amount         INT UNSIGNED NOT NULL,             -- cents, price actually charged per unit
  coins_each          INT UNSIGNED NULL,                 -- coin bundles only, e.g. 100
  fulfillment_status  ENUM('pending','processing','delivered','fulfilled','revoked','failed')
                      NOT NULL DEFAULT 'pending',
  fulfilled_by        VARCHAR(64)  NULL,                 -- 'system' or the staff member's Discord ID
  fulfilled_at        DATETIME(3)  NULL,
  staff_note          TEXT         NULL,
  created_at          DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at          DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_items_order (order_id),
  KEY idx_items_kind_status (kind, fulfillment_status),
  KEY idx_items_slug (product_slug),
  CONSTRAINT fk_items_order FOREIGN KEY (order_id) REFERENCES pmv2_store_orders (id) ON DELETE CASCADE,
  CONSTRAINT chk_items_qty CHECK (quantity BETWEEN 1 AND 10)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- Stripe webhook events already handled.
-- Stripe can send the same event more than once; the webhook inserts the
-- event ID first and skips it if it's already here, so nothing is granted twice.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pmv2_store_webhook_events (
  stripe_event_id  VARCHAR(255) NOT NULL,                -- evt_...
  event_type       VARCHAR(64)  NOT NULL,                -- e.g. checkout.session.completed, charge.refunded
  stripe_object_id VARCHAR(255) NULL,                    -- cs_... / ch_... / pi_...
  status           ENUM('processing','processed','failed') NOT NULL DEFAULT 'processing',
  error            TEXT         NULL,
  received_at      DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  processed_at     DATETIME(3)  NULL,
  PRIMARY KEY (stripe_event_id),
  KEY idx_webhook_object (stripe_object_id),
  KEY idx_webhook_status (status, received_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- Misfit Coin wallets: current balance per customer.
-- Always change this together with a pmv2_store_coin_ledger row
-- in the same transaction.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pmv2_store_wallets (
  customer_id         BIGINT UNSIGNED NOT NULL,
  balance             INT NOT NULL DEFAULT 0,            -- can only go below 0 if spent coins are later refunded
  lifetime_purchased  INT UNSIGNED NOT NULL DEFAULT 0,
  lifetime_spent      INT UNSIGNED NOT NULL DEFAULT 0,
  updated_at          DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (customer_id),
  CONSTRAINT fk_wallets_customer FOREIGN KEY (customer_id) REFERENCES pmv2_store_customers (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- Coin ledger: every coin added or removed, forever (never update or delete rows).
-- Spending in the city (VIP shop etc.) writes a 'spend' row here.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pmv2_store_coin_ledger (
  id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  customer_id    BIGINT UNSIGNED NOT NULL,
  delta          INT NOT NULL,                           -- +100 purchase, -25 spend, -100 refund
  reason         ENUM('purchase','spend','refund','admin_grant','admin_remove','reversal') NOT NULL,
  balance_after  INT NOT NULL,
  order_item_id  BIGINT UNSIGNED NULL,                   -- set for purchase/refund rows
  reference      VARCHAR(128) NULL,                      -- what was bought in-city, or why staff changed it
  idempotency_key VARCHAR(128) NULL,                     -- stops double grants/spends, e.g. 'purchase:<order_item_id>'
  actor          VARCHAR(64)  NOT NULL DEFAULT 'system', -- 'system', 'city:<citizenid>', 'staff:<discord_id>'
  created_at     DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_ledger_idempotency (idempotency_key),
  KEY idx_ledger_customer_created (customer_id, created_at),
  KEY idx_ledger_order_item (order_item_id),
  CONSTRAINT fk_ledger_customer FOREIGN KEY (customer_id) REFERENCES pmv2_store_customers (id),
  CONSTRAINT fk_ledger_item FOREIGN KEY (order_item_id) REFERENCES pmv2_store_order_items (id),
  CONSTRAINT chk_ledger_delta CHECK (delta <> 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- Entitlements: things a customer owns that last over time.
--   priority -> tier bronze/silver/gold, read by the queue when they connect
--   package  -> gang/family/business/mlo, 'pending_setup' until staff finish it
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pmv2_store_entitlements (
  id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  customer_id    BIGINT UNSIGNED NOT NULL,
  discord_id     VARCHAR(32)  NOT NULL,                  -- copy for fast lookups at connect time
  order_item_id  BIGINT UNSIGNED NULL,                   -- NULL when staff grant it by hand
  type           ENUM('priority','package') NOT NULL,
  product_slug   VARCHAR(64)  NOT NULL,                  -- gold-priority, gang, mlo, ...
  tier           VARCHAR(32)  NULL,                      -- priority: bronze / silver / gold
  status         ENUM('pending_setup','active','expired','revoked') NOT NULL DEFAULT 'active',
  starts_at      DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  expires_at     DATETIME(3)  NULL,                      -- NULL = never expires
  details        JSON         NULL,                      -- e.g. {"gang_name":"...","mlo":"..."}
  revoked_reason VARCHAR(255) NULL,
  created_at     DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at     DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_ent_discord_type_status (discord_id, type, status),
  KEY idx_ent_customer (customer_id),
  KEY idx_ent_item (order_item_id),
  KEY idx_ent_expires (status, expires_at),
  CONSTRAINT fk_ent_customer FOREIGN KEY (customer_id) REFERENCES pmv2_store_customers (id),
  CONSTRAINT fk_ent_item FOREIGN KEY (order_item_id) REFERENCES pmv2_store_order_items (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- Deliveries: anything that must be handed to the player while they're in the city
-- (an item, a vehicle, or just a "your coins arrived" message).
-- The pmv2_store resource checks for 'pending' rows for online players,
-- claims them, delivers, then marks them 'delivered'. If the server is off or
-- the player is offline, the row simply waits.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pmv2_store_deliveries (
  id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  customer_id    BIGINT UNSIGNED NOT NULL,
  discord_id     VARCHAR(32)  NOT NULL,
  order_item_id  BIGINT UNSIGNED NULL,
  action         VARCHAR(32)  NOT NULL,                  -- 'notify', 'give_item', 'give_vehicle', ...
  payload        JSON         NULL,                      -- e.g. {"message":"100 Misfit Coins added"}
  status         ENUM('pending','claimed','delivered','failed','canceled') NOT NULL DEFAULT 'pending',
  attempts       TINYINT UNSIGNED NOT NULL DEFAULT 0,
  last_error     VARCHAR(255) NULL,
  claimed_at     DATETIME(3)  NULL,                      -- a 'claimed' row older than a few minutes can be retried
  delivered_to   VARCHAR(50)  NULL,                      -- citizenid that received it
  delivered_at   DATETIME(3)  NULL,
  created_at     DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_deliv_discord_status (discord_id, status),
  KEY idx_deliv_status_created (status, created_at),
  KEY idx_deliv_item (order_item_id),
  CONSTRAINT fk_deliv_customer FOREIGN KEY (customer_id) REFERENCES pmv2_store_customers (id),
  CONSTRAINT fk_deliv_item FOREIGN KEY (order_item_id) REFERENCES pmv2_store_order_items (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- Audit log: who did what (owner refunds, staff coin changes, fulfillments)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pmv2_store_audit_log (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  actor        VARCHAR(64)  NOT NULL,                    -- 'owner', 'system', 'staff:<discord_id>', 'city'
  action       VARCHAR(64)  NOT NULL,                    -- 'order.paid', 'order.refunded', 'coins.admin_grant', ...
  target_type  VARCHAR(32)  NULL,                        -- 'order', 'customer', 'entitlement', ...
  target_id    VARCHAR(64)  NULL,
  details      JSON         NULL,
  ip_address   VARCHAR(45)  NULL,
  created_at   DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY idx_audit_target (target_type, target_id),
  KEY idx_audit_actor_created (actor, created_at),
  KEY idx_audit_action_created (action, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ------------------------------------------------------------
-- Handy view: each customer's coins and best active priority tier.
-- The queue / VIP shop can read this in one query.
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW pmv2_store_player_status AS
SELECT
  c.id          AS customer_id,
  c.discord_id,
  c.fivem_license,
  COALESCE(w.balance, 0) AS coins,
  (
    SELECT e.tier
    FROM pmv2_store_entitlements e
    WHERE e.customer_id = c.id
      AND e.type = 'priority'
      AND e.status = 'active'
      AND e.starts_at <= CURRENT_TIMESTAMP(3)
      AND (e.expires_at IS NULL OR e.expires_at > CURRENT_TIMESTAMP(3))
    ORDER BY FIELD(e.tier, 'gold', 'silver', 'bronze')
    LIMIT 1
  ) AS priority_tier
FROM pmv2_store_customers c
LEFT JOIN pmv2_store_wallets w ON w.customer_id = c.id;

-- ============================================================
-- OPTIONAL: separate login for the website (recommended).
-- The webstore only gets access to the store tables, never your
-- players / inventories. Replace the password, run as an admin,
-- then put these details in Coolify (never in GitHub).
-- Change `your_fivem_db` to your FiveM database name and
-- '%' to the website server's IP if you can.
-- ============================================================
-- CREATE USER IF NOT EXISTS 'pmv2_web'@'%' IDENTIFIED BY 'CHANGE_ME_TO_A_LONG_RANDOM_PASSWORD';
-- GRANT SELECT, INSERT, UPDATE ON your_fivem_db.pmv2_store_customers      TO 'pmv2_web'@'%';
-- GRANT SELECT, INSERT, UPDATE ON your_fivem_db.pmv2_store_orders         TO 'pmv2_web'@'%';
-- GRANT SELECT, INSERT, UPDATE ON your_fivem_db.pmv2_store_order_items    TO 'pmv2_web'@'%';
-- GRANT SELECT, INSERT, UPDATE ON your_fivem_db.pmv2_store_webhook_events TO 'pmv2_web'@'%';
-- GRANT SELECT, INSERT, UPDATE ON your_fivem_db.pmv2_store_wallets        TO 'pmv2_web'@'%';
-- GRANT SELECT, INSERT         ON your_fivem_db.pmv2_store_coin_ledger    TO 'pmv2_web'@'%';
-- GRANT SELECT, INSERT, UPDATE ON your_fivem_db.pmv2_store_entitlements   TO 'pmv2_web'@'%';
-- GRANT SELECT, INSERT, UPDATE ON your_fivem_db.pmv2_store_deliveries     TO 'pmv2_web'@'%';
-- GRANT SELECT, INSERT         ON your_fivem_db.pmv2_store_audit_log      TO 'pmv2_web'@'%';
-- GRANT SELECT                 ON your_fivem_db.pmv2_store_player_status  TO 'pmv2_web'@'%';
-- FLUSH PRIVILEGES;
