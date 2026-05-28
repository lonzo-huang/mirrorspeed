-- ============================================================
-- Migration 007: Increase device limit from 2 to 3
-- ============================================================

CREATE OR REPLACE FUNCTION check_device_limit()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF (
    SELECT COUNT(*) FROM public.vpn_devices
    WHERE user_id = NEW.user_id AND is_active = true
  ) >= 3 THEN
    RAISE EXCEPTION 'Device limit reached: maximum 3 devices per account';
  END IF;
  RETURN NEW;
END;
$$;
