-- ============================================================
-- Migration 001: Core Schema
-- ============================================================

-- 启用 pgcrypto（用于加密私钥）
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ── profiles ─────────────────────────────────────────────────────────────
-- auth.users 由 Supabase Auth 自动管理，此表存业务扩展字段
CREATE TABLE public.profiles (
  id            UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email         TEXT        NOT NULL,
  display_name  TEXT,
  avatar_url    TEXT,
  role          TEXT        NOT NULL DEFAULT 'user'
                            CHECK (role IN ('user', 'admin')),
  preferred_currency TEXT   NOT NULL DEFAULT 'usd'
                            CHECK (preferred_currency IN ('usd', 'eur', 'cny')),
  stripe_customer_id TEXT   UNIQUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── plans ─────────────────────────────────────────────────────────────────
CREATE TABLE public.plans (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name           TEXT        NOT NULL,            -- 'Monthly VPN'
  description    TEXT,
  max_devices    INT         NOT NULL DEFAULT 2,
  -- 三个货币的价格（单位：最小货币单位，如分）
  price_usd_cents INT        NOT NULL,            -- $9.99 → 999
  price_eur_cents INT        NOT NULL,            -- €9.99 → 999
  price_cny_fen   INT        NOT NULL,            -- ¥68   → 6800
  -- Stripe Price IDs（在 Stripe Dashboard 创建后填入）
  stripe_price_usd TEXT,
  stripe_price_eur TEXT,
  stripe_price_cny TEXT,
  is_active      BOOLEAN     NOT NULL DEFAULT true,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── subscriptions ─────────────────────────────────────────────────────────
CREATE TABLE public.subscriptions (
  id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id              UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  plan_id              UUID        NOT NULL REFERENCES public.plans(id),
  status               TEXT        NOT NULL DEFAULT 'pending'
                                   CHECK (status IN ('pending','active','past_due','cancelled','expired')),
  currency             TEXT        NOT NULL CHECK (currency IN ('usd','eur','cny')),
  -- 实际到账金额（Stripe 返回）
  amount_paid_cents    INT,
  started_at           TIMESTAMPTZ,
  expires_at           TIMESTAMPTZ,
  -- Stripe 关联 ID
  stripe_subscription_id TEXT      UNIQUE,
  stripe_latest_invoice  TEXT,
  cancel_at_period_end   BOOLEAN   NOT NULL DEFAULT false,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 每个用户同一时间只能有一条 active 订阅
CREATE UNIQUE INDEX subscriptions_one_active_per_user
  ON public.subscriptions(user_id)
  WHERE status = 'active';

-- ── vpn_devices ──────────────────────────────────────────────────────────
CREATE TABLE public.vpn_devices (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  subscription_id  UUID        REFERENCES public.subscriptions(id) ON DELETE SET NULL,
  -- 对应 VPN 服务器上的 peer 名称，格式: uid_shortid，如 abc123_d1
  peer_name        TEXT        NOT NULL UNIQUE,
  -- WireGuard 密钥（private_key 加密存储）
  public_key       TEXT        NOT NULL,
  private_key_enc  TEXT        NOT NULL,   -- pgp_sym_encrypt(private_key, app_secret)
  preshared_key_enc TEXT       NOT NULL,
  vpn_ip           TEXT        NOT NULL,   -- 10.200.0.x/32
  -- 订阅 URL token（唯一，用于 Clash 拉取配置）
  sub_token        TEXT        NOT NULL UNIQUE DEFAULT gen_random_uuid()::TEXT,
  device_label     TEXT        NOT NULL DEFAULT '新设备',
  os_hint          TEXT,                   -- 'windows'|'macos'|'ios'|'android'|'linux'
  is_active        BOOLEAN     NOT NULL DEFAULT true,
  last_handshake_at TIMESTAMPTZ,           -- 从 VPN 服务器同步
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 每用户最多 2 台设备（触发器强制）
CREATE OR REPLACE FUNCTION check_device_limit()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF (
    SELECT COUNT(*) FROM public.vpn_devices
    WHERE user_id = NEW.user_id AND is_active = true
  ) >= 2 THEN
    RAISE EXCEPTION 'Device limit reached: maximum 2 devices per account';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER enforce_device_limit
  BEFORE INSERT ON public.vpn_devices
  FOR EACH ROW EXECUTE FUNCTION check_device_limit();

-- ── payments ──────────────────────────────────────────────────────────────
CREATE TABLE public.payments (
  id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id              UUID        NOT NULL REFERENCES public.profiles(id),
  subscription_id      UUID        REFERENCES public.subscriptions(id),
  amount_cents         INT         NOT NULL,
  currency             TEXT        NOT NULL,
  status               TEXT        NOT NULL CHECK (status IN ('succeeded','failed','refunded','pending')),
  stripe_payment_id    TEXT        UNIQUE,
  stripe_invoice_id    TEXT,
  description          TEXT,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── audit_log ──────────────────────────────────────────────────────────────
-- 用于虚拟结算审计追踪
CREATE TABLE public.audit_log (
  id          BIGSERIAL   PRIMARY KEY,
  user_id     UUID        REFERENCES public.profiles(id),
  action      TEXT        NOT NULL,  -- 'device_added'|'sub_activated'|'sub_expired'|...
  detail      JSONB,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── 自动更新 updated_at ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER subscriptions_updated_at
  BEFORE UPDATE ON public.subscriptions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ── 新用户自动创建 profile（Auth 注册触发）─────────────────────────────────
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (id, email, display_name, avatar_url)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
    NEW.raw_user_meta_data->>'avatar_url'
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ── 初始套餐数据（价格待 Stripe Price ID 填入后更新）──────────────────────
INSERT INTO public.plans (name, description, max_devices, price_usd_cents, price_eur_cents, price_cny_fen)
VALUES (
  'Monthly VPN',
  '高速企业专线，支持 2 台设备同时在线，每月计费',
  2,
  999,    -- $9.99
  999,    -- €9.99
  6800    -- ¥68.00
);
