'use client'

import { useEffect, useState, useCallback } from 'react'

interface Peer {
  vpn_ip: string; online: boolean; mode: 'fast' | 'relay' | 'offline'
  device_id: string; email: string; tier: string
}
interface ServerStats {
  status: string; active_peers: number; total_peers: number
  cpu_percent: number; mem_percent: number; bw_tx_mbps: number; bw_rx_mbps: number
  load_1m: number; uptime_seconds: number
}
interface Summary { online: number; fast: number; relay: number; fast_pct: number }
interface ServerRow {
  id: string; name: string; display_name: string; location: string | null; flag_emoji: string | null
  endpoint: string; online: boolean; error?: string
  db_status: string | null; max_peers: number | null
  stats: ServerStats | null; peers: Peer[]; summary?: Summary
  pending?: boolean
}

function fmtUptime(s: number): string {
  const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600)
  return d > 0 ? `${d}d ${h}h` : `${h}h ${Math.floor((s % 3600) / 60)}m`
}

const REFRESH_MS = 30 * 60 * 1000   // 30 分钟自动刷新（按需点"刷新"手动更新）

export default function AdminDashboard() {
  const [servers, setServers] = useState<ServerRow[]>([])
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [fetchedAt, setFetchedAt] = useState<string>('')

  const load = useCallback(async (mode: 'quick' | 'live' = 'live') => {
    setErr(null)
    if (mode === 'live') setRefreshing(true)
    try {
      const res = await fetch(`/api/admin/servers-overview?mode=${mode}`, { cache: 'no-store' })
      if (!res.ok) { setErr(`HTTP ${res.status}`); return }
      const data = await res.json()
      setServers(data.servers ?? [])
      if (mode === 'live') setFetchedAt(new Date().toLocaleString())
    } catch (e: any) {
      setErr(String(e?.message ?? e))
    } finally {
      setLoading(false)
      if (mode === 'live') setRefreshing(false)
    }
  }, [])

  useEffect(() => {
    // 两阶段：先 quick 秒开，再 live 补全实时明细
    ;(async () => {
      await load('quick')
      load('live')
    })()
    const t = setInterval(() => load('live'), REFRESH_MS)
    return () => clearInterval(t)
  }, [load])

  const totalOnline = servers.reduce((s, sv) => s + (sv.summary?.online ?? 0), 0)
  const totalFast = servers.reduce((s, sv) => s + (sv.summary?.fast ?? 0), 0)

  return (
    <div className="ms-landing min-h-screen bg-app text-app-primary px-5 py-8 md:px-10 relative overflow-hidden">
      <div className="absolute inset-0 grid-bg opacity-20 pointer-events-none" />
      <div className="absolute -top-32 right-1/4 h-96 w-96 rounded-full pointer-events-none" style={{ background: 'var(--accent-cyan-glow)', filter: 'blur(140px)', opacity: 0.15 }} />
      <div className="relative mx-auto max-w-5xl">
        <header className="mb-6 flex items-center justify-between">
          <div>
            <h1 className="font-heading text-3xl font-black tracking-tighter"><span className="text-gradient-cyan">VPN 服务器管理后台</span></h1>
            <p className="text-sm text-app-muted">
              {servers.length} 台节点 · 在线 {totalOnline} · 快速 {totalFast}
              {totalOnline > 0 && `（${Math.round(totalFast / totalOnline * 100)}%）`}
              {refreshing && ' · ⏳ 拉取实时数据中…'}
              {!refreshing && fetchedAt && ` · 更新于 ${fetchedAt}（每 30 分钟自动刷新）`}
            </p>
          </div>
          <div className="flex items-center gap-2">
            <a href="/admin/blog"
              className="rounded-xl px-4 py-2 text-sm font-semibold glass hover:bg-white/5 transition-colors">博客管理</a>
            <button onClick={() => load('live')} disabled={refreshing}
              className="rounded-lg px-4 py-2 text-sm font-semibold rounded-xl glow-cyan hover:scale-[1.02] transition-transform disabled:opacity-50">
              {refreshing ? '刷新中…' : '刷新'}</button>
          </div>
        </header>

        {err && <div className="mb-4 rounded-lg bg-red-500/10 border border-red-500/30 px-4 py-3 text-sm text-red-400">加载失败：{err}</div>}
        {loading && <div className="text-app-muted">加载中…</div>}

        <div className="space-y-6">
          {servers.map(sv => (
            <section key={sv.id} className="glass-panel rounded-2xl p-5 ring-1 ring-white/5">
              <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
                <div className="flex items-center gap-3">
                  <span className="text-2xl">{sv.flag_emoji || '🌐'}</span>
                  <div>
                    <div className="font-semibold">{sv.display_name} <span className="text-xs text-app-muted">({sv.name})</span></div>
                    <div className="font-mono text-xs text-app-muted">{sv.endpoint}</div>
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  {sv.summary && sv.online && (
                    <span className="rounded-full bg-white/5 px-2.5 py-1 text-xs ring-1 ring-white/10">
                      快速 <b className="text-emerald-300">{sv.summary.fast}</b> · 强力 <b className="text-amber-300">{sv.summary.relay}</b> · 快速率 <b>{sv.summary.fast_pct}%</b>
                    </span>
                  )}
                  <span className={`rounded-full px-2.5 py-1 text-xs font-medium ring-1 ${
                    sv.online ? 'bg-emerald-400/10 text-emerald-300 ring-emerald-400/30'
                              : 'bg-red-500/10 text-red-400 ring-red-500/30'}`}>
                    {sv.online ? '在线' : `离线${sv.error ? ' · ' + sv.error : ''}`}
                  </span>
                </div>
              </div>

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

              {sv.pending ? (
                <div className="text-xs text-app-muted">⏳ 实时明细加载中…</div>
              ) : sv.peers.length > 0 ? (
                <div className="overflow-x-auto rounded-xl ring-1 ring-white/5">
                  <table className="w-full text-left text-xs">
                    <thead className="bg-white/5 text-app-muted">
                      <tr>
                        <th className="px-3 py-2 font-medium">状态</th>
                        <th className="px-3 py-2 font-medium">模式</th>
                        <th className="px-3 py-2 font-medium">VPN IP</th>
                        <th className="px-3 py-2 font-medium">用户名</th>
                        <th className="px-3 py-2 font-medium">设备 ID</th>
                        <th className="px-3 py-2 font-medium">套餐</th>
                      </tr>
                    </thead>
                    <tbody>
                      {sv.peers.map((p, i) => (
                        <tr key={i} className="border-t border-white/5">
                          <td className="px-3 py-2"><span className={`inline-block size-2 rounded-full ${p.online ? 'bg-emerald-400' : 'bg-zinc-600'}`} /></td>
                          <td className="px-3 py-2">
                            {p.mode === 'fast' && <span className="rounded bg-emerald-400/15 px-1.5 py-0.5 text-[10px] text-emerald-300">快速</span>}
                            {p.mode === 'relay' && <span className="rounded bg-amber-400/15 px-1.5 py-0.5 text-[10px] text-amber-300">强力</span>}
                            {p.mode === 'offline' && <span className="text-zinc-600">—</span>}
                          </td>
                          <td className="px-3 py-2 font-mono">{p.vpn_ip}</td>
                          <td className="px-3 py-2">{p.email}</td>
                          <td className="px-3 py-2 font-mono text-app-muted">{p.device_id}</td>
                          <td className="px-3 py-2">
                            <span className={
                              p.tier === '付费' ? 'text-emerald-300' : p.tier === '超级' ? 'text-[var(--gold,#E8C766)]' : 'text-app-muted'
                            }>{p.tier}</span>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              ) : (
                <div className="text-xs text-app-muted">无 peer{sv.online ? '' : '（服务器离线，无法读取）'}</div>
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
      <div className="text-[10px] uppercase tracking-wide text-app-muted">{label}</div>
      <div className={`font-mono text-sm font-semibold ${warn ? 'text-amber-400' : ''}`}>{value}</div>
    </div>
  )
}
