'use client'

import { useEffect, useState } from 'react'
import { SiteNav } from '@/components/site/SiteNav'
import { SiteFooter } from '@/components/site/SiteFooter'
import { useI18n } from '@/lib/i18n'
import type { LatestRelease, ReleaseAsset } from '@/app/api/releases/latest/route'

// ── 第三方 Clash 客户端（保持原有内容）──────────────────────
const CLIENTS = [
  { os: 'macOS',   client: 'ClashX Pro',            arch: 'Apple Silicon / Intel',  url: 'https://github.com/yichengchen/clashX/releases', recommended: true  },
  { os: 'Windows', client: 'Clash Verge',            arch: 'x64 / ARM64',            url: 'https://github.com/clash-verge-rev/clash-verge-rev/releases', recommended: true  },
  { os: 'iOS',     client: 'Shadowrocket',           arch: 'App Store',              url: 'https://apps.apple.com/app/shadowrocket/id932747118', recommended: true  },
  { os: 'Android', client: 'ClashMetaForAndroid',    arch: 'APK · arm64',            url: 'https://github.com/MetaCubeX/ClashMetaForAndroid/releases', recommended: true  },
  { os: 'Linux',   client: 'Clash Verge',            arch: '.deb / .rpm / AppImage', url: 'https://github.com/clash-verge-rev/clash-verge-rev/releases', recommended: false },
  { os: 'OpenWrt', client: 'OpenClash',              arch: 'Router firmware',        url: 'https://github.com/vernesong/OpenClash/releases', recommended: false },
]

const PLATFORM_ICONS: Record<string, string> = {
  android: '🤖',
  windows: '🪟',
  ios:     '🍎',
  macos:   '🍎',
}

function formatBytes(bytes: number) {
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`
}

function platformLabel(p: ReleaseAsset['platform']) {
  return { android: 'Android', windows: 'Windows', ios: 'iOS', macos: 'macOS', other: '其他' }[p]
}

export default function DownloadPage() {
  const { t } = useI18n()
  const [release, setRelease] = useState<LatestRelease | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    fetch('/api/releases/latest', { cache: 'no-store' })
      .then(r => r.json())
      .then(d => { setRelease(d.version ? d : null) })
      .catch(() => setRelease(null))
      .finally(() => setLoading(false))
  }, [])

  const nativeAssets = release?.assets.filter(a => a.platform !== 'other') ?? []

  return (
    <div className="min-h-screen bg-background text-foreground">
      <SiteNav />
      <main className="px-6 pt-16 pb-24">
        <div className="max-w-5xl mx-auto">
          <div className="text-center mb-14">
            <h1 className="text-5xl font-bold tracking-tighter mb-3">{t.download.title}</h1>
            <p className="text-muted-foreground max-w-2xl mx-auto">{t.download.sub}</p>
          </div>

          {/* ── MirrorSpeed 原生客户端 ────────────────────────── */}
          <div className="mb-14">
            <div className="flex items-center justify-between mb-5">
              <div>
                <h2 className="text-xl font-bold">MirrorSpeed VPN 客户端</h2>
                <p className="text-sm text-muted-foreground mt-1">
                  原生 WireGuard 客户端，一键登录，自动接入全球节点
                </p>
              </div>
              {release && (
                <span className="text-xs font-mono bg-mirror/10 border border-mirror/20 text-mirror px-3 py-1 rounded-full">
                  v{release.version}
                </span>
              )}
            </div>

            {loading ? (
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {[0, 1].map(i => (
                  <div key={i} className="glass-panel rounded-2xl p-6 animate-pulse h-28" />
                ))}
              </div>
            ) : nativeAssets.length > 0 ? (
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {nativeAssets.map(asset => {
                  const cnUrl = asset.platform === 'android'
                    ? release?.cn_apk_url
                    : asset.platform === 'windows'
                      ? release?.cn_win_url
                      : null
                  return (
                  <div key={asset.name} className="glass-panel rounded-2xl p-6 flex items-center justify-between gap-4 hover:border-mirror/40 transition-colors">
                    <div>
                      <div className="flex items-center gap-2 mb-1">
                        <span className="text-xl">{PLATFORM_ICONS[asset.platform] ?? '💾'}</span>
                        <h3 className="font-bold">{platformLabel(asset.platform)}</h3>
                        <span className="text-[9px] font-bold uppercase tracking-widest text-mirror bg-mirror/10 border border-mirror/20 px-2 py-0.5 rounded-full">
                          官方
                        </span>
                      </div>
                      <p className="text-sm text-muted-foreground">{asset.name}</p>
                      <p className="text-[10px] text-muted-foreground font-mono mt-1">
                        {formatBytes(asset.size)} · {new Date(release!.published).toLocaleDateString('zh-CN')}
                      </p>
                    </div>
                    <div className="flex flex-col gap-2 shrink-0">
                      {cnUrl && (
                        <a
                          href={cnUrl}
                          className="text-xs font-bold bg-red-500/80 hover:bg-red-500 text-white px-4 py-2 rounded-lg transition-colors text-center whitespace-nowrap"
                          title="通过国内镜像高速下载"
                        >
                          🇨🇳 高速下载
                        </a>
                      )}
                      <a
                        href={`/api/download?id=${asset.id}&name=${encodeURIComponent(asset.name)}`}
                        className="text-xs font-bold bg-primary text-primary-foreground px-4 py-2 rounded-lg hover:bg-mirror transition-colors text-center whitespace-nowrap"
                        title="通过 GitHub 下载"
                      >
                        {cnUrl ? '备用下载' : '下载'}
                      </a>
                    </div>
                  </div>
                  )
                })}
              </div>
            ) : (
              /* 尚未发布时的占位 */
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {[
                  { platform: 'Android', icon: '🤖', desc: 'APK · arm64-v8a', badge: '即将发布' },
                  { platform: 'Windows', icon: '🪟', desc: 'x64 · ZIP 免安装', badge: '即将发布' },
                ].map(p => (
                  <div key={p.platform} className="glass-panel rounded-2xl p-6 flex items-center justify-between gap-4 opacity-60">
                    <div>
                      <div className="flex items-center gap-2 mb-1">
                        <span className="text-xl">{p.icon}</span>
                        <h3 className="font-bold">{p.platform}</h3>
                        <span className="text-[9px] font-bold uppercase tracking-widest text-yellow-500 bg-yellow-500/10 border border-yellow-500/20 px-2 py-0.5 rounded-full">
                          {p.badge}
                        </span>
                      </div>
                      <p className="text-sm text-muted-foreground">{p.desc}</p>
                    </div>
                    <button disabled className="text-xs font-bold bg-muted text-muted-foreground px-4 py-2 rounded-lg cursor-not-allowed">
                      下载
                    </button>
                  </div>
                ))}
              </div>
            )}
          </div>

          <div className="border-t border-white/10 mb-14" />

          {/* ── Quick start（原有） ───────────────────────────── */}
          <div className="glass-panel rounded-2xl p-6 mb-10">
            <h2 className="text-xs font-bold uppercase tracking-widest text-mirror mb-4">{t.download.step}</h2>
            <ol className="space-y-3">
              {t.download.steps.map((s, i) => (
                <li key={i} className="flex gap-3 text-sm">
                  <span className="w-6 h-6 shrink-0 rounded-full bg-mirror/10 border border-mirror/30 text-mirror font-mono text-xs grid place-items-center">{i + 1}</span>
                  <span className="text-foreground/90">{s}</span>
                </li>
              ))}
            </ol>
          </div>

          {/* ── Clash 第三方客户端（原有） ────────────────────── */}
          <div className="mb-6">
            <h2 className="text-xl font-bold mb-1">Clash / 第三方客户端</h2>
            <p className="text-sm text-muted-foreground">通过订阅链接接入，支持分流规则</p>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {CLIENTS.map((c) => (
              <div key={c.os} className="glass-panel rounded-2xl p-6 flex items-center justify-between gap-4 hover:border-mirror/40 transition-colors">
                <div>
                  <div className="flex items-center gap-2 mb-1">
                    <h3 className="font-bold">{c.os}</h3>
                    {c.recommended && (
                      <span className="text-[9px] font-bold uppercase tracking-widest text-mirror bg-mirror/10 border border-mirror/20 px-2 py-0.5 rounded-full">
                        {t.download.recommended}
                      </span>
                    )}
                  </div>
                  <p className="text-sm text-muted-foreground">{c.client}</p>
                  <p className="text-[10px] text-muted-foreground font-mono mt-1">{c.arch}</p>
                </div>
                <div className="flex flex-col gap-2 shrink-0">
                  <a href={c.url} target="_blank" rel="noreferrer"
                    className="text-xs font-bold bg-primary text-primary-foreground px-4 py-2 rounded-lg hover:bg-mirror transition-colors text-center">
                    {t.download.install}
                  </a>
                  <a href={c.url} target="_blank" rel="noreferrer"
                    className="text-[10px] text-muted-foreground hover:text-mirror text-center">
                    {t.download.guide} →
                  </a>
                </div>
              </div>
            ))}
          </div>
        </div>
      </main>
      <SiteFooter />
    </div>
  )
}
