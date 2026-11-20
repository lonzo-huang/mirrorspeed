-- Migration 20261120: 给 ip_pool 补上 RLS
--
-- 背景：016_ondemand_provisioning.sql 建 public.ip_pool 时漏了 ENABLE ROW LEVEL
-- SECURITY（其余 13 张表都有）。Supabase 安全顾问 2026-11-14 报 rls_disabled_in_public
-- Critical：任何人拿公开 anon key 即可读/改/删全表，可读出 WG 内网 IP ↔ 设备 ID 映射，
-- 或清空分配导致新设备 provision 失败。
--
-- 这张表只由两个 SECURITY DEFINER 函数（allocate_device_ip / release_device_ip）
-- 和 service_role 访问，两者都绕过 RLS，因此**不需要任何 policy**：
-- 开启 RLS 后对 anon / authenticated 默认全部拒绝，业务逻辑零影响。
-- 切勿为「方便」加 policy，客户端永远不该直连这张表。

ALTER TABLE public.ip_pool ENABLE ROW LEVEL SECURITY;

-- 纵深防御：顺手收掉 anon/authenticated 的表级授权（Supabase 默认授予）
REVOKE ALL ON TABLE public.ip_pool FROM anon, authenticated;
