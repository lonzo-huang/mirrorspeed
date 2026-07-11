-- ============================================================
-- Migration 018: Refund requests (退款申请)
-- 用户提交的退款申请，供管理后台审核。截图存 Vercel Blob，url 记录于此。
-- 仅服务端（service_role / admin client）读写，不开放 RLS 公共策略。
-- ============================================================

CREATE TABLE IF NOT EXISTS public.refund_requests (
  id            UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id       UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  email         TEXT        NOT NULL,
  reason_code   TEXT        NOT NULL,
  reason_label  TEXT,
  detail        TEXT,
  screenshot_url TEXT,
  plan          TEXT,
  status        TEXT        NOT NULL DEFAULT 'pending',  -- pending / approved / rejected / refunded
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_refund_requests_created ON public.refund_requests(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_refund_requests_status  ON public.refund_requests(status);

ALTER TABLE public.refund_requests ENABLE ROW LEVEL SECURITY;
-- 无公共策略：仅 service_role 可访问（管理后台 / API 使用 admin client）。
