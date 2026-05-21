-- ── 004_free_quota.sql ─────────────────────────────────────────────────────
-- 免费用户每日流量额度追踪
-- 执行方式：Supabase Dashboard → SQL Editor → 粘贴并运行

-- ── 1. 可配置参数表（无需重新部署即可调整额度）─────────────────────────────
CREATE TABLE IF NOT EXISTS public.app_config (
  key        TEXT PRIMARY KEY,
  value      TEXT NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 默认免费日流量额度：500 MB = 524288000 bytes
-- 修改方式：UPDATE public.app_config SET value = '1073741824' WHERE key = 'free_daily_bytes'; -- 1GB
INSERT INTO public.app_config (key, value)
VALUES ('free_daily_bytes', '524288000')
ON CONFLICT (key) DO NOTHING;

-- RLS
ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "all_read_config"   ON public.app_config;
DROP POLICY IF EXISTS "admin_edit_config" ON public.app_config;

CREATE POLICY "all_read_config"   ON public.app_config FOR SELECT USING (TRUE);
CREATE POLICY "admin_edit_config" ON public.app_config FOR ALL   USING (is_admin());

-- ── 2. vpn_device_peers 加流量追踪字段 ──────────────────────────────────────
ALTER TABLE public.vpn_device_peers
  ADD COLUMN IF NOT EXISTS last_total_bytes BIGINT  NOT NULL DEFAULT 0,
  -- ^ WireGuard 上次采样时的累计字节数（rx+tx）；用于计算增量，处理 WG 重启后归零
  ADD COLUMN IF NOT EXISTS daily_bytes      BIGINT  NOT NULL DEFAULT 0,
  -- ^ 今日已用字节（每次 cron 增量叠加）
  ADD COLUMN IF NOT EXISTS daily_reset_at   DATE    NOT NULL DEFAULT CURRENT_DATE,
  -- ^ 上次重置日期；cron 发现 daily_reset_at < TODAY 时重置计数器
  ADD COLUMN IF NOT EXISTS is_suspended     BOOLEAN NOT NULL DEFAULT FALSE;
  -- ^ true = 超额暂停中（AllowedIPs 被清空）
