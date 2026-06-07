#!/bin/bash
set -euo pipefail

WG_DIR="/etc/wireguard"
WG_IFACE="wg0"
WG_PORT="${WG_PORT:-39666}"
WG_SUBNET="10.200.0.0/24"
WG_SERVER_IP="10.200.0.1"
WG_CONF="${WG_DIR}/${WG_IFACE}.conf"

# ── First-run: generate WireGuard keys and config ─────────────────────────
if [ ! -f "${WG_CONF}" ]; then
    echo "[entrypoint] First run detected — generating WireGuard configuration..."

    mkdir -p "${WG_DIR}"
    chmod 700 "${WG_DIR}"

    # Detect WAN interface
    WAN_IF=$(ip -4 route show default | awk '{print $5; exit}')
    if [ -z "${WAN_IF}" ]; then
        echo "[entrypoint] ERROR: Cannot detect WAN interface"
        exit 1
    fi
    echo "[entrypoint] Detected WAN interface: ${WAN_IF}"

    # Generate server key pair
    wg genkey | tee "${WG_DIR}/server-private.key" | wg pubkey > "${WG_DIR}/server-public.key"
    chmod 600 "${WG_DIR}/server-private.key"
    chmod 644 "${WG_DIR}/server-public.key"

    SERVER_PRIVATE=$(cat "${WG_DIR}/server-private.key")
    SERVER_PUBLIC=$(cat "${WG_DIR}/server-public.key")

    # Write wg0.conf
    cat > "${WG_CONF}" << EOF
[Interface]
Address    = ${WG_SERVER_IP}/24
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIVATE}

PostUp   = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${WAN_IF} -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ${WAN_IF} -j MASQUERADE
EOF

    chmod 600 "${WG_CONF}"

    echo ""
    echo "================================================================"
    echo " WireGuard server public key (register this in the portal):"
    echo " ${SERVER_PUBLIC}"
    echo "================================================================"
    echo ""
else
    echo "[entrypoint] Found existing WireGuard configuration, skipping key generation."
    SERVER_PUBLIC=$(cat "${WG_DIR}/server-public.key" 2>/dev/null || echo "(key file missing)")
    echo "[entrypoint] Server public key: ${SERVER_PUBLIC}"
fi

# ── Start WireGuard ────────────────────────────────────────────────────────
echo "[entrypoint] Bringing up WireGuard interface ${WG_IFACE}..."
wg-quick up "${WG_IFACE}"
echo "[entrypoint] WireGuard is up."
wg show "${WG_IFACE}"

# ── Start wstunnel in background ──────────────────────────────────────────
echo "[entrypoint] Starting wstunnel server on :2080 → 127.0.0.1:${WG_PORT}..."
wstunnel server \
    --restrict-to "127.0.0.1:${WG_PORT}" \
    ws://0.0.0.0:2080 &
WSTUNNEL_PID=$!
echo "[entrypoint] wstunnel PID: ${WSTUNNEL_PID}"

# ── Start vpn-api (uvicorn) in foreground ─────────────────────────────────
echo "[entrypoint] Starting vpn-api on :8443..."
exec /app/venv/bin/uvicorn main:app \
    --host 0.0.0.0 \
    --port 8443 \
    --log-level info
