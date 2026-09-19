-- 023_iap_apple.sql
-- Apple App Store in-app purchase (auto-renewable subscriptions) support.
-- Self-contained: safe whether or not 015_iap_google.sql was run. Idempotent.
--
-- For platform='apple':
--   store_purchase_token = originalTransactionId (stable across renewals → unique key)
--   store_order_id       = latest transactionId
--   store_product_id     = App Store productId
--
-- App Store Connect product IDs (auto-renewable, one subscription group):
--   vip_monthly (1 month) · vip_quarterly (3 months) · vip_halfyear (6 months) · vip_yearly (1 year)
--
-- Run in Supabase SQL Editor.

-- ── columns (also covered by 015; IF NOT EXISTS keeps this safe) ────────────
ALTER TABLE plans
  ADD COLUMN IF NOT EXISTS google_product_id   text,
  ADD COLUMN IF NOT EXISTS billing_period_days integer,
  ADD COLUMN IF NOT EXISTS apple_product_id    text;

ALTER TABLE subscriptions
  ADD COLUMN IF NOT EXISTS platform             text NOT NULL DEFAULT 'stripe',
  ADD COLUMN IF NOT EXISTS store_product_id     text,
  ADD COLUMN IF NOT EXISTS store_purchase_token text,
  ADD COLUMN IF NOT EXISTS store_order_id       text,
  ADD COLUMN IF NOT EXISTS auto_renewing        boolean NOT NULL DEFAULT false;

CREATE UNIQUE INDEX IF NOT EXISTS subscriptions_store_purchase_token_key
  ON subscriptions (store_purchase_token) WHERE store_purchase_token IS NOT NULL;

-- ── map App Store products to plans ─────────────────────────────────────────
-- Reuse existing rows where possible (Google tiers / legacy "Monthly VPN").
UPDATE plans SET apple_product_id = google_product_id
 WHERE google_product_id IN ('vip_monthly', 'vip_quarterly', 'vip_yearly')
   AND apple_product_id IS NULL;

UPDATE plans SET apple_product_id = 'vip_monthly', billing_period_days = COALESCE(billing_period_days, 30)
 WHERE name = 'Monthly VPN' AND apple_product_id IS NULL
   AND NOT EXISTS (SELECT 1 FROM plans WHERE apple_product_id = 'vip_monthly');

-- Insert whatever is still missing. Prices here are informational only —
-- the amount actually charged comes from Apple.
INSERT INTO plans (name, description, max_devices, price_usd_cents, price_eur_cents, price_cny_fen,
                   apple_product_id, billing_period_days, is_active)
SELECT v.name, v.descr, 4, v.usd, v.usd, v.cny, v.pid, v.days, true
  FROM (VALUES
    ('Monthly VPN',   '1-month plan',  'vip_monthly',   30,  299,  2400),
    ('Quarterly VPN', '3-month plan',  'vip_quarterly', 90,  599,  3900),
    ('Half-Year VPN', '6-month plan',  'vip_halfyear',  180, 999,  6600),
    ('Yearly VPN',    '12-month plan', 'vip_yearly',    365, 1399, 10800)
  ) AS v(name, descr, pid, days, usd, cny)
 WHERE NOT EXISTS (SELECT 1 FROM plans p WHERE p.apple_product_id = v.pid);

CREATE UNIQUE INDEX IF NOT EXISTS plans_apple_product_id_key
  ON plans (apple_product_id) WHERE apple_product_id IS NOT NULL;

-- ── Notification log: dedupe Apple re-deliveries + audit trail ──────────────
CREATE TABLE IF NOT EXISTS public.apple_notifications (
  notification_uuid       text PRIMARY KEY,
  notification_type       text,
  subtype                 text,
  environment             text,
  original_transaction_id text,
  user_id                 uuid,
  result                  text,          -- applied / ignored / no_user / error:...
  received_at             timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS apple_notifications_otid_idx
  ON public.apple_notifications (original_transaction_id);

-- Only the service role (server) touches this table.
ALTER TABLE public.apple_notifications ENABLE ROW LEVEL SECURITY;

-- Check: should list 4 rows
SELECT name, apple_product_id, billing_period_days FROM plans
 WHERE apple_product_id IS NOT NULL ORDER BY billing_period_days;
