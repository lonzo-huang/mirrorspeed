-- ============================================================
-- Migration 020: get_ratelimit_config() RPC
-- 把原 Vercel /api/vpn/ratelimit-sync 的逻辑搬进数据库：在 Postgres 内部
-- 算好三档限速值 + 三档 IP 列表，只返回聚合结果（不含用户隐私）。
-- VPN 服务器的 ms-ratelimit-sync.py 直接用 anon key 调用它，绕开 Vercel。
--
-- 安全：SECURITY DEFINER（以函数属主身份读表，绕过 RLS），仅返回内网 IP 分档，
-- 无 PII；授权 anon 执行即可。
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_ratelimit_config()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_free  int;
  v_paid  int;
  v_super int;
  v_super_ids jsonb;
  v_result json;
BEGIN
  -- 限速档位（app_config，缺省回退：free=4 / paid=10 / super=0=不限速）
  SELECT COALESCE((SELECT value FROM app_config WHERE key='ratelimit_free_mbit'),  '4')::int  INTO v_free;
  SELECT COALESCE((SELECT value FROM app_config WHERE key='ratelimit_paid_mbit'),  '10')::int INTO v_paid;
  SELECT COALESCE((SELECT value FROM app_config WHERE key='ratelimit_super_mbit'), '0')::int  INTO v_super;
  BEGIN
    SELECT COALESCE((SELECT value FROM app_config WHERE key='super_user_ids'), '[]')::jsonb INTO v_super_ids;
  EXCEPTION WHEN others THEN
    v_super_ids := '[]'::jsonb;   -- super_user_ids 非法 JSON 时降级为空
  END;

  WITH devs AS (
    -- vpn_ip 是 inet 类型：用 host() 取不带掩码的地址（等价于原 JS 的 split('/')[0]）
    SELECT host(vpn_ip) AS ip, user_id
    FROM vpn_devices
    WHERE is_active = true AND vpn_ip IS NOT NULL
  ),
  paid_users AS (
    SELECT user_id FROM subscriptions WHERE status = 'active'
    UNION
    SELECT id      FROM profiles      WHERE referral_bonus_expires_at > now()
  ),
  tiered AS (
    SELECT d.ip,
      MAX(
        CASE
          WHEN v_super_ids ? d.user_id::text                THEN 2   -- 超级
          WHEN d.user_id IN (SELECT user_id FROM paid_users) THEN 1   -- 付费
          ELSE 0                                                      -- 免费
        END
      ) AS tier
    FROM devs d
    WHERE d.ip <> ''
    GROUP BY d.ip
  )
  SELECT json_build_object(
    'free_mbit',  v_free,
    'paid_mbit',  v_paid,
    'super_mbit', v_super,
    'free_ips',  COALESCE((SELECT json_agg(ip) FROM tiered WHERE tier = 0), '[]'::json),
    'paid_ips',  COALESCE((SELECT json_agg(ip) FROM tiered WHERE tier = 1), '[]'::json),
    'super_ips', COALESCE((SELECT json_agg(ip) FROM tiered WHERE tier = 2), '[]'::json)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

-- 允许匿名（anon key）调用；只返回内网 IP 分档，无敏感数据。
GRANT EXECUTE ON FUNCTION public.get_ratelimit_config() TO anon;
