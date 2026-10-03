-- sing-box 迁移 · 阶段 1 基础设施(加列,不动现有 AWG/数据)
-- 对应 docs/singbox-migration.md。可安全重复执行(IF NOT EXISTS)。
-- 本期只做 快速(hy2)+ 强力(reality);超级(CF-ws)仅预留列,阶段 2 再用。

-- ── 节点级:sing-box 服务端参数(每台节点一行,全用户共享)─────────────
alter table public.vpn_servers
  add column if not exists sb_enabled  boolean not null default false,  -- 该节点是否已部署 sing-box(客户端据此决定走 sing-box 还是回退 AWG;也是回滚开关)
  -- 强力:VLESS + Reality(TCP 443)
  add column if not exists reality_pbk text,                 -- Reality 服务端公钥(客户端 pbk)
  add column if not exists reality_sid text,                 -- Reality short_id
  add column if not exists reality_sni text,                 -- 伪装 SNI;为空 → 客户端用默认 www.microsoft.com
  add column if not exists reality_port integer default 443, -- Reality 监听端口(默认 443)
  -- 快速:Hysteria2(UDP,端口跳跃 30000-49999 DNAT 到此端口)
  add column if not exists hy2_port    integer,              -- hy2 服务端固定监听 UDP 端口
  add column if not exists hy2_obfs    text,                 -- hy2 salamander obfs 密码(节点级)
  add column if not exists hy2_hop_min integer default 30000,
  add column if not exists hy2_hop_max integer default 49999,
  -- 超级:VLESS + WS + TLS(经 Cloudflare)—— 阶段 2 才用,本期留空
  add column if not exists ws_path     text,                 -- ws 路径
  add column if not exists cf_host     text;                 -- 经 CF 的连接域名(为空=该节点不提供超级层)

comment on column public.vpn_servers.sb_enabled is 'sing-box 已部署并可用;客户端据此选 sing-box/AWG,置 false 即回滚到 AWG(无需发版)';
comment on column public.vpn_servers.reality_sni is '伪装 SNI,空则客户端用默认 www.microsoft.com';

-- ── 用户级:每设备在每节点的 sing-box 凭证(与现 vpn_device_peers 同维度)──
-- 复用现有表:加 UUID(vless reality/ws 共用)+ hy2 密码。
alter table public.vpn_device_peers
  add column if not exists sb_uuid       text,  -- VLESS UUID(reality 与 ws 共用)
  add column if not exists hy2_password  text;  -- Hysteria2 用户密码

-- 说明:
--  * AWG 相关列(awg_*, public_key, private_key_enc, vpn_ip)全部保留,双栈期并行。
--  * sunset(~2026-12-03)后再单独写 migration 删除 awg_* 与 sing-box 未用到的旧列。
