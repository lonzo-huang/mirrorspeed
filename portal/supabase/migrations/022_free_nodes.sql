-- ============================================================
-- Migration 022: free_nodes —— 共享(免费机场)节点池
--
-- 由控制机上的抓取器(ms-free-nodes.py，systemd timer）定时从扫描器订阅源拉取、
-- 解析、写入这张表。App 通过 /api/mobile/free-nodes 拉取，交给 sing-box 引擎连接。
--
-- 全部是「加法」：不动任何现有表，实验失败也不影响现网付费用户。
-- ============================================================

CREATE TABLE IF NOT EXISTS public.free_nodes (
  id           UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  -- 去重指纹：protocol|server|port|password/uuid 的 hash，同一节点多次抓取只更新
  fingerprint  TEXT        NOT NULL UNIQUE,
  protocol     TEXT        NOT NULL,          -- vless / trojan / ss / vmess / hysteria2 / anytls
  name         TEXT,                          -- 展示名（订阅里的 #备注，已 urldecode）
  server       TEXT        NOT NULL,
  port         INTEGER     NOT NULL,
  country_code TEXT,                          -- 由抓取器按 server IP 归属地填（可空）
  -- sing-box outbound JSON（端上零解析，直接塞进 sing-box 配置的 outbounds）
  outbound     JSONB       NOT NULL,
  -- 质量指标（若扫描器订阅带了就填，否则留空由后续实测补）
  latency_ms   INTEGER,
  score        REAL,
  -- 生命周期
  is_active    BOOLEAN     NOT NULL DEFAULT true,
  first_seen   TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen    TIMESTAMPTZ NOT NULL DEFAULT now(),  -- 每次抓取到就刷新
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_free_nodes_active   ON public.free_nodes(is_active, last_seen DESC);
CREATE INDEX IF NOT EXISTS idx_free_nodes_country  ON public.free_nodes(country_code);

ALTER TABLE public.free_nodes ENABLE ROW LEVEL SECURITY;
-- 无公共策略：抓取器用 service_role 写；App 通过服务端 API（带 JWT）读，不直接暴露表。
