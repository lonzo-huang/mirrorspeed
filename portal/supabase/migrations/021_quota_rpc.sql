-- ============================================================
-- Migration 021: 配额判定下沉到数据库，大幅削减 Supabase egress
--
-- 背景：控制机每 60s 把 vpn_device_peers 全表（带 device join）拉出来在本地算，
-- 约 100KB+/次 × 1440 次/天 ≈ 4GB/月 —— 免费额度才 5GB，这一项就能吃光。
-- 现改为：库内算好，只返回「需要变更状态的 peer」（绝大多数轮次是空数组）。
--
-- 判定规则与原 JS/Python 实现保持一致：
--   付费用户(active 订阅) 或 新的一天 或 用量已回落 → 需要恢复(resume)
--   免费用户且当日总用量 > free_daily_bytes        → 需要暂停(suspend)
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_quota_actions()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_quota  bigint;
  v_today  text := to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD');
  v_result json;
BEGIN
  SELECT COALESCE((SELECT value FROM app_config WHERE key = 'free_daily_bytes'),
                  '524288000')::bigint INTO v_quota;

  WITH live AS (            -- 活跃 peer + 其设备/用户
    SELECT p.id, p.peer_name, p.server_id, p.is_suspended,
           COALESCE(p.daily_reset_at::text, '') AS reset_at,
           CASE WHEN COALESCE(p.daily_reset_at::text,'') >= v_today
                THEN COALESCE(p.daily_bytes, 0) ELSE 0 END AS bytes,
           d.id AS device_id, d.user_id
    FROM vpn_device_peers p
    JOIN vpn_devices d ON d.id = p.device_id
    WHERE p.is_active = true AND d.is_active = true
  ),
  dev AS (                  -- 按设备聚合当日用量 + 是否付费
    SELECT l.device_id,
           SUM(l.bytes) AS total,
           BOOL_OR(s.user_id IS NOT NULL) AS is_paid
    FROM live l
    LEFT JOIN subscriptions s
           ON s.user_id = l.user_id AND s.status = 'active'
    GROUP BY l.device_id
  ),
  decided AS (
    SELECT l.id, l.peer_name, l.server_id, l.is_suspended,
           (l.reset_at < v_today)                                AS is_new_day,
           d.is_paid,
           (NOT d.is_paid AND d.total > v_quota)                 AS is_over
    FROM live l JOIN dev d ON d.device_id = l.device_id
  )
  SELECT json_build_object(
    'quota_bytes', v_quota,
    -- 需要恢复：已被暂停，且（付费 / 新的一天 / 用量已回落到额度内）
    'resume', COALESCE((SELECT json_agg(json_build_object(
                  'id', id, 'peer_name', peer_name, 'server_id', server_id))
                FROM decided
                WHERE is_suspended AND (is_paid OR is_new_day OR NOT is_over)), '[]'::json),
    -- 需要暂停：未暂停，且免费用户已超额
    'suspend', COALESCE((SELECT json_agg(json_build_object(
                  'id', id, 'peer_name', peer_name, 'server_id', server_id))
                FROM decided
                WHERE NOT is_suspended AND is_over), '[]'::json)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

-- 仅 service_role 调用（控制机）；不授权 anon。
REVOKE ALL ON FUNCTION public.get_quota_actions() FROM PUBLIC, anon;
