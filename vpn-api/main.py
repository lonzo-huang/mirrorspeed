"""
VPN 服务器管理 API（多服务器版）
部署在每台 VPN 服务器上，供 Next.js portal 统一调用

依赖安装：
  pip install fastapi uvicorn[standard] python-dotenv psutil

启动（开发）：
  uvicorn main:app --host 127.0.0.1 --port 8443

启动（生产，使用 Let's Encrypt 证书）：
  uvicorn main:app --host 0.0.0.0 --port 8443 \
    --ssl-keyfile /etc/letsencrypt/live/hk01.vpn.example.com/privkey.pem \
    --ssl-certfile /etc/letsencrypt/live/hk01.vpn.example.com/fullchain.pem
"""

import subprocess
import re
import os
import time
import threading
from datetime import datetime
from pathlib import Path
from typing import Optional

import psutil
from fastapi import FastAPI, HTTPException, Security, status
from fastapi.security import APIKeyHeader
from pydantic import BaseModel, Field
from dotenv import load_dotenv

load_dotenv()

app = FastAPI(title="Enterprise VPN Management API", docs_url=None, redoc_url=None)

# ── API Key 鉴权 ─────────────────────────────────────────────────────────
API_SECRET     = os.getenv("VPN_API_SECRET", "")
api_key_header = APIKeyHeader(name="X-API-Secret", auto_error=True)

def verify_api_key(key: str = Security(api_key_header)) -> str:
    if not API_SECRET or key != API_SECRET:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Invalid API secret")
    return key

# ── 常量 ─────────────────────────────────────────────────────────────────
PEER_MANAGER = Path("/opt/mirrorspeed/06-peer-manager.sh")
WG_DIR       = Path("/etc/wireguard")
WG_IFACE     = os.getenv("WG_INTERFACE", "wg0")
PEERS_DIR    = WG_DIR / "peers"
WAN_IF_FILE  = WG_DIR / ".wan-interface"
WAN_IF       = WAN_IF_FILE.read_text().strip() if WAN_IF_FILE.exists() else "eth0"

# ── 带宽采样（后台线程，每 5 秒刷新一次）───────────────────────────────
_bw_lock     = threading.Lock()
_bw_prev     = psutil.net_io_counters(pernic=True).get(WAN_IF)
_bw_prev_ts  = time.monotonic()
_bw_mbps_tx  = 0.0
_bw_mbps_rx  = 0.0

def _bw_sampler():
    global _bw_prev, _bw_prev_ts, _bw_mbps_tx, _bw_mbps_rx
    while True:
        time.sleep(5)
        cur = psutil.net_io_counters(pernic=True).get(WAN_IF)
        now = time.monotonic()
        if cur and _bw_prev:
            dt = now - _bw_prev_ts
            tx = (cur.bytes_sent - _bw_prev.bytes_sent) * 8 / dt / 1e6  # Mbps
            rx = (cur.bytes_recv - _bw_prev.bytes_recv) * 8 / dt / 1e6
            with _bw_lock:
                _bw_mbps_tx = max(0.0, tx)
                _bw_mbps_rx = max(0.0, rx)
        _bw_prev    = cur
        _bw_prev_ts = now

threading.Thread(target=_bw_sampler, daemon=True).start()

# ── 辅助函数 ─────────────────────────────────────────────────────────────

def run(cmd: list[str], check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, check=check)

def validate_peer_name(name: str) -> None:
    if not re.fullmatch(r"[a-zA-Z0-9_-]{1,64}", name):
        raise HTTPException(status_code=400, detail=f"Invalid peer name: {name!r}")

def read_peer_meta(peer_name: str) -> dict:
    meta_file = PEERS_DIR / f"{peer_name}.meta"
    if not meta_file.exists():
        return {}
    meta = {}
    for line in meta_file.read_text().splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            meta[k.strip()] = v.strip()
    return meta

def get_wg_peers_runtime() -> dict[str, dict]:
    """wg show wg0 dump → {public_key: {endpoint, last_handshake, rx, tx}}"""
    result = run(["wg", "show", WG_IFACE, "dump"], check=False)
    peers  = {}
    if result.returncode != 0:
        return peers
    lines = result.stdout.strip().splitlines()
    for line in lines[1:]:   # 跳过 interface 行
        parts = line.split("\t")
        if len(parts) < 8:
            continue
        pub, _, endpoint, allowed_ips, last_hs, rx, tx, _ = parts[:8]
        peers[pub] = {
            "endpoint":       endpoint if endpoint != "(none)" else None,
            "allowed_ips":    allowed_ips,
            "last_handshake": datetime.fromtimestamp(int(last_hs)).isoformat() if last_hs != "0" else None,
            "rx_bytes":       int(rx),
            "tx_bytes":       int(tx),
        }
    return peers

def count_active_peers() -> int:
    """统计最近 5 分钟有握手的活跃 Peer 数"""
    runtime = get_wg_peers_runtime()
    now_ts  = time.time()
    active  = 0
    for info in runtime.values():
        hs = info.get("last_handshake")
        if hs:
            try:
                hs_ts = datetime.fromisoformat(hs).timestamp()
                if now_ts - hs_ts < 300:   # 5 分钟内
                    active += 1
            except Exception:
                pass
    return active

# ── 模型 ─────────────────────────────────────────────────────────────────

class CreatePeerRequest(BaseModel):
    peer_name: str = Field(..., min_length=1, max_length=64)

class PeerResponse(BaseModel):
    peer_name:     str
    public_key:    str
    private_key:   str
    preshared_key: str
    vpn_ip:        str

class PeerStatusResponse(BaseModel):
    peer_name:      str
    public_key:     str
    vpn_ip:         str
    last_handshake: Optional[str]
    tx_bytes:       int
    rx_bytes:       int

class SetActiveRequest(BaseModel):
    active: bool

class ServerStats(BaseModel):
    """服务器状态快照，供 portal 缓存并展示给用户"""
    status:         str            # 'online' | 'degraded' | 'offline'
    active_peers:   int            # 5 分钟内有握手的 Peer 数
    total_peers:    int            # 配置文件中的总 Peer 数
    cpu_percent:    float          # 1 分钟平均 CPU 利用率
    mem_percent:    float          # 内存占用百分比
    bw_tx_mbps:     float          # 出站带宽 Mbps（5 秒平均）
    bw_rx_mbps:     float          # 入站带宽 Mbps（5 秒平均）
    load_1m:        float          # 系统 load average (1min)
    uptime_seconds: int
    timestamp:      str

# ── API 端点 ─────────────────────────────────────────────────────────────

@app.get("/stats", response_model=ServerStats)
def get_stats(_key: str = Security(verify_api_key)):
    """
    返回服务器实时状态。
    portal 的 cron job 每分钟调用一次，将结果缓存到 Supabase，
    前端从 Supabase 读取以减少对 VPN 服务器的直接请求。
    """
    try:
        cpu    = psutil.cpu_percent(interval=1)
        mem    = psutil.virtual_memory().percent
        load   = psutil.getloadavg()[0]          # 1 分钟 load average
        uptime = int(time.time() - psutil.boot_time())

        with _bw_lock:
            tx_mbps = _bw_mbps_tx
            rx_mbps = _bw_mbps_rx

        active_peers = count_active_peers()
        total_peers  = len(list(PEERS_DIR.glob("*.meta")))

        # 状态判断：CPU > 90% 或 load > CPU 核数 × 2 则 degraded
        cpu_count = psutil.cpu_count() or 1
        if cpu > 90 or load > cpu_count * 2:
            srv_status = "degraded"
        else:
            srv_status = "online"

        return ServerStats(
            status=         srv_status,
            active_peers=   active_peers,
            total_peers=    total_peers,
            cpu_percent=    round(cpu, 1),
            mem_percent=    round(mem, 1),
            bw_tx_mbps=     round(tx_mbps, 2),
            bw_rx_mbps=     round(rx_mbps, 2),
            load_1m=        round(load, 2),
            uptime_seconds= uptime,
            timestamp=      datetime.utcnow().isoformat() + "Z",
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/health")
def health():
    """轻量健康检查，不需要 API Key，供负载均衡器和延迟探测使用"""
    wg = run(["wg", "show", WG_IFACE], check=False)
    return {
        "status":    "ok" if wg.returncode == 0 else "degraded",
        "wg_status": "up" if wg.returncode == 0 else "down",
        "timestamp": datetime.utcnow().isoformat() + "Z",
    }


@app.post("/peers", response_model=PeerResponse, status_code=201)
def create_peer(req: CreatePeerRequest, _key: str = Security(verify_api_key)):
    validate_peer_name(req.peer_name)

    if (PEERS_DIR / f"{req.peer_name}.meta").exists():
        raise HTTPException(status_code=409, detail=f"Peer {req.peer_name!r} already exists")

    result = run(["bash", str(PEER_MANAGER), "add", req.peer_name], check=False)
    if result.returncode != 0:
        raise HTTPException(status_code=500, detail=f"Peer creation failed: {result.stderr}")

    private_key_file   = PEERS_DIR / f"{req.peer_name}.private"
    preshared_key_file = PEERS_DIR / f"{req.peer_name}.psk"
    meta               = read_peer_meta(req.peer_name)

    if not private_key_file.exists():
        raise HTTPException(status_code=500, detail="Key files not found after creation")

    private_key   = private_key_file.read_text().strip()
    preshared_key = preshared_key_file.read_text().strip()

    # 从 meta 读取 public key
    public_key = meta.get("client_public", "")

    return PeerResponse(
        peer_name=     req.peer_name,
        public_key=    public_key,
        private_key=   private_key,
        preshared_key= preshared_key,
        vpn_ip=        meta.get("client_ip", "") + "/32",
    )


@app.delete("/peers/{peer_name}", status_code=204)
def delete_peer(peer_name: str, _key: str = Security(verify_api_key)):
    validate_peer_name(peer_name)

    if not (PEERS_DIR / f"{peer_name}.meta").exists():
        raise HTTPException(status_code=404, detail=f"Peer {peer_name!r} not found")

    result = run(["bash", str(PEER_MANAGER), "remove", peer_name], check=False)
    if result.returncode != 0:
        raise HTTPException(status_code=500, detail=f"Peer removal failed: {result.stderr}")


@app.get("/peers", response_model=list[PeerStatusResponse])
def list_peers(_key: str = Security(verify_api_key)):
    wg_status = get_wg_peers_runtime()
    peers     = []

    for meta_file in sorted(PEERS_DIR.glob("*.meta")):
        meta = {}
        for line in meta_file.read_text().splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                meta[k.strip()] = v.strip()

        pub_key = meta.get("client_public", "")
        runtime = wg_status.get(pub_key, {})

        peers.append(PeerStatusResponse(
            peer_name=      meta.get("name", meta_file.stem),
            public_key=     pub_key,
            vpn_ip=         meta.get("client_ip", "") + "/32",
            last_handshake= runtime.get("last_handshake"),
            rx_bytes=       runtime.get("rx_bytes", 0),
            tx_bytes=       runtime.get("tx_bytes", 0),
        ))

    return peers


@app.patch("/peers/{peer_name}/status", status_code=204)
def set_peer_active(peer_name: str, req: SetActiveRequest, _key: str = Security(verify_api_key)):
    validate_peer_name(peer_name)
    meta = read_peer_meta(peer_name)
    if not meta:
        raise HTTPException(status_code=404, detail=f"Peer {peer_name!r} not found")

    pub_key   = meta.get("client_public", "")
    client_ip = meta.get("client_ip", "")

    if req.active:
        run(["wg", "set", WG_IFACE, "peer", pub_key, "allowed-ips", f"{client_ip}/32"])
    else:
        run(["wg", "set", WG_IFACE, "peer", pub_key, "allowed-ips", ""])
