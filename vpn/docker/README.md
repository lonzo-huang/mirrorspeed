# MirrorSpeed VPN Server — Docker Deployment

Runs WireGuard + wstunnel WebSocket relay + management API in one container, with a separate nginx/certbot container for TLS termination.

## Architecture

```
Client ──UDP 39666──────────────────────────────► WireGuard (vpn container)
Client ──WSS 443 /secure-tunnel/──► nginx ──WS──► wstunnel:2080 ──UDP──► WireGuard
Portal ──HTTPS /vpn-api/──────────► nginx ──────► vpn-api:8443
```

The `vpn` container runs WireGuard, wstunnel, and the FastAPI management API in the **same network namespace** — required so wstunnel can forward to `127.0.0.1:39666` (WireGuard).

## Prerequisites

- A Linux VPS with Docker and Docker Compose v2
- A domain name (e.g. `vpn.example.com`) with DNS A record pointing to this server
- Ports **80**, **443** (TCP) and **39666** (UDP) open in the firewall

## Deploy

### 1. Clone the repository

```bash
git clone https://github.com/your-org/MirrorSpeed.git
cd MirrorSpeed/vpn/docker
```

### 2. Create your environment file

```bash
cp .env.example .env
```

### 3. Edit `.env`

```bash
nano .env
```

Set all four variables:

| Variable | Description |
|---|---|
| `DOMAIN` | Your VPN server domain (e.g. `vpn.example.com`) |
| `EMAIL` | Email for Let's Encrypt expiry notifications |
| `VPN_API_SECRET` | Long random secret shared with the portal (run `openssl rand -hex 32`) |
| `WG_PORT` | WireGuard UDP port (default: `39666`) |

### 4. Start the stack

```bash
docker compose up -d
```

On first start the `vpn` container will:
1. Generate WireGuard server keys
2. Write `/etc/wireguard/wg0.conf`
3. Print the **server public key** to the container log
4. Start WireGuard, wstunnel, and the management API

Certbot will automatically obtain a TLS certificate for your domain.

Check logs:
```bash
docker compose logs -f vpn
docker compose logs -f nginx
```

## Register the server in the portal

1. Copy the server public key from the vpn container logs:
   ```bash
   docker compose logs vpn | grep "server public key" -A 2
   ```
2. In the MirrorSpeed portal, go to **Admin → VPN Servers → Add Server** and enter:
   - **Domain**: your `DOMAIN` value
   - **Public Key**: the WireGuard server public key
   - **API Secret**: your `VPN_API_SECRET` value

## Peer management

The portal manages peers via the vpn-api. You can also call the API directly:

```bash
# Health check (no auth)
curl https://vpn.example.com/vpn-api/health

# List peers
curl -H "X-API-Secret: <secret>" https://vpn.example.com/vpn-api/peers

# Create a peer
curl -X POST -H "X-API-Secret: <secret>" \
     -H "Content-Type: application/json" \
     -d '{"peer_name": "alice-laptop"}' \
     https://vpn.example.com/vpn-api/peers

# Disable a peer
curl -X PATCH -H "X-API-Secret: <secret>" \
     -H "Content-Type: application/json" \
     -d '{"active": false}' \
     https://vpn.example.com/vpn-api/peers/alice-laptop/status

# Delete a peer
curl -X DELETE -H "X-API-Secret: <secret>" \
     https://vpn.example.com/vpn-api/peers/alice-laptop
```

WireGuard config and keys are persisted in the `wg-data` Docker volume and survive container restarts.

## Upgrading wstunnel

Pass a build arg to use a different wstunnel version:

```bash
docker compose build --build-arg WSTUNNEL_VERSION=v10.2.0 vpn
docker compose up -d vpn
```
