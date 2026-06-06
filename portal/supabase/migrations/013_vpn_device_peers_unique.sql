-- Migration 013: enforce one active peer per (device, server)
--
-- Provisioning happens from two paths (/api/mobile/device and
-- /api/mobile/configs). Without a DB constraint, concurrent requests could each
-- create a peer for the same device+server, producing duplicates (observed in
-- testing: many redundant peers, some sharing a VPN IP). This partial unique
-- index makes the second concurrent insert fail with 23505, which both code
-- paths catch and treat as "already exists" (reuse the existing peer).
--
-- Partial (WHERE is_active) so historical deactivated peers don't block
-- re-provisioning a fresh active one for the same device+server.
--
-- NOTE: run after clearing existing duplicates, otherwise index creation fails.

CREATE UNIQUE INDEX IF NOT EXISTS vpn_device_peers_active_device_server_uniq
  ON vpn_device_peers (device_id, server_id)
  WHERE is_active;
