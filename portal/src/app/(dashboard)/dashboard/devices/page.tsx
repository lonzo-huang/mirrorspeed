'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Monitor, Plus, Trash2, RefreshCw, Smartphone, Laptop, Wifi } from 'lucide-react'
import { ConnectDialog } from '@/components/dashboard/connect-dialog'
import type { Tables } from '@/types/database.types'

type Device = Tables<'vpn_devices'>

interface ServerPeer {
  server_id:    string
  display_name: string
  flag_emoji:   string
}

const OS_ICONS: Record<string, React.ReactNode> = {
  windows: <Laptop className="h-4 w-4" />,
  macos:   <Laptop className="h-4 w-4" />,
  ios:     <Smartphone className="h-4 w-4" />,
  android: <Smartphone className="h-4 w-4" />,
  linux:   <Monitor className="h-4 w-4" />,
}

export default function DevicesPage() {
  const supabase                            = createClient()
  const [devices,      setDevices]          = useState<Device[]>([])
  const [devicePeers,  setDevicePeers]      = useState<Record<string, ServerPeer[]>>({})
  const [loading,      setLoading]          = useState(true)
  const [adding,       setAdding]           = useState(false)
  const [hasSub,       setHasSub]           = useState(false)
  const [newLabel,     setNewLabel]         = useState('')
  const [newOs,        setNewOs]            = useState('windows')
  const [error,        setError]            = useState<string | null>(null)
  const [connectOpen,  setConnectOpen]      = useState<string | null>(null)

  useEffect(() => { loadData() }, [])

  async function loadData() {
    setLoading(true)
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return

    const [{ data: devs }, { data: sub }, { data: peers }] = await Promise.all([
      supabase.from('vpn_devices').select('*').eq('user_id', user.id)
        .eq('is_active', true).order('created_at', { ascending: true }),
      supabase.from('subscriptions').select('id').eq('user_id', user.id)
        .eq('status', 'active').maybeSingle(),
      supabase.from('vpn_device_peers')
        .select('device_id, server_id, server:vpn_servers(id, display_name, flag_emoji)')
        .eq('user_id', user.id)
        .eq('is_active', true),
    ])

    setDevices(devs ?? [])
    setHasSub(!!sub)

    // group peers by device_id
    const grouped: Record<string, ServerPeer[]> = {}
    for (const p of (peers as any[]) ?? []) {
      const srv = p.server
      if (!srv) continue
      if (!grouped[p.device_id]) grouped[p.device_id] = []
      grouped[p.device_id].push({
        server_id:    srv.id,
        display_name: srv.display_name,
        flag_emoji:   srv.flag_emoji ?? '',
      })
    }
    setDevicePeers(grouped)
    setLoading(false)
  }

  async function addDevice() {
    if (!newLabel.trim()) return
    setError(null)
    setAdding(true)
    try {
      const res  = await fetch('/api/devices', {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify({ label: newLabel.trim(), os: newOs }),
      })
      const json = await res.json()
      if (!res.ok) throw new Error(json.error ?? '添加失败')
      setNewLabel('')
      await loadData()
    } catch (e: any) {
      setError(e.message)
    } finally {
      setAdding(false)
    }
  }

  async function removeDevice(deviceId: string) {
    if (!confirm('确认删除设备？该设备将立即失去 VPN 访问权限。')) return
    const res = await fetch('/api/devices', {
      method:  'DELETE',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify({ deviceId }),
    })
    if (res.ok) await loadData()
  }

  if (loading) return (
    <div className="flex items-center justify-center py-20">
      <RefreshCw className="h-6 w-6 text-gray-400 animate-spin" />
    </div>
  )

  const connectDevice = connectOpen ? devices.find(d => d.id === connectOpen) : null

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">我的设备</h1>
        <p className="mt-1 text-sm text-gray-500">
          每个账号最多添加 2 台设备，每台设备可通过 Clash 订阅或 WireGuard 接入所有节点。
        </p>
      </div>

      {!hasSub && (
        <div className="card border-yellow-200 bg-yellow-50">
          <p className="text-sm text-yellow-800">
            添加设备前，请先前往
            <a href="/dashboard/billing" className="font-medium underline mx-1">订阅与账单</a>
            开通 VPN 服务。
          </p>
        </div>
      )}

      <div className="space-y-4">
        {devices.map((device, i) => {
          const servers = devicePeers[device.id] ?? []
          return (
            <div key={device.id} className="card">
              <div className="flex items-start justify-between gap-4">
                <div className="flex items-center gap-3">
                  <div className="rounded-lg bg-brand-50 p-2.5 text-brand-600">
                    {OS_ICONS[device.os_hint ?? 'windows'] ?? <Monitor className="h-4 w-4" />}
                  </div>
                  <div>
                    <div className="flex items-center gap-2">
                      <p className="font-semibold text-gray-900">{device.device_label}</p>
                      <span className="badge-active">设备 {i + 1}</span>
                    </div>
                    <p className="text-xs text-gray-400 mt-0.5">
                      {servers.length > 0
                        ? `已连接 ${servers.length} 个节点 · ${servers.map(s => s.flag_emoji).join(' ')}`
                        : '正在配置节点…'
                      }
                    </p>
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  <button
                    onClick={() => setConnectOpen(device.id)}
                    disabled={servers.length === 0}
                    className="btn-primary text-sm px-3 py-1.5 flex items-center gap-1.5 disabled:opacity-40 disabled:cursor-not-allowed"
                  >
                    <Wifi className="h-3.5 w-3.5" />
                    连接
                  </button>
                  <button
                    onClick={() => removeDevice(device.id)}
                    className="rounded-lg p-2 text-gray-400 hover:bg-red-50 hover:text-red-600 transition-colors"
                    title="删除设备"
                  >
                    <Trash2 className="h-4 w-4" />
                  </button>
                </div>
              </div>
            </div>
          )
        })}

        {devices.length < 2 && hasSub && (
          <div className="card border-dashed border-gray-300">
            <div className="flex items-center gap-3 mb-4">
              <Plus className="h-5 w-5 text-gray-400" />
              <h3 className="font-medium text-gray-700">添加新设备</h3>
            </div>

            {error && (
              <div className="mb-3 rounded-lg bg-red-50 px-3 py-2 text-sm text-red-700">{error}</div>
            )}

            <div className="flex gap-3 flex-wrap">
              <input
                type="text"
                value={newLabel}
                onChange={e => setNewLabel(e.target.value)}
                placeholder="设备名称，如「公司 MacBook」"
                className="flex-1 min-w-0 rounded-lg border border-gray-300 px-3 py-2 text-sm
                           focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
                onKeyDown={e => e.key === 'Enter' && addDevice()}
              />
              <select
                value={newOs}
                onChange={e => setNewOs(e.target.value)}
                className="rounded-lg border border-gray-300 px-3 py-2 text-sm bg-white
                           focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
              >
                <option value="windows">Windows</option>
                <option value="macos">macOS</option>
                <option value="ios">iOS</option>
                <option value="android">Android</option>
                <option value="linux">Linux</option>
              </select>
              <button
                onClick={addDevice}
                disabled={adding || !newLabel.trim()}
                className="btn-primary"
              >
                {adding ? <RefreshCw className="h-4 w-4 animate-spin" /> : <Plus className="h-4 w-4" />}
                {adding ? '添加中...' : '添加'}
              </button>
            </div>
          </div>
        )}

        {devices.length === 0 && !hasSub && (
          <div className="text-center py-12 text-gray-400">
            <Monitor className="h-10 w-10 mx-auto mb-3 opacity-30" />
            <p>暂无设备</p>
          </div>
        )}
      </div>

      {connectDevice && (
        <ConnectDialog
          open={!!connectOpen}
          onClose={() => setConnectOpen(null)}
          deviceId={connectDevice.id}
          deviceLabel={connectDevice.device_label}
          subToken={connectDevice.sub_token}
          servers={devicePeers[connectDevice.id] ?? []}
        />
      )}
    </div>
  )
}
