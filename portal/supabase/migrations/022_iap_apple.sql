-- 022_iap_apple.sql
-- Apple App Store 内购（自动续订订阅）支持。
-- 纯增量：不改动 Stripe / Google Play 现有流程。
--
-- 在 Supabase SQL Editor 里执行。

-- ── plans：每个套餐对应一个 App Store 产品 id ────────────────────────────────
ALTER TABLE plans
  ADD COLUMN IF NOT EXISTS apple_product_id text;

-- ── subscriptions：苹果侧的稳定标识 ─────────────────────────────────────────
-- Apple 的 originalTransactionId 唯一标识「一条订阅」，续订/恢复购买都不变，
-- 相当于 Google 的 purchase token。用它做幂等键，服务器通知重复投递也不会写重。
ALTER TABLE subscriptions
  ADD COLUMN IF NOT EXISTS apple_original_transaction_id text;

CREATE UNIQUE INDEX IF NOT EXISTS subscriptions_apple_original_txn_key
  ON subscriptions (apple_original_transaction_id)
  WHERE apple_original_transaction_id IS NOT NULL;

-- platform 现有取值：'stripe'(默认/历史) | 'google_play' | 'apple'
-- 015 里没加 CHECK 约束，这里也不加，避免与历史数据冲突。

-- ── 套餐 ↔ App Store 产品 id 映射 ──────────────────────────────────────────
-- 产品 id 需与 App Store Connect 里创建的自动续订订阅完全一致。
-- 价格由苹果按档位收取（月 $2.99 / 半年 $8.99 / 年 $11.99 / 两年 $20.99），
-- 与官网价一致（抽成由我们承担，不加价）。
UPDATE plans SET apple_product_id = 'com.mirrorspeed.vip.monthly',  billing_period_days = 30
 WHERE google_product_id = 'vip_monthly' OR name = 'Monthly VPN';

UPDATE plans SET apple_product_id = 'com.mirrorspeed.vip.quarterly', billing_period_days = 90
 WHERE google_product_id = 'vip_quarterly' OR name = 'Quarterly VPN';

INSERT INTO plans (name, description, max_devices,
                   price_usd_cents, price_eur_cents, price_cny_fen,
                   apple_product_id, billing_period_days, is_active)
SELECT 'Half-Year VPN', '6-month plan', 3, 899, 899, 6600,
       'com.mirrorspeed.vip.halfyear', 182, true
WHERE NOT EXISTS (SELECT 1 FROM plans WHERE apple_product_id = 'com.mirrorspeed.vip.halfyear');

UPDATE plans SET apple_product_id = 'com.mirrorspeed.vip.yearly', billing_period_days = 365
 WHERE google_product_id = 'vip_yearly' OR name = 'Yearly VPN';

INSERT INTO plans (name, description, max_devices,
                   price_usd_cents, price_eur_cents, price_cny_fen,
                   apple_product_id, billing_period_days, is_active)
SELECT '2-Year VPN', '24-month plan', 3, 2099, 2099, 19200,
       'com.mirrorspeed.vip.biennial', 730, true
WHERE NOT EXISTS (SELECT 1 FROM plans WHERE apple_product_id = 'com.mirrorspeed.vip.biennial');

-- 年付若不存在（历史库可能没 seed 过）则补一条
INSERT INTO plans (name, description, max_devices,
                   price_usd_cents, price_eur_cents, price_cny_fen,
                   apple_product_id, billing_period_days, is_active)
SELECT 'Yearly VPN', '12-month plan', 3, 1199, 1199, 10800,
       'com.mirrorspeed.vip.yearly', 365, true
WHERE NOT EXISTS (SELECT 1 FROM plans WHERE apple_product_id = 'com.mirrorspeed.vip.yearly');
