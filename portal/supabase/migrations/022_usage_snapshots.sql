-- 022_usage_snapshots.sql
-- 用量时序快照：每次采集(如每15分钟/每小时)记录每个节点当前的在线用户数
-- (按套餐分类) + 节点资源指标。用于 admin 分时洞察（北京时间为基准）。
--
-- 设计要点：
--   * 聚合快照，非逐条连接事件 —— 数据量极小（7节点 × 96次/天 × 90天 ≈ 6万行）
--   * bucket_* 列在写入时按北京时间(UTC+8)算好，查询直接 GROUP BY，无需时区转换
--   * 采集端点用 service role 写入；启用 RLS 且不加 policy = 仅 service role 可访问

CREATE TABLE IF NOT EXISTS public.usage_snapshots (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  server_id     UUID NOT NULL REFERENCES public.vpn_servers(id) ON DELETE CASCADE,
  captured_at   TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- 北京时间(UTC+8)分桶，写入时算好
  bucket_date   DATE    NOT NULL,   -- 北京日期 YYYY-MM-DD
  bucket_hour   SMALLINT NOT NULL,  -- 北京小时 0-23
  bucket_min    SMALLINT NOT NULL DEFAULT 0,  -- 0/15/30/45（支持15分钟粒度）

  -- 在线用户数（此刻握手 <3min 的 peer，按套餐分类）
  online_total  INTEGER NOT NULL DEFAULT 0,
  online_paid   INTEGER NOT NULL DEFAULT 0,
  online_free   INTEGER NOT NULL DEFAULT 0,
  online_super  INTEGER NOT NULL DEFAULT 0,

  -- 节点资源指标（来自 vpn-api /stats）
  cpu_percent   NUMERIC(5,2),
  mem_percent   NUMERIC(5,2),
  load_1m       NUMERIC(6,2),
  bw_rx_mbps    NUMERIC(10,2),
  bw_tx_mbps    NUMERIC(10,2),
  active_peers  INTEGER,   -- 服务器报告的活跃 peer 数
  reachable     BOOLEAN NOT NULL DEFAULT true  -- 采集时节点是否可达
);

-- 查询索引：按节点 + 时间范围（画趋势）、按分时桶（聚合规律）
CREATE INDEX IF NOT EXISTS idx_usage_snapshots_server_time
  ON public.usage_snapshots (server_id, captured_at DESC);
CREATE INDEX IF NOT EXISTS idx_usage_snapshots_bucket
  ON public.usage_snapshots (bucket_hour, bucket_min);
CREATE INDEX IF NOT EXISTS idx_usage_snapshots_captured
  ON public.usage_snapshots (captured_at DESC);

-- 仅 service role 访问（采集端点/admin API 均走 service role，绕过 RLS）
ALTER TABLE public.usage_snapshots ENABLE ROW LEVEL SECURITY;
