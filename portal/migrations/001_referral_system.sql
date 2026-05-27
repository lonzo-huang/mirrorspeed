-- ============================================================
-- Migration: 邀请/推荐系统
-- 在 Supabase Dashboard → SQL Editor 中执行此文件
-- ============================================================

-- 1. profiles 表新增邀请相关字段
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS referral_code          TEXT UNIQUE,
  ADD COLUMN IF NOT EXISTS referred_by            UUID REFERENCES profiles(id),
  ADD COLUMN IF NOT EXISTS referral_bonus_expires_at TIMESTAMPTZ;

-- 2. 为已有用户批量生成邀请码（6位大写字母+数字，排除易混淆字符）
UPDATE profiles
SET referral_code = upper(
  substring(
    translate(encode(gen_random_bytes(6), 'base64'), '+/=0OIl1', 'ABCDEFGH'),
    1, 6
  )
)
WHERE referral_code IS NULL;

-- 3. 设为 NOT NULL（批量填充完成后）
ALTER TABLE profiles
  ALTER COLUMN referral_code SET NOT NULL;

-- 4. referral_rewards 表（记录每次邀请奖励）
-- invitee_id UNIQUE：每个被邀请人只能触发一次奖励（防止续费重复奖励）
CREATE TABLE IF NOT EXISTS referral_rewards (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_id  UUID        NOT NULL REFERENCES profiles(id),
  invitee_id   UUID        NOT NULL UNIQUE REFERENCES profiles(id),
  plan_name    TEXT,
  bonus_days   INT         NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_referral_rewards_referrer
  ON referral_rewards(referrer_id);

-- 5. Row Level Security（仅允许查看自己的奖励记录）
ALTER TABLE referral_rewards ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own referral rewards"
  ON referral_rewards FOR SELECT
  USING (referrer_id = auth.uid());
