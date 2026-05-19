-- ============================================================
-- Migration 003: 多服务器支持
-- 重构 vpn_devices：设备与 Peer 分离，支持一设备多服务器
-- ============================================================

-- ── vpn_servers：服务器注册表 ──────────────────────────────────────────
CREATE TABLE public.vpn_servers (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name            TEXT        NOT NULL,           -- 'HK01'
  display_name    TEXT        NOT NULL,           -- '香港 01'
  location        TEXT        NOT NULL,           -- 'Hong Kong'
  country_code    TEXT        NOT NULL,           -- 'HK'
  flag_emoji      TEXT        NOT NULL DEFAULT '🌐',
  endpoint        TEXT        NOT NULL,           -- 'hk01.vpn.example.com'
  port            INT         NOT NULL DEFAULT 51820,
  public_key      TEXT        NOT NULL,           -- WireGuard 服务端公钥
  api_url         TEXT        NOT NULL,           -- FastAPI 管理 API 地址
  -- 运行时缓存（由 cron 定期刷新，不放 realtime 减少写放大）
  status          TEXT        NOT NULL DEFAULT 'unknown'
                              CHECK (status IN ('online','degraded','offline','unknown')),
  latency_ms      INT,                            -- portal → server 响应时间
  active_peers    INT         NOT NULL DEFAULT 0,
  max_peers       INT         NOT NULL DEFAULT 200,
  load_percent    INT         NOT NULL DEFAULT 0, -- 0-100
  cpu_percent     FLOAT,
  mem_percent     FLOAT,
  bandwidth_mbps  FLOAT,                          -- 当前出口带宽利用率
  last_checked_at TIMESTAMPTZ,
  -- 展示控制
  sort_order      INT         NOT NULL DEFAULT 0, -- 越小越靠前
  is_active       BOOLEAN     NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── vpn_device_peers：设备×服务器 Peer 记录 ───────────────────────────
-- 替代原 vpn_devices 中的密钥字段
-- 一台设备在每个服务器上有独立密钥对
CREATE TABLE public.vpn_device_peers (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id        UUID        NOT NULL REFERENCES public.vpn_devices(id) ON DELETE CASCADE,
  server_id        UUID        NOT NULL REFERENCES public.vpn_servers(id) ON DELETE CASCADE,
  user_id          UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  -- VPN 服务器上的 peer 标识
  peer_name        TEXT        NOT NULL,           -- 格式: u{uid8}_{shortid}_{serverShort}
  public_key       TEXT        NOT NULL,
  private_key_enc  TEXT        NOT NULL,
  preshared_key_enc TEXT       NOT NULL,
  vpn_ip           TEXT        NOT NULL,           -- 10.x.0.y/32
  is_active        BOOLEAN     NOT NULL DEFAULT true,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(device_id, server_id)                     -- 一台设备在每个服务器只有一个 peer
);

-- ── 从 vpn_devices 中移除密钥字段（已迁移到 vpn_device_peers）─────────
-- 以下 ALTER TABLE 仅在 vpn_devices 已存在上述字段时执行
-- 如果是全新部署，001_schema.sql 中的 vpn_devices 已简化，无需执行下面的 DROP
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'vpn_devices' AND column_name = 'private_key_enc'
  ) THEN
    ALTER TABLE public.vpn_devices
      DROP COLUMN IF EXISTS peer_name,
      DROP COLUMN IF EXISTS public_key,
      DROP COLUMN IF EXISTS private_key_enc,
      DROP COLUMN IF EXISTS preshared_key_enc,
      DROP COLUMN IF EXISTS vpn_ip,
      DROP COLUMN IF EXISTS last_handshake_at;
  END IF;
END $$;

-- ── RLS：vpn_servers（所有登录用户可读）──────────────────────────────
ALTER TABLE public.vpn_servers       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vpn_device_peers  ENABLE ROW LEVEL SECURITY;

CREATE POLICY "anyone: read active servers"
  ON public.vpn_servers FOR SELECT
  USING (is_active = true OR is_admin());

CREATE POLICY "admin: manage servers"
  ON public.vpn_servers FOR ALL USING (is_admin());

CREATE POLICY "users: read own device peers"
  ON public.vpn_device_peers FOR SELECT
  USING (user_id = auth.uid() OR is_admin());

CREATE POLICY "admin: manage device peers"
  ON public.vpn_device_peers FOR ALL USING (is_admin());

-- ── 示例服务器数据（部署时修改为实际值）──────────────────────────────
INSERT INTO public.vpn_servers (name, display_name, location, country_code, flag_emoji, endpoint, port, public_key, api_url, sort_order)
VALUES
  ('HK01', '香港 01', 'Hong Kong', 'HK', '🇭🇰', 'hk01.vpn.example.com', 51820, 'PLACEHOLDER_HK01_PUBKEY', 'https://hk01.vpn.example.com:8443', 1),
  ('SG01', '新加坡 01', 'Singapore', 'SG', '🇸🇬', 'sg01.vpn.example.com', 51820, 'PLACEHOLDER_SG01_PUBKEY', 'https://sg01.vpn.example.com:8443', 2),
  ('JP01', '日本 01', 'Tokyo', 'JP', '🇯🇵', 'jp01.vpn.example.com', 51820, 'PLACEHOLDER_JP01_PUBKEY', 'https://jp01.vpn.example.com:8443', 3);
