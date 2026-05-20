'use client'

import { useState } from 'react'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Copy, Check, Download, QrCode, Wifi, ExternalLink, RefreshCw } from 'lucide-react'

interface ServerPeer {
  server_id:    string
  display_name: string
  flag_emoji:   string
}

interface ConnectDialogProps {
  open:        boolean
  onClose:     () => void
  deviceId:    string
  deviceLabel: string
  subToken:    string
  servers:     ServerPeer[]
}

export function ConnectDialog({ open, onClose, deviceId, deviceLabel, subToken, servers }: ConnectDialogProps) {
  const [tab,            setTab]            = useState<'clash' | 'wireguard'>('clash')
  const [selectedServer, setSelectedServer] = useState(servers[0]?.server_id ?? '')
  const [copied,         setCopied]         = useState(false)
  const [qrError,        setQrError]        = useState(false)
  const [qrLoading,      setQrLoading]      = useState(true)

  const appUrl  = process.env.NEXT_PUBLIC_APP_URL ?? window.location.origin
  const clashUrl = `${appUrl}/api/sub/${subToken}`
  const clashDeepLink = `clash://install-config?url=${encodeURIComponent(clashUrl)}&name=${encodeURIComponent(deviceLabel)}`
  const wgConfUrl     = `/api/devices/${deviceId}/wireguard-config?server=${selectedServer}`
  const qrUrl         = `/api/devices/${deviceId}/qr?server=${selectedServer}`

  async function copyClashUrl() {
    await navigator.clipboard.writeText(clashUrl)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  function handleServerChange(serverId: string) {
    setSelectedServer(serverId)
    setQrError(false)
    setQrLoading(true)
  }

  return (
    <Dialog open={open} onOpenChange={v => !v && onClose()}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Wifi className="h-5 w-5 text-brand-600" />
            连接 — {deviceLabel}
          </DialogTitle>
        </DialogHeader>

        {/* Tab 切换 */}
        <div className="flex rounded-lg bg-gray-100 p-1 gap-1">
          {(['clash', 'wireguard'] as const).map(t => (
            <button
              key={t}
              onClick={() => setTab(t)}
              className={`flex-1 rounded-md py-1.5 text-sm font-medium transition-colors ${
                tab === t
                  ? 'bg-white text-gray-900 shadow-sm'
                  : 'text-gray-500 hover:text-gray-700'
              }`}
            >
              {t === 'clash' ? 'Clash 订阅' : 'WireGuard'}
            </button>
          ))}
        </div>

        {tab === 'clash' && (
          <div className="space-y-4">
            <p className="text-sm text-gray-500">
              将订阅链接粘贴到 Clash 的「代理提供者」，或点击下方按钮直接在 Clash 中打开。
              客户端会自动获取所有节点并每 24 小时更新配置。
            </p>

            {/* 订阅 URL */}
            <div className="rounded-lg border border-gray-200 bg-gray-50 p-3">
              <p className="text-xs font-medium text-gray-500 mb-2">订阅链接</p>
              <div className="flex items-center gap-2">
                <code className="flex-1 truncate text-xs text-gray-700 font-mono bg-white border border-gray-200 rounded px-2.5 py-1.5">
                  {clashUrl}
                </code>
                <button
                  onClick={copyClashUrl}
                  className="shrink-0 rounded-lg border border-gray-200 bg-white px-2.5 py-1.5 text-xs text-gray-600 hover:bg-gray-50 transition-colors flex items-center gap-1"
                >
                  {copied
                    ? <><Check className="h-3.5 w-3.5 text-green-600" />已复制</>
                    : <><Copy className="h-3.5 w-3.5" />复制</>
                  }
                </button>
              </div>
            </div>

            {/* 一键在 Clash 中打开 */}
            <a
              href={clashDeepLink}
              className="btn-primary w-full justify-center flex items-center gap-2 text-sm"
            >
              <ExternalLink className="h-4 w-4" />
              在 Clash 中打开
            </a>
            <p className="text-xs text-gray-400 text-center">
              需要已安装 Clash Meta / Clash Verge / Stash 等客户端
            </p>
          </div>
        )}

        {tab === 'wireguard' && (
          <div className="space-y-4">
            {/* 服务器选择 */}
            {servers.length > 1 && (
              <div>
                <label className="text-xs font-medium text-gray-600 mb-1.5 block">选择节点</label>
                <select
                  value={selectedServer}
                  onChange={e => handleServerChange(e.target.value)}
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500"
                >
                  {servers.map(s => (
                    <option key={s.server_id} value={s.server_id}>
                      {s.flag_emoji} {s.display_name}
                    </option>
                  ))}
                </select>
              </div>
            )}

            {/* QR 码 */}
            <div className="flex flex-col items-center gap-3">
              <p className="text-xs text-gray-500 self-start">
                使用 WireGuard App 扫描下方二维码导入配置
              </p>
              <div className="relative w-56 h-56 rounded-xl border-2 border-gray-200 overflow-hidden bg-gray-50 flex items-center justify-center">
                {qrLoading && !qrError && (
                  <div className="absolute inset-0 flex items-center justify-center bg-gray-50 z-10">
                    <RefreshCw className="h-6 w-6 text-gray-300 animate-spin" />
                  </div>
                )}
                {qrError ? (
                  <div className="flex flex-col items-center gap-2 text-gray-400">
                    <QrCode className="h-8 w-8 opacity-30" />
                    <p className="text-xs">加载失败</p>
                    <button
                      onClick={() => { setQrError(false); setQrLoading(true) }}
                      className="text-xs text-brand-600 hover:underline"
                    >重试</button>
                  </div>
                ) : (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img
                    key={qrUrl}
                    src={qrUrl}
                    alt="WireGuard 配置二维码"
                    className="w-full h-full object-contain"
                    onLoad={() => setQrLoading(false)}
                    onError={() => { setQrError(true); setQrLoading(false) }}
                  />
                )}
              </div>
              <p className="text-xs text-gray-400 text-center">
                WireGuard App → + → 扫描二维码
              </p>
            </div>

            {/* 下载 .conf */}
            <a
              href={wgConfUrl}
              download
              className="flex items-center justify-center gap-2 w-full rounded-lg border border-gray-300 bg-white px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
            >
              <Download className="h-4 w-4" />
              下载 .conf 文件
            </a>
            <p className="text-xs text-gray-400 text-center">
              在电脑端：WireGuard → 从文件导入隧道
            </p>
          </div>
        )}
      </DialogContent>
    </Dialog>
  )
}
