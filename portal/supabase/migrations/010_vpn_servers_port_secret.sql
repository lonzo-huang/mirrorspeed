-- Migration 010: Add port_secret column to vpn_servers
-- This column stores the HMAC-SHA256 secret used by the client-side
-- port hopping service (PortHoppingService) to compute the current
-- hop port independently from the server.
-- NULL means port hopping is disabled for that server (use port directly).

ALTER TABLE vpn_servers
  ADD COLUMN IF NOT EXISTS port_secret TEXT DEFAULT NULL;

COMMENT ON COLUMN vpn_servers.port_secret IS
  'HMAC-SHA256 secret for client-side port hopping. '
  'NULL = disabled (connect to port directly). '
  'Must match PORT_SECRET env var on the server.';
