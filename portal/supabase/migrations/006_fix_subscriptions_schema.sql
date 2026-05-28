-- ============================================================
-- Migration 006: Fix subscriptions schema for new billing flow
-- ============================================================

-- plan_id is no longer required (we use plan_key text instead)
ALTER TABLE public.subscriptions
  ALTER COLUMN plan_id DROP NOT NULL;

-- currency defaults to usd
ALTER TABLE public.subscriptions
  ALTER COLUMN currency SET DEFAULT 'usd';

-- Remove the partial unique index (only covers active rows, can't be used for upsert)
DROP INDEX IF EXISTS subscriptions_one_active_per_user;

-- Add a proper unique constraint on user_id so upsert works reliably
-- (one subscription record per user — historical records go to payments table)
ALTER TABLE public.subscriptions
  ADD CONSTRAINT subscriptions_user_id_unique UNIQUE (user_id);
