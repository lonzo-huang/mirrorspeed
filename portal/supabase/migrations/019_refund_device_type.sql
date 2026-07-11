-- ============================================================
-- Migration 019: 退款申请增加「终端类型」字段
-- 记录用户所用平台/机型，便于统计各平台需求（如 Mac/iOS 未支持导致的退款）。
-- 值示例：'Apple / iPhone'、'Android / Huawei'、'PC / Windows 11'
-- ============================================================

ALTER TABLE public.refund_requests
  ADD COLUMN IF NOT EXISTS device_type TEXT;
