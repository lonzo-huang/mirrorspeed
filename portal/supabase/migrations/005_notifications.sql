-- ============================================================
-- Migration 005: Subscription notifications + lang preference
-- ============================================================

-- Add notified_expiry flag to subscriptions
-- Prevents duplicate expiry warning emails from being sent
ALTER TABLE public.subscriptions
  ADD COLUMN IF NOT EXISTS notified_expiry BOOLEAN NOT NULL DEFAULT false;

-- Add lang preference to profiles
-- Stored when the user picks a language in the app
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS lang TEXT NOT NULL DEFAULT 'en';

-- Add plan_key to subscriptions (text-based plan identifier)
-- Used by our webhook and checkout flow instead of plan_id FK
ALTER TABLE public.subscriptions
  ADD COLUMN IF NOT EXISTS plan_key TEXT;

-- Add stripe_payment_intent_id to payments (used by CN one-time payments)
ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS stripe_payment_intent_id TEXT UNIQUE;

-- Reset notified_expiry whenever a subscription is renewed/reactivated
CREATE OR REPLACE FUNCTION reset_expiry_notification()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  -- Reset notification flag when subscription becomes active again
  IF NEW.status = 'active' AND OLD.status != 'active' THEN
    NEW.notified_expiry = false;
  END IF;
  -- Also reset when expiry date is extended
  IF NEW.expires_at IS DISTINCT FROM OLD.expires_at AND NEW.expires_at > now() THEN
    NEW.notified_expiry = false;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER subscription_reset_notification
  BEFORE UPDATE ON public.subscriptions
  FOR EACH ROW EXECUTE FUNCTION reset_expiry_notification();
