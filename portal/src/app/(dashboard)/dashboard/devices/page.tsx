'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Monitor, Plus, Trash2, Copy, RefreshCw, Check, Smartphone, Laptop } from 'lucide-react'
import type { Tables } from '@/types/database.types'

type Device = Tables<'vpn_devices'>

const OS_ICONS: Record<string, React.ReactNode> = {
  windows: <Laptop className="h-4 w-4" />,
  macos:   <Laptop className="h-4 w-4" />,
  ios:     <Smartphone className="h-4 w-4" />,
  android: <Smartphone className="h-4 w-4" />,
  linux:   <Monitor className="h-4 w-4" />,
}

export default function DevicesPage() {
  const supabase                      = createClient()
  const [devices,  setDevices]        = useState<Device[]>([])
  const [loading,  setLoading]        = useState(true)
  const [adding,   setAdding]         = useState(false)
  const [hasSub,   setHasSub]         = useState(false)
  const [newLabel, setNewLabel]       = useState('')
  const [newOs,    setNewOs]          = useState('windows')
  const [copied,   setCopied]         = useState<string | null>(null)
  const [error,    setError]          = useState<string | null>(null)

  useEffect(() => { loadData() }, [])

  async function loadData() {
    setLoading(true)
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return

    const [{ data: devs }, { data: sub }] = await Promise.all([
      supabase.from('vpn_devices').select('*').eq('user_id', user.id)
        .eq('is_active', true).order('created_at', { ascending: true }),
      supabase.from('subscriptions').select('id').eq('user_id', user.id)
        .eq('status', 'active').maybeSingle(),
    ])

    setDevices(devs ?? [])
    setHasSub(!!sub)
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

  function subUrl(token: string) {
    return `${process.env.NEXT_PUBLIC_APP_URL}/api/sub/${token}`
  }

  async function copySubUrl(token: string) {
    await navigator.clipboard.writeText(subUrl(token))
    setCopied(token)
    setTimeout(() => setCopied(null), 2000)
  }

  function downloadConfig(device: Device) {
    window.open(`/api/devices/${device.id}/clash-config`, '_blank')
  }

  if (loading) return (
    <div className="flex items-center justify-center py-20">
      <RefreshCw className="h-6 w-6 text-gray-400 animate-spin" />
    </div>
  )

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">我的设备</h1>
        <p className="mt-1 text-sm text-gray-500">
          每个账号最多添加 2 台设备，每台设备有独立的 Clash 订阅链接。
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
        {devices.map((device, i) => (
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
                  <p className="text-xs text-gray-400 mt-0.5">已连接多节点</p>
                </div>
              </div>
              <button
                onClick={() => removeDevice(device.id)}
                className="rounded-lg p-2 text-gray-400 hover:bg-red-50 hover:text-red-600 transition-colors"
                title="删除设备"
              >
                <Trash2 className="h-4 w-4" />
              </button>
            </div>

            <div className="mt-4 rounded-lg bg-gray-50 p-3">
              <p className="text-xs font-medium text-gray-600 mb-2">Clash 订阅链接</p>
              <div className="flex items-center gap-2">
                <code className="flex-1 truncate rounded bg-white border border-gray-200 px-2.5 py-1.5 text-xs text-gray-700 font-mono">
                  {subUrl(device.sub_token)}
                </code>
                <button
                  onClick={() => copySubUrl(device.sub_token)}
                  className="btn-secondary px-2.5 py-1.5 text-xs shrink-0"
                  title="复制链接"
                >
                  {copied === device.sub_token
                    ? <Check className="h-3.5 w-3.5 text-green-600" />
                    : <Copy className="h-3.5 w-3.5" />
                  }
                </button>
                <button
                  onClick={() => downloadConfig(device)}
                  className="btn-secondary px-2.5 py-1.5 text-xs shrink-0"
                  title="下载 Clash 配置文件"
                >
                  下载配置
                </button>
              </div>
              <p className="mt-2 text-xs text-gray-400">
                将订阅链接粘贴到 Clash 的「代理提供者」中，客户端会自动获取并更新配置。
              </p>
            </div>
          </div>
        ))}

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
    </div>
  )
}
