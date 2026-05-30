-- ============================================================
-- Migration 009: Harden handle_new_user() trigger
-- ============================================================
-- Problem: any exception inside the AFTER INSERT trigger on auth.users
-- propagates back to Supabase Auth and produces a 500
-- "Database error saving new user" (unexpected_failure), blocking sign-up.
--
-- Fix:
--   1. Generate a unique referral_code (profiles.referral_code is NOT NULL UNIQUE).
--   2. Wrap everything in EXCEPTION WHEN OTHERS so trigger failures never block
--      user creation.
--   3. Guard against rare NULL email (anonymous / magic-link edge cases).
--   4. Keep ON CONFLICT (id) DO NOTHING for idempotency.

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  _code     TEXT;
  _attempts INT := 0;
BEGIN
  -- Generate a unique 6-char referral code (A-Z0-9 minus confusable 0/O/I/l/1)
  LOOP
    _code := upper(
      substring(
        translate(encode(gen_random_bytes(6), 'base64'), '+/=0OIl1', 'ABCDEFGH'),
        1, 6
      )
    );
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.profiles WHERE referral_code = _code);
    _attempts := _attempts + 1;
    EXIT WHEN _attempts >= 10;  -- give up after 10 tries (fallback below)
  END LOOP;

  -- Fallback: use 8 hex chars from user UUID (guaranteed unique-enough)
  IF _attempts >= 10 THEN
    _code := upper(substring(replace(NEW.id::text, '-', ''), 1, 8));
  END IF;

  INSERT INTO public.profiles (id, email, display_name, avatar_url, referral_code)
  VALUES (
    NEW.id,
    COALESCE(NEW.email, ''),
    COALESCE(
      NEW.raw_user_meta_data->>'full_name',
      split_part(COALESCE(NEW.email, ''), '@', 1)
    ),
    NEW.raw_user_meta_data->>'avatar_url',
    _code
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  -- Log the error for debugging but never block user creation
  RAISE WARNING 'handle_new_user() failed for user %: % (SQLSTATE: %)',
                NEW.id, SQLERRM, SQLSTATE;
  RETURN NEW;
END;
$$;
