-- 016_ondemand_provisioning.sql
-- 架构改造 P1：按需建 Peer + /16 子网 的数据库基础。
-- 详见 docs/on-demand-provisioning.md。
-- 在 Supabase SQL Editor 执行。本迁移为加列 + 新表 + 函数，不破坏现网旧路径。

-- ── 1) GC 天数（可配，默认 30）────────────────────────────────────────────────
INSERT INTO public.app_config (key, value)
VALUES ('peer_gc_days', '30')
ON CONFLICT (key) DO NOTHING;

-- ── 2) 设备：一次性密钥对 + 全局唯一内网 IP（跨服务器复用）──────────────────────
ALTER TABLE public.vpn_devices
  ADD COLUMN IF NOT EXISTS vpn_ip          inet,
  ADD COLUMN IF NOT EXISTS public_key      text,
  ADD COLUMN IF NOT EXISTS private_key_enc text;

CREATE UNIQUE INDEX IF NOT EXISTS vpn_devices_vpn_ip_key
  ON public.vpn_devices (vpn_ip) WHERE vpn_ip IS NOT NULL;

-- ── 3) IP 池（方案 B：可回收）────────────────────────────────────────────────
-- 预填 10.200.0.0/16 的可用主机段：10.200.0.2 .. 10.200.255.254
--   （10.200.0.1 = 服务端；.0.0 / .255.255 = 网络/广播，跳过）
CREATE TABLE IF NOT EXISTS public.ip_pool (
  ip           inet PRIMARY KEY,
  device_id    uuid UNIQUE REFERENCES public.vpn_devices(id) ON DELETE SET NULL,
  allocated_at timestamptz
);

-- 仅在首次（空表）时填充，避免重复执行报错
INSERT INTO public.ip_pool (ip)
SELECT ('10.200.0.0'::inet + g)
FROM generate_series(2, 65534) AS g
ON CONFLICT (ip) DO NOTHING;

-- 加速"取下一个空闲 IP"
CREATE INDEX IF NOT EXISTS ip_pool_free_idx ON public.ip_pool (ip) WHERE device_id IS NULL;

-- 分配（幂等 + 并发安全）：已分配则返回原 IP；否则取最小空闲 IP
CREATE OR REPLACE FUNCTION public.allocate_device_ip(p_device_id uuid)
RETURNS inet
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_ip inet;
BEGIN
  SELECT ip INTO v_ip FROM public.ip_pool WHERE device_id = p_device_id LIMIT 1;
  IF FOUND THEN
    RETURN v_ip;
  END IF;

  UPDATE public.ip_pool
     SET device_id = p_device_id, allocated_at = now()
   WHERE ip = (
     SELECT ip FROM public.ip_pool
      WHERE device_id IS NULL
      ORDER BY ip
      LIMIT 1
      FOR UPDATE SKIP LOCKED
   )
  RETURNING ip INTO v_ip;

  IF v_ip IS NULL THEN
    RAISE EXCEPTION 'IP pool exhausted (10.200.0.0/16)';
  END IF;
  RETURN v_ip;
END;
$$;

-- 回收：设备删除/停用时把 IP 还回池
CREATE OR REPLACE FUNCTION public.release_device_ip(p_device_id uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
AS $$
  UPDATE public.ip_pool SET device_id = NULL, allocated_at = NULL WHERE device_id = p_device_id;
$$;

-- ── 4) Peer 台账：记录"该设备在该服务器上是否已 provision" + 最近握手 ──────────
ALTER TABLE public.vpn_device_peers
  ADD COLUMN IF NOT EXISTS provisioned  boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS last_seen_at timestamptz;

-- ── 5) 回填：给现有活跃设备分配全局 IP（密钥由 Portal 之后按需生成）─────────────
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT id FROM public.vpn_devices WHERE is_active = true AND vpn_ip IS NULL LOOP
    UPDATE public.vpn_devices SET vpn_ip = public.allocate_device_ip(r.id) WHERE id = r.id;
  END LOOP;
END $$;
