"""
MirrorSpeed VPN Management API — AmneziaWG (bare-metal) edition
Runs on the VPN server directly (not in Docker).

Endpoints:
  GET  /health                      — no auth
  GET  /stats                       — auth required
  GET  /peers                       — auth required
  POST /peers                       — auth required, body: {peer_name: str}
  DELETE /peers/{peer_name}         — auth required
  PATCH /peers/{peer_name}/status   — auth required, body: {active: bool}

Auth: X-API-Secret header

Differences vs docker/vpn/main.py:
  - Uses `awg` / `awg-quick` commands instead of `wg` / `wg-quick`
  - Config lives at /etc/amnezia/amneziawg/awg0.conf (not /etc/wireguard/wg0.conf)
  - Default interface name is awg0
"""

import os
import re
import subprocess
import time
import threading
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import psutil
from fastapi import FastAPI, HTTPException, Security, status
from fastapi.security import APIKeyHeader
from pydantic import BaseModel, Field

app = FastAPI(title="MirrorSpeed VPN API", docs_url=None, redoc_url=None)

# ── Auth ──────────────────────────────────────────────────────────────────
API_SECRET = os.getenv("VPN_API_SECRET", "")
api_key_header = APIKeyHeader(name="X-API-Secret", auto_error=True)


def verify_api_key(key: str = Security(api_key_header)) -> str:
    if not API_SECRET or key != API_SECRET:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Invalid API secret")
    return key


# ── Constants ─────────────────────────────────────────────────────────────
WG_IFACE = os.getenv("WG_INTERFACE", "awg0")
# AmneziaWG keys/meta live in /etc/wireguard; conf lives in /etc/amnezia/amneziawg/
WG_DIR = Path("/etc/wireguard")
AWG_CONF_DIR = Path("/etc/amnezia/amneziawg")
WG_CONF = AWG_CONF_DIR / f"{WG_IFACE}.conf"
WG_SUBNET_PREFIX = "10.200.0."  # .1 is server; peers get .2 – .254

_conf_lock = threading.Lock()

# ── Bandwidth sampler ─────────────────────────────────────────────────────
# Detect WAN interface (the one with the default route)
def _detect_wan_if() -> str:
    try:
        result = subprocess.run(
            ["ip", "-4", "route", "ls"],
            capture_output=True, text=True, check=False
        )
        for line in result.stdout.splitlines():
            parts = line.split()
            if parts and parts[0] == "default":
                idx = parts.index("dev") + 1 if "dev" in parts else -1
                if idx > 0:
                    return parts[idx]
    except Exception:
        pass
    return "eth0"


_wan_if = _detect_wan_if()
_bw_lock = threading.Lock()
_bw_prev = psutil.net_io_counters(pernic=True).get(_wan_if)
_bw_prev_ts = time.monotonic()
_bw_mbps_tx = 0.0
_bw_mbps_rx = 0.0


def _bw_sampler():
    global _bw_prev, _bw_prev_ts, _bw_mbps_tx, _bw_mbps_rx
    while True:
        time.sleep(5)
        cur = psutil.net_io_counters(pernic=True).get(_wan_if)
        now = time.monotonic()
        if cur and _bw_prev:
            dt = now - _bw_prev_ts
            if dt > 0:
                tx = (cur.bytes_sent - _bw_prev.bytes_sent) * 8 / dt / 1e6
                rx = (cur.bytes_recv - _bw_prev.bytes_recv) * 8 / dt / 1e6
                with _bw_lock:
                    _bw_mbps_tx = max(0.0, tx)
                    _bw_mbps_rx = max(0.0, rx)
        _bw_prev = cur
        _bw_prev_ts = now


threading.Thread(target=_bw_sampler, daemon=True).start()


# ── Config helpers ────────────────────────────────────────────────────────

def parse_peers_from_conf() -> list[dict]:
    """
    Parse [Peer] sections from awg0.conf.
    Each peer block may be preceded by a comment: # Peer: <name> | IP: ...
    Also handles: # Name = <peer_name> style comments.
    Returns list of dicts with keys: name, public_key, preshared_key, allowed_ips
    """
    if not WG_CONF.exists():
        return []

    text = WG_CONF.read_text()
    # Split on [Peer] boundaries; first chunk is [Interface]
    raw_blocks = re.split(r"(?=\[Peer\])", text)

    peers = []
    for block in raw_blocks:
        if not block.strip().startswith("[Peer]"):
            continue

        name = ""
        public_key = ""
        preshared_key = ""
        allowed_ips = ""

        for line in block.splitlines():
            line = line.strip()
            # 06-peer-manager.sh writes: # Peer: <name> | IP: ...
            m = re.match(r"^#\s*Peer:\s*(\S+)", line)
            if m:
                name = m.group(1).strip()
                continue
            # docker/vpn/main.py writes: # Name = foo
            m2 = re.match(r"^#\s*Name\s*=\s*(.+)$", line)
            if m2:
                name = m2.group(1).strip()
                continue
            if line.startswith("PublicKey"):
                public_key = line.split("=", 1)[1].strip()
            elif line.startswith("PresharedKey"):
                preshared_key = line.split("=", 1)[1].strip()
            elif line.startswith("AllowedIPs"):
                allowed_ips = line.split("=", 1)[1].strip()

        if public_key:
            peers.append({
                "name": name,
                "public_key": public_key,
                "preshared_key": preshared_key,
                "allowed_ips": allowed_ips,
            })

    return peers


def get_live_stats() -> dict[str, dict]:
    """
    Run `awg show awg0 dump` and return dict keyed by public_key with runtime stats.
    Output columns: public_key, preshared_key, endpoint, allowed_ips,
                    last_handshake, rx_bytes, tx_bytes, keepalive
    """
    result = subprocess.run(
        ["awg", "show", WG_IFACE, "dump"],
        capture_output=True, text=True, check=False
    )
    stats = {}
    if result.returncode != 0:
        return stats

    lines = result.stdout.strip().splitlines()
    for line in lines[1:]:  # skip interface line
        parts = line.split("\t")
        if len(parts) < 8:
            continue
        pub_key, _psk, endpoint, allowed_ips, last_hs, rx, tx, _keepalive = parts[:8]
        stats[pub_key] = {
            "endpoint": endpoint if endpoint != "(none)" else None,
            "allowed_ips": allowed_ips,
            "last_handshake": (
                # 输出 UTC（带时区），避免下游(浏览器/Portal)按本地时区误解析成"未来时间"
                datetime.fromtimestamp(int(last_hs), tz=timezone.utc).isoformat()
                if last_hs != "0" else None
            ),
            "rx_bytes": int(rx),
            "tx_bytes": int(tx),
        }
    return stats


def next_vpn_ip() -> str:
    """Find the next free IP in 10.200.0.X (skip .0, .1, .255)."""
    peers = parse_peers_from_conf()
    used_ips: set[str] = set()
    for p in peers:
        # AllowedIPs may be "10.200.0.X/32" or "0.0.0.0/32" (disabled)
        for cidr in p["allowed_ips"].split(","):
            cidr = cidr.strip()
            if cidr.startswith(WG_SUBNET_PREFIX):
                ip = cidr.split("/")[0]
                used_ips.add(ip)

    for i in range(2, 255):
        candidate = f"{WG_SUBNET_PREFIX}{i}"
        if candidate not in used_ips:
            return candidate

    raise HTTPException(status_code=507, detail="No free VPN IPs available in subnet")


def syncconf():
    """Hot-reload AmneziaWG config without dropping existing peers."""
    result = subprocess.run(
        ["bash", "-c", f"awg syncconf {WG_IFACE} <(awg-quick strip {WG_IFACE})"],
        capture_output=True, text=True, check=False
    )
    if result.returncode != 0:
        raise HTTPException(
            status_code=500,
            detail=f"awg syncconf failed: {result.stderr.strip()}"
        )


def append_peer_to_conf(name: str, public_key: str, preshared_key: str, vpn_ip: str):
    """Append a new [Peer] block to awg0.conf."""
    block = (
        f"\n# Name = {name}\n"
        f"[Peer]\n"
        f"PublicKey    = {public_key}\n"
        f"PresharedKey = {preshared_key}\n"
        f"AllowedIPs   = {vpn_ip}/32\n"
    )
    with open(WG_CONF, "a") as f:
        f.write(block)


def remove_peer_from_conf(public_key: str) -> bool:
    """
    Remove the [Peer] block matching public_key from awg0.conf.
    Returns True if a block was found and removed.
    """
    text = WG_CONF.read_text()
    # Split preserving [Peer] headers
    blocks = re.split(r"(?=\[Peer\])", text)

    new_blocks = []
    removed = False
    for block in blocks:
        if block.strip().startswith("[Peer]") and f"PublicKey    = {public_key}" in block:
            # Also match with varying spacing
            if re.search(r"PublicKey\s*=\s*" + re.escape(public_key), block):
                removed = True
                continue
        new_blocks.append(block)

    if removed:
        WG_CONF.write_text("".join(new_blocks))

    return removed


def validate_peer_name(name: str):
    if not re.fullmatch(r"[a-zA-Z0-9_-]{1,64}", name):
        raise HTTPException(status_code=400, detail=f"Invalid peer name: {name!r}")


def count_active_peers() -> int:
    """Count peers with a handshake in the last 5 minutes."""
    stats = get_live_stats()
    now_ts = time.time()
    active = 0
    for info in stats.values():
        hs = info.get("last_handshake")
        if hs:
            try:
                hs_ts = datetime.fromisoformat(hs).timestamp()
                if now_ts - hs_ts < 300:
                    active += 1
            except Exception:
                pass
    return active


# ── Models ────────────────────────────────────────────────────────────────

class CreatePeerRequest(BaseModel):
    peer_name: str = Field(..., min_length=1, max_length=64)


class PeerResponse(BaseModel):
    peer_name: str
    public_key: str
    private_key: str
    preshared_key: str
    vpn_ip: str


class PeerStatusResponse(BaseModel):
    peer_name: str
    public_key: str
    vpn_ip: str
    active: bool
    last_handshake: Optional[str]
    tx_bytes: int
    rx_bytes: int
    endpoint: Optional[str] = None   # 客户端来源：真实公网IP=直连(快速)；127.0.0.1=wstunnel(强力)


class SetActiveRequest(BaseModel):
    active: bool


class ServerStats(BaseModel):
    status: str           # 'online' | 'degraded'
    active_peers: int
    total_peers: int
    cpu_percent: float
    mem_percent: float
    bw_tx_mbps: float
    bw_rx_mbps: float
    load_1m: float
    uptime_seconds: int
    timestamp: str


# ── On-demand provisioning（按需建 peer）──────────────────────────────────────
# 设备自带密钥对 + 全局唯一 IP（由 Portal 集中分配），服务器只需"接受"该公钥。
class EnsurePeerRequest(BaseModel):
    public_key:    str = Field(..., min_length=40, max_length=64)
    vpn_ip:        str = Field(..., min_length=7,  max_length=18)  # 10.200.x.y[/32]
    peer_name:     str = Field("",  max_length=64)
    preshared_key: str = Field("",  max_length=64)


class RemovePeerRequest(BaseModel):
    public_key: str = Field(..., min_length=40, max_length=64)


# ── Endpoints ─────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    """Lightweight health check — no auth required."""
    awg = subprocess.run(["awg", "show", WG_IFACE], capture_output=True, check=False)
    return {
        "status": "ok" if awg.returncode == 0 else "degraded",
        "wg_status": "up" if awg.returncode == 0 else "down",
        "timestamp": datetime.utcnow().isoformat() + "Z",
    }


@app.get("/stats", response_model=ServerStats)
def get_stats(_key: str = Security(verify_api_key)):
    """Server stats snapshot for portal dashboard."""
    try:
        cpu = psutil.cpu_percent(interval=1)
        mem = psutil.virtual_memory().percent
        load = psutil.getloadavg()[0]
        uptime = int(time.time() - psutil.boot_time())

        with _bw_lock:
            tx_mbps = _bw_mbps_tx
            rx_mbps = _bw_mbps_rx

        with _conf_lock:
            peers = parse_peers_from_conf()
            total_peers = len(peers)

        active_peers = count_active_peers()

        cpu_count = psutil.cpu_count() or 1
        srv_status = "degraded" if (cpu > 90 or load > cpu_count * 2) else "online"

        return ServerStats(
            status=srv_status,
            active_peers=active_peers,
            total_peers=total_peers,
            cpu_percent=round(cpu, 1),
            mem_percent=round(mem, 1),
            bw_tx_mbps=round(tx_mbps, 2),
            bw_rx_mbps=round(rx_mbps, 2),
            load_1m=round(load, 2),
            uptime_seconds=uptime,
            timestamp=datetime.utcnow().isoformat() + "Z",
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/peers", response_model=list[PeerStatusResponse])
def list_peers(_key: str = Security(verify_api_key)):
    """List all configured peers with live AmneziaWG stats."""
    with _conf_lock:
        peers = parse_peers_from_conf()

    live = get_live_stats()
    result = []

    for p in peers:
        runtime = live.get(p["public_key"], {})
        allowed = p["allowed_ips"]
        # A peer is "active" if its AllowedIPs is not the block sentinel 0.0.0.0/32
        is_active = not allowed.startswith("0.0.0.0")
        # Normalise vpn_ip: prefer the 10.200.0.x address from AllowedIPs
        vpn_ip = allowed
        for cidr in allowed.split(","):
            cidr = cidr.strip()
            if cidr.startswith(WG_SUBNET_PREFIX):
                vpn_ip = cidr
                break

        result.append(PeerStatusResponse(
            peer_name=p["name"] or p["public_key"][:12],
            public_key=p["public_key"],
            vpn_ip=vpn_ip,
            active=is_active,
            last_handshake=runtime.get("last_handshake"),
            rx_bytes=runtime.get("rx_bytes", 0),
            tx_bytes=runtime.get("tx_bytes", 0),
            endpoint=runtime.get("endpoint"),
        ))

    return result


@app.post("/peers", response_model=PeerResponse, status_code=201)
def create_peer(req: CreatePeerRequest, _key: str = Security(verify_api_key)):
    """Create a new AmneziaWG peer and return its keys + VPN IP."""
    validate_peer_name(req.peer_name)

    with _conf_lock:
        # Check for duplicate name
        existing = parse_peers_from_conf()
        for p in existing:
            if p["name"] == req.peer_name:
                raise HTTPException(
                    status_code=409,
                    detail=f"Peer {req.peer_name!r} already exists"
                )

        # Generate keys using awg
        private_key = subprocess.run(
            ["awg", "genkey"], capture_output=True, text=True, check=True
        ).stdout.strip()

        public_key = subprocess.run(
            ["awg", "pubkey"], input=private_key,
            capture_output=True, text=True, check=True
        ).stdout.strip()

        preshared_key = subprocess.run(
            ["awg", "genpsk"], capture_output=True, text=True, check=True
        ).stdout.strip()

        vpn_ip = next_vpn_ip()

        append_peer_to_conf(
            name=req.peer_name,
            public_key=public_key,
            preshared_key=preshared_key,
            vpn_ip=vpn_ip,
        )
        syncconf()

    return PeerResponse(
        peer_name=req.peer_name,
        public_key=public_key,
        private_key=private_key,
        preshared_key=preshared_key,
        vpn_ip=f"{vpn_ip}/32",
    )


@app.post("/peers/ensure", status_code=200)
def ensure_peer(req: EnsurePeerRequest, _key: str = Security(verify_api_key)):
    """
    幂等地确保某设备在本机有 peer（On-demand provisioning 快路径）。
    设备自带密钥对/IP，本接口**不生成密钥**，只把公钥+IP 加进 awg0.conf。
    已存在则直接返回。客户端连接前 / 节点列表预热时调用。
    """
    ip = req.vpn_ip.split("/")[0]
    if not re.fullmatch(r"10\.200\.\d{1,3}\.\d{1,3}", ip):
        raise HTTPException(status_code=400, detail=f"Invalid vpn_ip: {req.vpn_ip!r}")

    with _conf_lock:
        for p in parse_peers_from_conf():
            if p["public_key"] == req.public_key:
                return {"status": "exists", "vpn_ip": f"{ip}/32"}

        name = req.peer_name or f"ms-{req.public_key[:12]}"
        block = f"\n# Name = {name}\n[Peer]\nPublicKey    = {req.public_key}\n"
        if req.preshared_key:
            block += f"PresharedKey = {req.preshared_key}\n"
        block += f"AllowedIPs   = {ip}/32\n"
        with open(WG_CONF, "a") as f:
            f.write(block)
        syncconf()

    return {"status": "created", "vpn_ip": f"{ip}/32"}


@app.post("/peers/remove", status_code=200)
def remove_peer_by_key(req: RemovePeerRequest, _key: str = Security(verify_api_key)):
    """按公钥移除 peer（闲置回收 GC 用）。幂等：不存在也返回 200。"""
    with _conf_lock:
        removed = remove_peer_from_conf(req.public_key)
        if removed:
            syncconf()
    return {"status": "removed" if removed else "absent"}


@app.delete("/peers/{peer_name}", status_code=204)
def delete_peer(peer_name: str, _key: str = Security(verify_api_key)):
    """Remove a peer from AmneziaWG config and hot-reload."""
    validate_peer_name(peer_name)

    with _conf_lock:
        peers = parse_peers_from_conf()
        target = next((p for p in peers if p["name"] == peer_name), None)
        if target is None:
            raise HTTPException(status_code=404, detail=f"Peer {peer_name!r} not found")

        removed = remove_peer_from_conf(target["public_key"])
        if not removed:
            raise HTTPException(status_code=500, detail="Failed to remove peer from config")

        syncconf()


@app.patch("/peers/{peer_name}/status", status_code=204)
def set_peer_status(peer_name: str, req: SetActiveRequest, _key: str = Security(verify_api_key)):
    """
    Enable or disable a peer.
    - active=False: set AllowedIPs to 0.0.0.0/32 (blocks all traffic routing)
    - active=True:  restore AllowedIPs to original vpn_ip/32
    """
    validate_peer_name(peer_name)

    with _conf_lock:
        peers = parse_peers_from_conf()
        target = next((p for p in peers if p["name"] == peer_name), None)
        if target is None:
            raise HTTPException(status_code=404, detail=f"Peer {peer_name!r} not found")

        pub_key = target["public_key"]
        current_allowed = target["allowed_ips"]

        if req.active:
            # Restore original VPN IP — find it from the awg0.conf comment block if blocked
            # The original IP was stored; if currently 0.0.0.0/32, we need to recover it.
            # We store it as a comment "# OrigIP = x.x.x.x" when disabling.
            text = WG_CONF.read_text()
            # Try to find OrigIP comment in the peer block
            orig_ip = None
            blocks = re.split(r"(?=\[Peer\])", text)
            for block in blocks:
                if re.search(r"PublicKey\s*=\s*" + re.escape(pub_key), block):
                    m = re.search(r"#\s*OrigIP\s*=\s*([\d.]+)", block)
                    if m:
                        orig_ip = m.group(1)
                    break

            if orig_ip is None:
                # Already active or OrigIP not recorded — nothing to restore
                if not current_allowed.startswith("0.0.0.0"):
                    return  # already active
                raise HTTPException(
                    status_code=409,
                    detail="Cannot restore: original IP not recorded. Delete and recreate the peer."
                )

            # Replace AllowedIPs and remove OrigIP comment in the block
            new_text = re.sub(
                r"(# Name = " + re.escape(peer_name) + r"\n\[Peer\].*?AllowedIPs\s*=\s*)[\d./]+",
                lambda m: m.group(1) + f"{orig_ip}/32",
                text,
                flags=re.DOTALL,
            )
            new_text = re.sub(r"# OrigIP = [\d.]+\n", "", new_text)
            WG_CONF.write_text(new_text)

        else:
            # Disable: record original IP as comment, set AllowedIPs to 0.0.0.0/32
            if current_allowed.startswith("0.0.0.0"):
                return  # already disabled

            # Extract the actual VPN IP
            orig_ip = None
            for cidr in current_allowed.split(","):
                cidr = cidr.strip()
                if cidr.startswith(WG_SUBNET_PREFIX):
                    orig_ip = cidr.split("/")[0]
                    break

            if orig_ip is None:
                raise HTTPException(status_code=500, detail="Cannot determine peer VPN IP")

            text = WG_CONF.read_text()
            # Insert OrigIP comment and update AllowedIPs
            new_text = re.sub(
                r"(# Name = " + re.escape(peer_name) + r"\n)",
                lambda m: m.group(1) + f"# OrigIP = {orig_ip}\n",
                text,
            )
            new_text = re.sub(
                r"(# Name = " + re.escape(peer_name) + r"\n(?:# OrigIP = [\d.]+\n)?\[Peer\].*?AllowedIPs\s*=\s*)[\d./]+",
                lambda m: m.group(1) + "0.0.0.0/32",
                new_text,
                flags=re.DOTALL,
            )
            WG_CONF.write_text(new_text)

        syncconf()
