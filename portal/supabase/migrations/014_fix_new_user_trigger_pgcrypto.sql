-- ============================================================
-- Migration 014: fix handle_new_user() — drop pgcrypto dependency + backfill
-- ============================================================
-- Problem: 009's handle_new_user() calls gen_random_bytes() (from the pgcrypto
-- extension). On Supabase pgcrypto lives in the `extensions` schema, but the
-- function runs with `SET search_path = public`, so gen_random_bytes() is not
-- found -> the function raises -> the `EXCEPTION WHEN OTHERS` swallows it and
-- RETURNs without inserting the profiles row. Result: new auth.users get NO
-- profiles row, and the first device insert fails with
--   vpn_devices_user_id_fkey violation (user_id -> profiles.id).
-- (Existing users already had profiles, so only NEW sign-ups were affected.)
--
-- Fix:
--   1. Generate the referral code with the built-in md5()/random() (core,
--      no extension, always on search_path) instead of gen_random_bytes().
--   2. Backfill profiles for any existing auth.users that are missing one.

-- ── 1. Replace the trigger function ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  _code     TEXT;
  _attempts INT := 0;
BEGIN
  -- Unique 6-char code from md5() (hex 0-9A-F). md5/random are core built-ins,
  -- so this works regardless of where pgcrypto is installed.
  LOOP
    _code := upper(substring(md5(random()::text || NEW.id::text) FROM 1 FOR 6));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.profiles WHERE referral_code = _code);
    _attempts := _attempts + 1;
    EXIT WHEN _attempts >= 10;
  END LOOP;

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
  RAISE WARNING 'handle_new_user() failed for user %: % (SQLSTATE: %)',
                NEW.id, SQLERRM, SQLSTATE;
  RETURN NEW;
END;
$$;

-- ── 2. Backfill profiles for users created while the trigger was broken ───────
INSERT INTO public.profiles (id, email, display_name, referral_code)
SELECT
  u.id,
  COALESCE(u.email, ''),
  split_part(COALESCE(u.email, ''), '@', 1),
  upper(substring(replace(u.id::text, '-', ''), 1, 8))
FROM auth.users u
LEFT JOIN public.profiles p ON p.id = u.id
WHERE p.id IS NULL
ON CONFLICT (id) DO NOTHING;
