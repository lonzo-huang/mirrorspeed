-- ============================================================
-- Migration 024: get_quota_actions() 只处理 provisioned=true 的 peer
--
-- 背景：节点上被 gc 掉的 peer（provisioned=false）若 is_active 仍为 true，
-- 会被 get_quota_actions 反复挑中要 suspend/resume；控制机下发时节点回 404，
-- 无法生效，于是每轮空转、反复横跳（额外的 PostgREST 写入 + 节点调用）。
--
-- 修复：live CTE 增加 p.provisioned = true，从源头排除"节点上已不存在"的僵尸 peer。
-- 配合控制机侧的自愈（set_peer_active 收到 404 时把该 peer 标 provisioned=false），
-- 僵尸行会被自动清出循环。
-- 仅此一处改动；其余判定逻辑与 021 完全一致。
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
      AND p.provisioned = true   -- 024: 排除节点上已不存在(gc 过)的僵尸 peer
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
