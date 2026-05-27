'use client'

import { useEffect, useState, useCallback } from 'react'
import { Wifi, WifiOff, AlertTriangle, RefreshCw, Activity, Cpu, Users } from 'lucide-react'

interface ServerInfo {
  id:             string
  name:           string
  display_name:   string
  location:       string
  flag_emoji:     string
  status:         'online' | 'degraded' | 'offline' | 'unknown'
  latency_ms:     number | null
  active_peers:   number
  max_peers:      number
  load_percent:   number
  cpu_percent:    number | null
  mem_percent:    number | null
  bandwidth_mbps: number | null
  last_checked_at: string | null
}

// ── 延迟数值 → 颜色 ──────────────────────────────────────────────────────
function latencyColor(ms: number | null): string {
  if (ms === null) return 'text-gray-400'
  if (ms < 80)    return 'text-green-600'
  if (ms < 200)   return 'text-yellow-600'
  return 'text-red-600'
}

function latencyLabel(ms: number | null): string {
  if (ms === null) return '— ms'
  return `${ms} ms`
}

// ── 负载 → 颜色与文字 ────────────────────────────────────────────────────
function loadColor(pct: number): string {
  if (pct < 40) return 'bg-green-500'
  if (pct < 70) return 'bg-yellow-500'
  return 'bg-red-500'
}

function loadLabel(pct: number): { text: string; cls: string } {
  if (pct < 40) return { text: '畅通',   cls: 'badge-active' }
  if (pct < 70) return { text: '正常',   cls: 'badge-pending' }
  if (pct < 90) return { text: '繁忙',   cls: 'badge-expired' }
  return               { text: '拥挤',   cls: 'badge-expired' }
}

// ── 状态图标 ─────────────────────────────────────────────────────────────
function StatusIcon({ status }: { status: ServerInfo['status'] }) {
  switch (status) {
    case 'online':   return <Wifi className="h-4 w-4 text-green-500" />
    case 'degraded': return <AlertTriangle className="h-4 w-4 text-yellow-500" />
    case 'offline':  return <WifiOff className="h-4 w-4 text-red-500" />
    default:         return <WifiOff className="h-4 w-4 text-gray-400" />
  }
}

// ── 单个服务器卡片 ────────────────────────────────────────────────────────
function ServerCard({ server }: { server: ServerInfo }) {
  const load    = loadLabel(server.load_percent)
  const latCls  = latencyColor(server.latency_ms)
  const isDown  = server.status === 'offline' || server.status === 'unknown'

  return (
    <div className={`rounded-xl border bg-white p-4 transition-all
      ${isDown ? 'border-red-100 opacity-60' : 'border-gray-200 shadow-sm hover:shadow-md'}`}
    >
      {/* 顶部：国旗 + 名称 + 状态 */}
      <div className="flex items-start justify-between mb-3">
        <div className="flex items-center gap-2">
          <span className="text-2xl leading-none">{server.flag_emoji}</span>
          <div>
            <p className="font-semibold text-gray-900 text-sm leading-tight">{server.display_name}</p>
            <p className="text-xs text-gray-400">{server.location}</p>
          </div>
        </div>
        <div className="flex items-center gap-1.5">
          <StatusIcon status={server.status} />
          <span className={load.cls}>{load.text}</span>
        </div>
      </div>

      {/* 延迟 */}
      <div className="flex items-center justify-between mb-2">
        <span className="text-xs text-gray-500 flex items-center gap-1">
          <Activity className="h-3 w-3" /> 响应延迟
        </span>
        <span className={`text-sm font-mono font-bold ${latCls}`}>
          {latencyLabel(server.latency_ms)}
        </span>
      </div>

      {/* 负载进度条 */}
      <div className="mb-2">
        <div className="flex items-center justify-between mb-1">
          <span className="text-xs text-gray-500 flex items-center gap-1">
            <Users className="h-3 w-3" /> 在线用户
          </span>
          <span className="text-xs text-gray-600">
            {server.active_peers} / {server.max_peers}
          </span>
        </div>
        <div className="h-1.5 w-full rounded-full bg-gray-100 overflow-hidden">
          <div
            className={`h-full rounded-full transition-all duration-500 ${loadColor(server.load_percent)}`}
            style={{ width: `${Math.min(100, server.load_percent)}%` }}
          />
        </div>
      </div>

      {/* CPU & 带宽 */}
      {(server.cpu_percent !== null || server.bandwidth_mbps !== null) && (
        <div className="flex gap-3 mt-2 pt-2 border-t border-gray-100">
          {server.cpu_percent !== null && (
            <div className="flex items-center gap-1 text-xs text-gray-400">
              <Cpu className="h-3 w-3" />
              <span>CPU {server.cpu_percent.toFixed(0)}%</span>
            </div>
          )}
          {server.bandwidth_mbps !== null && (
            <div className="flex items-center gap-1 text-xs text-gray-400">
              <Activity className="h-3 w-3" />
              <span>{server.bandwidth_mbps.toFixed(1)} Mbps</span>
            </div>
          )}
          {server.last_checked_at && (
            <div className="ml-auto text-xs text-gray-300">
              {timeAgo(server.last_checked_at)}
            </div>
          )}
        </div>
      )}
    </div>
  )
}

// ── 主组件 ────────────────────────────────────────────────────────────────
export function ServerStatus({ isAdmin }: { isAdmin?: boolean }) {
  if (!isAdmin) return null
  const [servers,   setServers]   = useState<ServerInfo[]>([])
  const [loading,   setLoading]   = useState(true)
  const [lastUpdate, setLastUpdate] = useState<Date | null>(null)

  const fetchServers = useCallback(async () => {
    try {
      const res  = await fetch('/api/servers')
      const json = await res.json()
      if (json.servers) {
        setServers(json.servers)
        setLastUpdate(new Date())
      }
    } catch (e) {
      console.error('Failed to fetch server status:', e)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    fetchServers()
    // 每 30 秒轮询一次（cron 每分钟刷新服务器状态，30s 内数据不会太旧）
    const interval = setInterval(fetchServers, 30_000)
    return () => clearInterval(interval)
  }, [fetchServers])

  const online  = servers.filter(s => s.status === 'online').length
  const total   = servers.length

  return (
    <section>
      {/* 标题栏 */}
      <div className="flex items-center justify-between mb-4">
        <div>
          <h2 className="font-semibold text-gray-900">服务器状态</h2>
          <p className="text-xs text-gray-400 mt-0.5">
            {loading ? '加载中...' : `${online}/${total} 台在线`}
            {lastUpdate && (
              <span className="ml-2">· 更新于 {timeAgo(lastUpdate.toISOString())}</span>
            )}
          </p>
        </div>
        <button
          onClick={fetchServers}
          disabled={loading}
          className="rounded-lg p-2 text-gray-400 hover:bg-gray-100 hover:text-gray-600 transition-colors"
          title="刷新"
        >
          <RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} />
        </button>
      </div>

      {/* 服务器网格 */}
      {loading && servers.length === 0 ? (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {[1, 2, 3].map(i => (
            <div key={i} className="rounded-xl border border-gray-100 bg-gray-50 p-4 h-36 animate-pulse" />
          ))}
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {servers.map(server => (
            <ServerCard key={server.id} server={server} />
          ))}
          {servers.length === 0 && (
            <div className="col-span-3 text-center py-8 text-gray-400 text-sm">
              暂无服务器配置
            </div>
          )}
        </div>
      )}

      {/* 延迟图例 */}
      {servers.length > 0 && (
        <div className="mt-3 flex items-center gap-4 text-xs text-gray-400">
          <span className="flex items-center gap-1">
            <span className="inline-block w-2 h-2 rounded-full bg-green-500" /> &lt; 80ms 极速
          </span>
          <span className="flex items-center gap-1">
            <span className="inline-block w-2 h-2 rounded-full bg-yellow-500" /> 80~200ms 正常
          </span>
          <span className="flex items-center gap-1">
            <span className="inline-block w-2 h-2 rounded-full bg-red-500" /> &gt; 200ms 较慢
          </span>
          <span className="ml-auto text-gray-300">延迟为 Portal→服务器，实际客户端延迟由 Clash 自动测速</span>
        </div>
      )}
    </section>
  )
}

// ── 工具函数 ─────────────────────────────────────────────────────────────
function timeAgo(isoStr: string): string {
  const diff = Math.floor((Date.now() - new Date(isoStr).getTime()) / 1000)
  if (diff < 60)   return `${diff}秒前`
  if (diff < 3600) return `${Math.floor(diff / 60)}分钟前`
  return `${Math.floor(diff / 3600)}小时前`
}
