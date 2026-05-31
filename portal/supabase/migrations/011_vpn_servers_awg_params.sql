-- Migration 011: AWG obfuscation parameters + Cloudflare Tunnel relay URL
--
-- AWG params: both client and server must share the same Jc/Jmin/Jmax/H1-H4.
-- These are stored per-server so the portal can embed them in client configs.
-- Jc=0 means standard WireGuard (obfuscation disabled).
--
-- cf_relay_url: Optional Cloudflare Tunnel URL as tertiary relay.
-- Format: "wss://xxx.cfargotunnel.com"  (no trailing slash, no path)
-- When set, client falls back to this if wstunnel on port 443 also fails.

ALTER TABLE vpn_servers
  ADD COLUMN IF NOT EXISTS awg_jc    INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS awg_jmin  INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS awg_jmax  INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS awg_s1    INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS awg_s2    INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS awg_h1    BIGINT  NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS awg_h2    BIGINT  NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS awg_h3    BIGINT  NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS awg_h4    BIGINT  NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS cf_relay_url TEXT DEFAULT NULL;

COMMENT ON COLUMN vpn_servers.awg_jc   IS 'AmneziaWG Jc (junk packet count). 0 = standard WireGuard.';
COMMENT ON COLUMN vpn_servers.awg_jmin IS 'AmneziaWG Jmin (min junk packet size bytes).';
COMMENT ON COLUMN vpn_servers.awg_jmax IS 'AmneziaWG Jmax (max junk packet size bytes).';
COMMENT ON COLUMN vpn_servers.awg_s1   IS 'AmneziaWG S1 (init packet junk size).';
COMMENT ON COLUMN vpn_servers.awg_s2   IS 'AmneziaWG S2 (response packet junk size).';
COMMENT ON COLUMN vpn_servers.awg_h1   IS 'AmneziaWG H1 magic header value.';
COMMENT ON COLUMN vpn_servers.awg_h2   IS 'AmneziaWG H2 magic header value.';
COMMENT ON COLUMN vpn_servers.awg_h3   IS 'AmneziaWG H3 magic header value.';
COMMENT ON COLUMN vpn_servers.awg_h4   IS 'AmneziaWG H4 magic header value.';
COMMENT ON COLUMN vpn_servers.cf_relay_url IS
  'Cloudflare Tunnel WebSocket base URL, e.g. wss://xxx.cfargotunnel.com. '
  'Used as tertiary relay after wstunnel-443 fails. NULL = disabled.';

-- ── Set Spain server AWG params (from: awg show awg0 on vm-spain) ────────────
-- Run after migration if the server exists; safe to re-run.
UPDATE vpn_servers
SET
  awg_jc   = 4,
  awg_jmin = 40,
  awg_jmax = 70,
  awg_s1   = 0,
  awg_s2   = 0,
  awg_h1   = 3352103504,
  awg_h2   = 3337486862,
  awg_h3   = 733779992,
  awg_h4   = 1606199382
WHERE name = 'spain01';
