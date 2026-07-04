-- 015_iap_google.sql
-- Google Play in-app purchase (subscriptions) support.
-- Additive only — does not touch the existing Stripe flow.
--
-- Run in Supabase SQL Editor.

-- ── plans: map each plan to a Google Play product + billing period ──────────
ALTER TABLE plans
  ADD COLUMN IF NOT EXISTS google_product_id   text,
  ADD COLUMN IF NOT EXISTS billing_period_days integer;

-- ── subscriptions: track which store the sub came from + its receipt ────────
-- platform: 'stripe' (default, legacy) | 'google_play' | 'apple'
ALTER TABLE subscriptions
  ADD COLUMN IF NOT EXISTS platform            text NOT NULL DEFAULT 'stripe',
  ADD COLUMN IF NOT EXISTS store_product_id    text,
  ADD COLUMN IF NOT EXISTS store_purchase_token text,
  ADD COLUMN IF NOT EXISTS store_order_id      text,
  ADD COLUMN IF NOT EXISTS auto_renewing       boolean NOT NULL DEFAULT false;

-- A Google purchase token uniquely identifies one subscription; enforce it so
-- RTDN re-deliveries and re-verifies upsert instead of duplicating.
CREATE UNIQUE INDEX IF NOT EXISTS subscriptions_store_purchase_token_key
  ON subscriptions (store_purchase_token)
  WHERE store_purchase_token IS NOT NULL;

-- ── Seed the 3 IAP tiers ─────────────────────────────────────────────────────
-- Reuse the existing "Monthly VPN" row as the monthly tier; add quarterly + yearly.
UPDATE plans
   SET google_product_id   = 'vip_monthly',
       billing_period_days = 30
 WHERE name = 'Monthly VPN';

INSERT INTO plans (name, description, max_devices,
                   price_usd_cents, price_eur_cents, price_cny_fen,
                   google_product_id, billing_period_days, is_active)
SELECT 'Quarterly VPN', '3-month plan', 3, 2499, 2499, 16800,
       'vip_quarterly', 90, true
WHERE NOT EXISTS (SELECT 1 FROM plans WHERE google_product_id = 'vip_quarterly');

INSERT INTO plans (name, description, max_devices,
                   price_usd_cents, price_eur_cents, price_cny_fen,
                   google_product_id, billing_period_days, is_active)
SELECT 'Yearly VPN', '12-month plan', 3, 7999, 7999, 53800,
       'vip_yearly', 365, true
WHERE NOT EXISTS (SELECT 1 FROM plans WHERE google_product_id = 'vip_yearly');
