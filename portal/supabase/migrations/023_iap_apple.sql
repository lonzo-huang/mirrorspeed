-- 023_iap_apple.sql
-- Apple App Store in-app purchase (auto-renewable subscriptions) support.
-- Builds on 015_iap_google.sql (subscriptions.platform / store_* columns).
--
-- For platform='apple':
--   store_purchase_token = originalTransactionId (stable across renewals → unique key)
--   store_order_id       = latest transactionId
--   store_product_id     = App Store productId
--
-- Run in Supabase SQL Editor.

-- ── plans: App Store product id per tier ─────────────────────────────────────
ALTER TABLE plans
  ADD COLUMN IF NOT EXISTS apple_product_id text;

-- Default to the same ids as Google Play. Create the products in App Store
-- Connect with exactly these Product IDs (or update these rows to match).
UPDATE plans SET apple_product_id = google_product_id
 WHERE google_product_id IS NOT NULL AND apple_product_id IS NULL;

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
