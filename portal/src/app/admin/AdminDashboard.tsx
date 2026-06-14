'use client'

import { useEffect, useState, useCallback } from 'react'

interface Peer {
  public_key: string; vpn_ip: string; active: boolean; last_handshake: string | null
  online: boolean; rx_bytes: number; tx_bytes: number; device_label: string; email: string
}
interface ServerStats {
  status: string; active_peers: number; total_peers: number
  cpu_percent: number; mem_percent: number; bw_tx_mbps: number; bw_rx_mbps: number
  load_1m: number; uptime_seconds: number
}
interface ServerRow {
  id: string; name: string; display_name: string; location: string | null; flag_emoji: string | null
  endpoint: string; online: boolean; error?: string
  db_status: string | null; last_checked_at: string | null; max_peers: number | null
  stats: ServerStats | null; peers: Peer[]
}

function fmtBytes(n: number): string {
  if (!n) return '0'
  const u = ['B', 'KB', 'MB', 'GB', 'TB']; let i = 0; let v = n
  while (v >= 1024 && i < u.length - 1) { v /= 1024; i++ }
  return `${v.toFixed(v < 10 && i > 0 ? 1 : 0)} ${u[i]}`
}
function fmtAgo(iso: string | null): string {
  if (!iso) return '—'
  const s = Math.floor((Date.now() - Date.parse(iso)) / 1000)
  if (Number.isNaN(s)) return '—'
  if (s < 60) return `${s}s 前`
  if (s < 3600) return `${Math.floor(s / 60)}m 前`
  if (s < 86400) return `${Math.floor(s / 3600)}h 前`
  return `${Math.floor(s / 86400)}d 前`
}
function fmtUptime(s: number): string {
  const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600)
  return d > 0 ? `${d}d ${h}h` : `${h}h ${Math.floor((s % 3600) / 60)}m`
}

export default function AdminDashboard() {
  const [servers, setServers] = useState<ServerRow[]>([])
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState<string | null>(null)
  const [fetchedAt, setFetchedAt] = useState<string>('')

  const load = useCallback(async () => {
    setErr(null)
    try {
      const res = await fetch('/api/admin/servers-overview', { cache: 'no-store' })
      if (!res.ok) { setErr(`HTTP ${res.status}`); setLoading(false); return }
      const data = await res.json()
      setServers(data.servers ?? [])
      setFetchedAt(new Date().toLocaleTimeString())
    } catch (e: any) {
      setErr(String(e?.message ?? e))
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    load()
    const t = setInterval(load, 30_000)
    return () => clearInterval(t)
  }, [load])

  const totalOnlinePeers = servers.reduce((s, sv) => s + sv.peers.filter(p => p.online).length, 0)
  const totalPeers = servers.reduce((s, sv) => s + sv.peers.length, 0)

  return (
    <div className="min-h-screen bg-background text-foreground px-5 py-8 md:px-10">
      <div className="mx-auto max-w-6xl">
        <header className="mb-6 flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-bold tracking-tight">VPN 服务器管理后台</h1>
            <p className="text-sm text-muted-foreground">
              {servers.length} 台节点 · 在线 peer {totalOnlinePeers}/{totalPeers}
              {fetchedAt && ` · 更新于 ${fetchedAt}（每 30s 自动刷新）`}
            </p>
          </div>
          <button onClick={load}
            className="rounded-lg bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground hover:opacity-90">
            刷新
          </button>
        </header>

        {err && <div className="mb-4 rounded-lg bg-red-500/10 border border-red-500/30 px-4 py-3 text-sm text-red-400">加载失败：{err}</div>}
        {loading && <div className="text-muted-foreground">加载中…</div>}

        <div className="space-y-6">
          {servers.map(sv => (
            <section key={sv.id} className="glass-panel rounded-2xl p-5 ring-1 ring-white/5">
              {/* server header */}
              <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
                <div className="flex items-center gap-3">
                  <span className="text-2xl">{sv.flag_emoji || '🌐'}</span>
                  <div>
                    <div className="font-semibold">{sv.display_name} <span className="text-xs text-muted-foreground">({sv.name})</span></div>
                    <div className="font-mono text-xs text-muted-foreground">{sv.endpoint}</div>
                  </div>
                </div>
                <span className={`rounded-full px-2.5 py-1 text-xs font-medium ring-1 ${
                  sv.online ? 'bg-emerald-400/10 text-emerald-300 ring-emerald-400/30'
                            : 'bg-red-500/10 text-red-400 ring-red-500/30'}`}>
                  {sv.online ? '在线' : `离线${sv.error ? ' · ' + sv.error : ''}`}
                </span>
              </div>

              {/* stats grid */}
              {sv.stats && (
                <div className="mb-4 grid grid-cols-2 gap-3 sm:grid-cols-4 lg:grid-cols-7">
                  <Stat label="活跃 Peer" value={`${sv.stats.active_peers}/${sv.stats.total_peers}`} />
                  <Stat label="CPU" value={`${sv.stats.cpu_percent}%`} warn={sv.stats.cpu_percent > 85} />
                  <Stat label="内存" value={`${sv.stats.mem_percent}%`} warn={sv.stats.mem_percent > 85} />
                  <Stat label="负载(1m)" value={`${sv.stats.load_1m}`} />
                  <Stat label="↓ 带宽" value={`${sv.stats.bw_rx_mbps} Mbps`} />
                  <Stat label="↑ 带宽" value={`${sv.stats.bw_tx_mbps} Mbps`} />
                  <Stat label="运行" value={fmtUptime(sv.stats.uptime_seconds)} />
                </div>
              )}

              {/* peers table */}
              {sv.peers.length > 0 ? (
                <div className="overflow-x-auto rounded-xl ring-1 ring-white/5">
                  <table className="w-full text-left text-xs">
                    <thead className="bg-white/5 text-muted-foreground">
                      <tr>
                        <th className="px-3 py-2 font-medium">状态</th>
                        <th className="px-3 py-2 font-medium">VPN IP</th>
                        <th className="px-3 py-2 font-medium">用户</th>
                        <th className="px-3 py-2 font-medium">设备</th>
                        <th className="px-3 py-2 font-medium">最近握手</th>
                        <th className="px-3 py-2 font-medium text-right">↓ 接收</th>
                        <th className="px-3 py-2 font-medium text-right">↑ 发送</th>
                        <th className="px-3 py-2 font-medium">公钥</th>
                      </tr>
                    </thead>
                    <tbody>
                      {sv.peers.map((p, i) => (
                        <tr key={i} className="border-t border-white/5">
                          <td className="px-3 py-2">
                            <span className={`inline-block size-2 rounded-full ${p.online ? 'bg-emerald-400' : 'bg-zinc-600'}`} />
                          </td>
                          <td className="px-3 py-2 font-mono">{p.vpn_ip}</td>
                          <td className="px-3 py-2">{p.email}</td>
                          <td className="px-3 py-2 text-muted-foreground">{p.device_label || '—'}</td>
                          <td className="px-3 py-2 text-muted-foreground">{fmtAgo(p.last_handshake)}</td>
                          <td className="px-3 py-2 text-right font-mono">{fmtBytes(p.rx_bytes)}</td>
                          <td className="px-3 py-2 text-right font-mono">{fmtBytes(p.tx_bytes)}</td>
                          <td className="px-3 py-2 font-mono text-muted-foreground">{p.public_key}…</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              ) : (
                <div className="text-xs text-muted-foreground">无 peer{sv.online ? '' : '（服务器离线，无法读取）'}</div>
              )}
            </section>
          ))}
        </div>
      </div>
    </div>
  )
}

function Stat({ label, value, warn }: { label: string; value: string; warn?: boolean }) {
  return (
    <div className="rounded-xl bg-white/5 px-3 py-2">
      <div className="text-[10px] uppercase tracking-wide text-muted-foreground">{label}</div>
      <div className={`font-mono text-sm font-semibold ${warn ? 'text-amber-400' : ''}`}>{value}</div>
    </div>
  )
}
