-- 017_device_fingerprint.sql
-- 多设备支持：按设备指纹区分同一账号的不同终端（修复"两个终端坍缩成一个设备"）。
-- 在 Supabase SQL Editor 执行。

ALTER TABLE public.vpn_devices
  ADD COLUMN IF NOT EXISTS fingerprint text;

-- 同一用户 + 同一指纹 = 同一台设备（同设备重装/丢缓存时复用，不同设备各自独立）。
CREATE UNIQUE INDEX IF NOT EXISTS vpn_devices_user_fp_key
  ON public.vpn_devices (user_id, fingerprint)
  WHERE fingerprint IS NOT NULL AND is_active;
