-- sing-box 迁移 · 修正:设备级凭证 + 节点 AWG 开关
-- 可安全重复执行。补在 20261003 之后。

-- 设备级 sing-box 凭证(按设备全局,所有 sing-box 节点共用一套,类比 WG 密钥)
alter table public.vpn_devices
  add column if not exists sb_uuid          text,   -- VLESS UUID(reality/ws 共用)
  add column if not exists hy2_password_enc text;   -- Hysteria2 密码(加密存,同 WG 私钥做法)

-- 节点是否仍提供 AWG(存量节点=true;纯 sing-box 新节点如 us02=false)
-- 用于 configs:awg_enabled=false 的节点不给老客户端下发 wg_conf(否则老客户端连不上)。
alter table public.vpn_servers
  add column if not exists awg_enabled boolean not null default true;

comment on column public.vpn_servers.awg_enabled is '是否提供 AmneziaWG;纯 sing-box 节点置 false，configs 不给老客户端发 wg_conf';

-- 说明:20261003 曾在 vpn_device_peers 加过 sb_uuid/hy2_password(按设备+节点),
-- 现改为设备级全局(更简单、与 WG 密钥模型一致)。vpn_device_peers 上那两列留着不用，
-- 无害;如需清理可后续单独 drop。
