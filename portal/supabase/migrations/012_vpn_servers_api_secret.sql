-- Migration 012: Add api_secret to vpn_servers
-- The portal uses this secret to authenticate against each server's vpn-api
-- (X-API-Secret header). Never exposed to clients.

ALTER TABLE vpn_servers
  ADD COLUMN IF NOT EXISTS api_secret TEXT DEFAULT NULL;

COMMENT ON COLUMN vpn_servers.api_secret IS
  'Shared secret for portal → vpn-api authentication (X-API-Secret header). '
  'Must match VPN_API_SECRET env var on the server. '
  'NULL = provisioning disabled for this server.';
