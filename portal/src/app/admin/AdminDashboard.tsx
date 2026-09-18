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
interface Summary {
  online: number; fast: number; relay: number; fast_pct: number
  paid?: number; free?: number; super?: number; paid_pct?: number
  active_24h?: number; active_24h_paid?: number
}
interface ServerRow {
  id: string; name: string; display_name: string; location: string | null; flag_emoji: string | null
  endpoint: string; online: boolean; error?: string
  db_status: string | null; max_peers: number | null
  stats: ServerStats | null; peers: Peer[]; summary?: Summary
  pending?: boolean
}
interface HourPoint { hour: number; paid: number; free: number; peak: number; samples: number }
interface Insights {
  days: number; total_samples: number; first_sample_at: string | null
  all: HourPoint[]; servers: { server_id: string; hours: HourPoint[] }[]
}

function fmtUptime(s: number): string {
  const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600)
  return d > 0 ? `${d}d ${h}h` : `${h}h ${Math.floor((s % 3600) / 60)}m`
}

const REFRESH_MS = 30 * 60 * 1000

export default function AdminDashboard() {
  const [servers, setServers] = useState<ServerRow[]>([])
  const [insights, setInsights] = useState<Insights | null>(null)
  const [insightsErr, setInsightsErr] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [fetchedAt, setFetchedAt] = useState('')
  const [expanded, setExpanded] = useState<Set<string>>(new Set())

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

  const loadInsights = useCallback(async () => {
    try {
      const res = await fetch('/api/admin/usage-insights?days=14', { cache: 'no-store' })
      const data = await res.json()
      if (!res.ok) { setInsightsErr(data?.error ?? `HTTP ${res.status}`); return }
      setInsights(data); setInsightsErr(null)
    } catch (e: any) { setInsightsErr(String(e?.message ?? e)) }
  }, [])

  useEffect(() => {
    ;(async () => { await load('quick'); load('live') })()
    loadInsights()
    const t = setInterval(() => { load('live'); loadInsights() }, REFRESH_MS)
    return () => clearInterval(t)
  }, [load, loadInsights])

  const toggle = (id: string) => setExpanded(s => {
    const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); return n
  })

  const live = servers.some(s => !s.pending)
  const sum = (f: (s: Summary) => number) => servers.reduce((a, sv) => a + (sv.summary ? f(sv.summary) : 0), 0)
  const totalOnline = sum(s => s.online)
  const totalPaid = sum(s => (s.paid ?? 0) + (s.super ?? 0))
  const totalFree = sum(s => s.free ?? 0)
  const total24 = sum(s => s.active_24h ?? 0)
  const paidPct = totalOnline > 0 ? Math.round(totalPaid / totalOnline * 100) : 0
  const insightsByServer = new Map(insights?.servers.map(s => [s.server_id, s.hours]) ?? [])
  const dash = (v: number | string) => (live ? String(v) : '…')

  return (
    <div className="ms-landing min-h-screen bg-app text-app-primary px-5 py-8 md:px-10 relative overflow-hidden">
      <div className="absolute inset-0 grid-bg opacity-20 pointer-events-none" />
      <div className="absolute -top-32 right-1/4 h-96 w-96 rounded-full pointer-events-none" style={{ background: 'var(--accent-cyan-glow)', filter: 'blur(140px)', opacity: 0.15 }} />
      <div className="relative mx-auto max-w-6xl">
        <header className="mb-6 flex flex-wrap items-center justify-between gap-3">
          <div>
            <h1 className="font-heading text-3xl font-black tracking-tighter"><span className="text-gradient-cyan">VPN 服务器管理后台</span></h1>
            <p className="text-sm text-app-muted">
              {servers.length} 台节点
              {refreshing ? ' · ⏳ 拉取实时数据中…' : fetchedAt ? ` · 更新于 ${fetchedAt}` : ''}
            </p>
          </div>
          <div className="flex items-center gap-2">
            <a href="/admin/blog" className="rounded-xl px-4 py-2 text-sm font-semibold glass hover:bg-white/5 transition-colors">博客管理</a>
            <a href="/admin/refunds" className="rounded-xl px-4 py-2 text-sm font-semibold glass hover:bg-white/5 transition-colors">退款申请</a>
            <button onClick={() => { load('live'); loadInsights() }} disabled={refreshing}
              className="rounded-xl px-4 py-2 text-sm font-semibold glow-cyan hover:scale-[1.02] transition-transform disabled:opacity-50">
              {refreshing ? '刷新中…' : '刷新'}</button>
          </div>
        </header>

        {err && <div className="mb-4 rounded-lg bg-red-500/10 border border-red-500/30 px-4 py-3 text-sm text-red-400">加载失败：{err}</div>}
        {loading && <div className="text-app-muted mb-4">加载中…</div>}

        {/* 全网汇总 */}
        <div className="mb-4 grid grid-cols-2 gap-3 sm:grid-cols-5">
          <Stat big label="当前在线" value={dash(totalOnline)} accent />
          <Stat big label="24 小时活跃" value={dash(total24)} />
          <Stat big label="付费在线" value={dash(totalPaid)} />
          <Stat big label="免费在线" value={dash(totalFree)} />
          <Stat big label="付费率" value={dash(`${paidPct}%`)} />
        </div>

        <HourlyChart big title="全网分时在线 · 最近 14 天平均 · 北京时间" data={insights?.all}
          empty={insightsErr ? `分时数据不可用：${insightsErr}` : '尚无数据——采集启动后每 15 分钟积累一次'}
          footnote={insights?.first_sample_at ? `数据起始 ${new Date(insights.first_sample_at).toLocaleString()} · 样本 ${insights.total_samples}` : undefined} />

        {/* 节点卡片 */}
        <div className="mt-6 grid gap-5 lg:grid-cols-2">
          {servers.map(sv => {
            const s = sv.summary
            const paidLike = (s?.paid ?? 0) + (s?.super ?? 0)
            const pend = sv.pending || !sv.online
            const v = (x: number | string) => (sv.pending ? '…' : !sv.online ? '—' : String(x))
            return (
              <section key={sv.id} className="glass-panel rounded-2xl p-5 ring-1 ring-white/5">
                <div className="mb-4 flex items-center justify-between gap-3">
                  <div className="flex items-center gap-3 min-w-0">
                    <span className="text-2xl">{sv.flag_emoji || '🌐'}</span>
                    <div className="min-w-0">
                      <div className="font-semibold truncate">{sv.display_name} <span className="text-xs text-app-muted">({sv.name})</span></div>
                      <div className="font-mono text-xs text-app-muted truncate">{sv.endpoint}</div>
                    </div>
                  </div>
                  <span className={`shrink-0 rounded-full px-2.5 py-1 text-xs font-medium ring-1 ${
                    sv.online ? 'bg-emerald-400/10 text-emerald-300 ring-emerald-400/30'
                              : 'bg-red-500/10 text-red-400 ring-red-500/30'}`}>
                    {sv.online ? '在线' : `离线${sv.error ? ' · ' + sv.error.slice(0, 30) : ''}`}
                  </span>
                </div>

                <div className="mb-3 grid grid-cols-5 gap-2">
                  <Stat label="当前在线" value={v(s?.online ?? 0)} accent />
                  <Stat label="24h 活跃" value={v(s?.active_24h ?? 0)} />
                  <Stat label="付费" value={v(paidLike)} />
                  <Stat label="免费" value={v(s?.free ?? 0)} />
                  <Stat label="付费率" value={v(`${s?.paid_pct ?? 0}%`)} />
                </div>

                {sv.stats && (
                  <div className="mb-3 flex flex-wrap gap-x-4 gap-y-1 text-[11px] font-mono text-app-muted">
                    <span className={sv.stats.cpu_percent > 85 ? 'text-amber-400' : ''}>CPU {sv.stats.cpu_percent}%</span>
                    <span className={sv.stats.mem_percent > 85 ? 'text-amber-400' : ''}>内存 {sv.stats.mem_percent}%</span>
                    <span>负载 {sv.stats.load_1m}</span>
                    <span>↓ {sv.stats.bw_rx_mbps} Mbps</span>
                    <span>↑ {sv.stats.bw_tx_mbps} Mbps</span>
                    <span>运行 {fmtUptime(sv.stats.uptime_seconds)}</span>
                  </div>
                )}

                <HourlyChart title="分时在线 · 14 天平均" data={insightsByServer.get(sv.id)} empty="尚无数据" />

                {!pend && (
                  <button onClick={() => toggle(sv.id)} className="mt-3 text-xs text-accent-cyan hover:underline">
                    {expanded.has(sv.id) ? '▲ 收起用户明细' : `▼ 用户明细（${sv.peers.filter(p => p.online).length} 在线 / ${sv.peers.length} 全部）`}
                  </button>
                )}
                {expanded.has(sv.id) && <PeerTable peers={sv.peers} />}
              </section>
            )
          })}
        </div>
      </div>
    </div>
  )
}

function Stat({ label, value, accent, big }: { label: string; value: string; accent?: boolean; big?: boolean }) {
  return (
    <div className="rounded-xl bg-white/5 px-3 py-2 min-w-0">
      <div className="text-[10px] tracking-wide text-app-muted truncate">{label}</div>
      <div className={`font-mono font-semibold ${big ? 'text-2xl' : 'text-base'} ${accent ? 'text-accent-cyan' : ''}`}>{value}</div>
    </div>
  )
}

/** 分时叠加柱状图：付费(绿)在下、免费(蓝)在上；悬停显示明细；自动标出高峰时段 */
function HourlyChart({ title, data, empty, footnote, big }: {
  title: string; data?: HourPoint[]; empty: string; footnote?: string; big?: boolean
}) {
  const [hover, setHover] = useState<number | null>(null)
  const hasData = !!data && data.some(d => d.samples > 0)
  const H = big ? 180 : 110
  const W = 240, PAD_B = 4
  const max = Math.max(1, ...(data ?? []).map(d => d.paid + d.free))

  // 高峰时段：平均在线最高的 3 个小时
  const peakHours = hasData
    ? [...data!].filter(d => d.samples > 0).sort((a, b) => (b.paid + b.free) - (a.paid + a.free)).slice(0, 3).map(d => d.hour)
    : []
  const hp = hover != null && data ? data[hover] : null

  return (
    <div className="rounded-xl bg-black/20 ring-1 ring-white/5 p-4">
      <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
        <span className="text-xs font-semibold text-app-secondary">{title}</span>
        <span className="text-[10px] text-app-muted">
          <span className="inline-block size-2 rounded-sm bg-emerald-400 mr-1 align-middle" />付费
          <span className="inline-block size-2 rounded-sm bg-sky-400 ml-3 mr-1 align-middle" />免费
        </span>
      </div>
      {!hasData ? (
        <div className="flex items-center justify-center text-[11px] text-app-muted text-center" style={{ height: H }}>{empty}</div>
      ) : (
        <>
          <div className="mb-1 h-4 text-[11px] font-mono text-app-secondary">
            {hp
              ? `${hp.hour}:00–${hp.hour + 1}:00 · 平均 ${Math.round((hp.paid + hp.free) * 10) / 10}（付费 ${hp.paid} / 免费 ${hp.free}）· 峰值 ${hp.peak}`
              : `高峰时段：${peakHours.map(h => `${h}点`).join('、')}　·　纵轴最高 ${Math.round(max * 10) / 10}`}
          </div>
          <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" className="w-full" style={{ height: H }}
            onMouseLeave={() => setHover(null)}>
            {data!.map((d, i) => {
              const bw = W / 24
              const ph = (d.paid / max) * (H - PAD_B - 2)
              const fh = (d.free / max) * (H - PAD_B - 2)
              const x = i * bw + bw * 0.12, w = bw * 0.76
              const yP = H - PAD_B - ph, yF = yP - fh
              const dim = hover != null && hover !== i
              return (
                <g key={i} onMouseEnter={() => setHover(i)} opacity={dim ? 0.45 : 1}>
                  <rect x={i * bw} y={0} width={bw} height={H} fill="transparent" />
                  <rect x={x} y={yF} width={w} height={fh} fill="#38bdf8" rx={1} />
                  <rect x={x} y={yP} width={w} height={ph} fill="#34d399" rx={1} />
                </g>
              )
            })}
          </svg>
          <div className="mt-1 grid text-[9px] text-app-muted font-mono" style={{ gridTemplateColumns: 'repeat(24, 1fr)' }}>
            {Array.from({ length: 24 }, (_, h) => (
              <span key={h} className={`text-center ${peakHours.includes(h) ? 'text-accent-cyan font-bold' : ''}`}>{h % 3 === 0 || peakHours.includes(h) ? h : ''}</span>
            ))}
          </div>
          {footnote && <div className="mt-2 text-[10px] text-app-muted">{footnote}</div>}
        </>
      )}
    </div>
  )
}

function PeerTable({ peers }: { peers: Peer[] }) {
  if (!peers.length) return <div className="mt-3 text-xs text-app-muted">无 peer</div>
  return (
    <div className="mt-3 max-h-80 overflow-auto rounded-xl ring-1 ring-white/5">
      <table className="w-full text-left text-xs">
        <thead className="sticky top-0 bg-[#0b0f16] text-app-muted">
          <tr>
            <th className="px-3 py-2 font-medium">状态</th>
            <th className="px-3 py-2 font-medium">模式</th>
            <th className="px-3 py-2 font-medium">VPN IP</th>
            <th className="px-3 py-2 font-medium">用户</th>
            <th className="px-3 py-2 font-medium">设备</th>
            <th className="px-3 py-2 font-medium">套餐</th>
          </tr>
        </thead>
        <tbody>
          {peers.map((p, i) => (
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
                <span className={p.tier === '付费' ? 'text-emerald-300' : p.tier === '超级' ? 'text-[var(--gold,#E8C766)]' : 'text-app-muted'}>{p.tier}</span>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
