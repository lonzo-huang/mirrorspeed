-- ============================================================
-- Migration 002: Row Level Security
-- 普通用户只能读写自己的数据，admin 可读全部
-- ============================================================

ALTER TABLE public.profiles    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.plans       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vpn_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log   ENABLE ROW LEVEL SECURITY;

-- ── 辅助函数：判断当前用户是否为 admin ────────────────────────────────────
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin'
  );
$$;

-- ── profiles ──────────────────────────────────────────────────────────────
CREATE POLICY "users: read own profile"
  ON public.profiles FOR SELECT
  USING (id = auth.uid() OR is_admin());

CREATE POLICY "users: update own profile"
  ON public.profiles FOR UPDATE
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid() AND role = 'user'); -- 不允许自改 role

CREATE POLICY "admin: full access profiles"
  ON public.profiles FOR ALL
  USING (is_admin());

-- ── plans（所有登录用户可读）────────────────────────────────────────────
CREATE POLICY "anyone: read active plans"
  ON public.plans FOR SELECT
  USING (is_active = true OR is_admin());

CREATE POLICY "admin: manage plans"
  ON public.plans FOR ALL
  USING (is_admin());

-- ── subscriptions ────────────────────────────────────────────────────────
CREATE POLICY "users: read own subscriptions"
  ON public.subscriptions FOR SELECT
  USING (user_id = auth.uid() OR is_admin());

CREATE POLICY "admin: manage subscriptions"
  ON public.subscriptions FOR ALL
  USING (is_admin());

-- ── vpn_devices ──────────────────────────────────────────────────────────
CREATE POLICY "users: read own devices"
  ON public.vpn_devices FOR SELECT
  USING (user_id = auth.uid() OR is_admin());

-- 用户不能直接 INSERT（只能通过 API Route + service_role 创建）
CREATE POLICY "admin: manage devices"
  ON public.vpn_devices FOR ALL
  USING (is_admin());

-- ── payments ─────────────────────────────────────────────────────────────
CREATE POLICY "users: read own payments"
  ON public.payments FOR SELECT
  USING (user_id = auth.uid() OR is_admin());

CREATE POLICY "admin: manage payments"
  ON public.payments FOR ALL
  USING (is_admin());

-- ── audit_log ────────────────────────────────────────────────────────────
CREATE POLICY "admin: read audit log"
  ON public.audit_log FOR SELECT
  USING (is_admin());

-- audit_log 只允许 service_role 写入（通过 API 服务端写）
