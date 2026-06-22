'use client'

import { useEffect, useState } from 'react'
import { SiteNav } from '@/components/site/SiteNav'
import { SiteFooter } from '@/components/site/SiteFooter'
import { useI18n } from '@/lib/i18n'
import type { LatestRelease, ReleaseAsset } from '@/app/api/releases/latest/route'

// Third-party Clash clients — listed as roadmap items
const CLIENTS = [
  { os: 'macOS',   client: 'ClashX Pro',         arch: 'Apple Silicon / Intel',  url: 'https://github.com/yichengchen/clashX/releases' },
  { os: 'Windows', client: 'Clash Verge',         arch: 'x64 / ARM64',            url: 'https://github.com/clash-verge-rev/clash-verge-rev/releases' },
  { os: 'iOS',     client: 'Shadowrocket',        arch: 'App Store',              url: 'https://apps.apple.com/app/shadowrocket/id932747118' },
  { os: 'Android', client: 'ClashMetaForAndroid', arch: 'APK · arm64',            url: 'https://github.com/MetaCubeX/ClashMetaForAndroid/releases' },
  { os: 'Linux',   client: 'Clash Verge',         arch: '.deb / .rpm / AppImage', url: 'https://github.com/clash-verge-rev/clash-verge-rev/releases' },
  { os: 'OpenWrt', client: 'OpenClash',           arch: 'Router firmware',        url: 'https://github.com/vernesong/OpenClash/releases' },
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

function isCnApk(name: string) {
  const n = name.toLowerCase()
  // Matches: jinsu*, *-cn-*, *cn-arm64*, etc.
  return n.includes('jinsu') || n.match(/[_-]cn[_-]/) !== null
}

function isGlobalApk(name: string) {
  const n = name.toLowerCase()
  // Matches: mirrorspeed*, *-global-*, *global-arm64*, etc.
  return (n.includes('mirrorspeed') || n.match(/[_-]global[_-]/) !== null) && n.endsWith('.apk')
}

function isArm64Apk(name: string) {
  const n = name.toLowerCase()
  return n.includes('arm64') || n.includes('aarch64')
}

export default function DownloadPage() {
  const { t, lang } = useI18n()
  const dl = t.download
  const isChinese = lang === 'zh'

  const [release, setRelease] = useState<LatestRelease | null>(null)
  const [loading, setLoading]   = useState(true)

  useEffect(() => {
    fetch('/api/releases/latest', { cache: 'no-store' })
      .then(r => r.json())
      .then(d => { setRelease(d.version ? d : null) })
      .catch(() => setRelease(null))
      .finally(() => setLoading(false))
  }, [])

  // For Chinese: show CN-flavor arm64 APK + Windows; for others: show global arm64 APK + Windows
  const displayedAssets: ReleaseAsset[] = (() => {
    if (!release?.assets) return []
    // v2.0.4+ 起为单一安装包（壳按设备语言运行时切换），不再区分 cn/global APK。
    // 优先按旧命名匹配以兼容历史 Release，最终一律兜底到「任意 android 资源」。
    const apk =
        (isChinese
          ? release.assets.find(a => isCnApk(a.name) && isArm64Apk(a.name))
            ?? release.assets.find(a => isCnApk(a.name))
          : release.assets.find(a => isGlobalApk(a.name) && isArm64Apk(a.name))
            ?? release.assets.find(a => isGlobalApk(a.name)))
        ?? release.assets.find(a => a.platform === 'android' && isArm64Apk(a.name))
        ?? release.assets.find(a => a.platform === 'android')
    const winAsset = release.assets.find(a => a.platform === 'windows')
    return [apk, winAsset].filter(Boolean) as ReleaseAsset[]
  })()

  // Placeholders when no release is available yet
  const placeholders = isChinese
    ? [
        { platform: 'Android', icon: '🤖', desc: 'APK · arm64-v8a' },
        { platform: 'Windows', icon: '🪟', desc: 'x64 · ZIP 免安装' },
      ]
    : [
        { platform: 'Android', icon: '🤖', desc: 'APK · arm64-v8a' },
        { platform: 'Windows', icon: '🪟', desc: 'x64 · ZIP portable' },
      ]

  return (
    <div className="min-h-screen bg-background text-foreground">
      <SiteNav />
      <main className="px-6 pt-16 pb-24">
        <div className="max-w-5xl mx-auto">
          <div className="text-center mb-14">
            <h1 className="text-5xl font-bold tracking-tighter mb-3">{dl.title}</h1>
            <p className="text-muted-foreground max-w-2xl mx-auto">{dl.sub}</p>
          </div>

          {/* ── Native client section ──────────────────────────────── */}
          <div className="mb-14">
            <div className="flex items-center justify-between mb-5">
              <div>
                <h2 className="text-xl font-bold">{dl.appClient}</h2>
                <p className="text-sm text-muted-foreground mt-1">{dl.appClientDesc}</p>
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
            ) : displayedAssets.length > 0 ? (
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {displayedAssets.map(asset => {
                  // Determine fast-download URL based on language
                  let fastUrl: string | null = null
                  if (isChinese) {
                    if (asset.platform === 'android') fastUrl = release?.cn_apk_cn_url ?? release?.cn_apk_url ?? null
                    if (asset.platform === 'windows') fastUrl = release?.cn_win_url ?? null
                  }

                  const platformDisplay = asset.platform === 'android'
                    ? (isChinese ? 'Android' : 'Android')
                    : asset.platform === 'windows'
                      ? 'Windows'
                      : asset.platform.charAt(0).toUpperCase() + asset.platform.slice(1)

                  return (
                    <div key={asset.name} className="glass-panel rounded-2xl p-6 flex items-center justify-between gap-4 hover:border-mirror/40 transition-colors">
                      <div>
                        <div className="flex items-center gap-2 mb-1">
                          <span className="text-xl">{PLATFORM_ICONS[asset.platform] ?? '💾'}</span>
                          <h3 className="font-bold">{platformDisplay}</h3>
                          <span className="text-[9px] font-bold uppercase tracking-widest text-mirror bg-mirror/10 border border-mirror/20 px-2 py-0.5 rounded-full">
                            {dl.official}
                          </span>
                        </div>
                        <p className="text-sm text-muted-foreground">{asset.name}</p>
                        <p className="text-[10px] text-muted-foreground font-mono mt-1">
                          {formatBytes(asset.size)} · {new Date(release!.published).toLocaleDateString()}
                        </p>
                      </div>
                      <div className="flex flex-col gap-2 shrink-0">
                        {fastUrl && (
                          <a
                            href={fastUrl}
                            className="text-xs font-bold bg-red-500/80 hover:bg-red-500 text-white px-4 py-2 rounded-lg transition-colors text-center whitespace-nowrap"
                          >
                            🚀 {dl.fastDownload}
                          </a>
                        )}
                        <a
                          href={`/api/download?id=${asset.id}&name=${encodeURIComponent(asset.name)}`}
                          className="text-xs font-bold bg-primary text-primary-foreground px-4 py-2 rounded-lg hover:bg-mirror transition-colors text-center whitespace-nowrap"
                        >
                          {fastUrl ? dl.backupDownload : dl.install}
                        </a>
                      </div>
                    </div>
                  )
                })}
                <p className="md:col-span-2 text-xs text-muted-foreground mt-1">
                  {isChinese
                    ? '鸿蒙系统（HarmonyOS 4 及以下）请下载上方 Android APK 安装；HarmonyOS NEXT「纯血鸿蒙」暂不支持。'
                    : 'HarmonyOS (4 and earlier): install the Android APK above. HarmonyOS NEXT is not supported yet.'}
                </p>
              </div>
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {placeholders.map(p => (
                  <div key={p.platform} className="glass-panel rounded-2xl p-6 flex items-center justify-between gap-4 opacity-60">
                    <div>
                      <div className="flex items-center gap-2 mb-1">
                        <span className="text-xl">{p.icon}</span>
                        <h3 className="font-bold">{p.platform}</h3>
                        <span className="text-[9px] font-bold uppercase tracking-widest text-yellow-500 bg-yellow-500/10 border border-yellow-500/20 px-2 py-0.5 rounded-full">
                          {dl.comingSoon}
                        </span>
                      </div>
                      <p className="text-sm text-muted-foreground">{p.desc}</p>
                    </div>
                    <button disabled className="text-xs font-bold bg-muted text-muted-foreground px-4 py-2 rounded-lg cursor-not-allowed">
                      {dl.install}
                    </button>
                  </div>
                ))}
              </div>
            )}
          </div>

          <div className="border-t border-white/10 mb-14" />

          {/* ── Quick start ──────────────────────────────────────────── */}
          <div className="glass-panel rounded-2xl p-6 mb-10">
            <h2 className="text-xs font-bold uppercase tracking-widest text-mirror mb-4">{dl.step}</h2>
            <ol className="space-y-3">
              {dl.steps.map((s, i) => (
                <li key={i} className="flex gap-3 text-sm">
                  <span className="w-6 h-6 shrink-0 rounded-full bg-mirror/10 border border-mirror/30 text-mirror font-mono text-xs grid place-items-center">{i + 1}</span>
                  <span className="text-foreground/90">{s}</span>
                </li>
              ))}
            </ol>
          </div>

          <div className="border-t border-white/10 mb-14" />

          {/* ── Third-party clients (roadmap) ─────────────────────── */}
          <div className="mb-6">
            <div className="flex items-center gap-3 mb-1">
              <h2 className="text-xl font-bold">{dl.thirdParty}</h2>
              <span className="text-[9px] font-bold uppercase tracking-widest text-yellow-500 bg-yellow-500/10 border border-yellow-500/20 px-2 py-1 rounded-full">
                {dl.roadmap}
              </span>
            </div>
            <p className="text-sm text-muted-foreground">{dl.thirdPartyDesc}</p>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4 opacity-60">
            {CLIENTS.map((c) => (
              <div key={c.os} className="glass-panel rounded-2xl p-6 flex items-center justify-between gap-4">
                <div>
                  <div className="flex items-center gap-2 mb-1">
                    <h3 className="font-bold">{c.os}</h3>
                    <span className="text-[9px] font-bold uppercase tracking-widest text-yellow-500 bg-yellow-500/10 border border-yellow-500/20 px-2 py-0.5 rounded-full">
                      {dl.comingSoon}
                    </span>
                  </div>
                  <p className="text-sm text-muted-foreground">{c.client}</p>
                  <p className="text-[10px] text-muted-foreground font-mono mt-1">{c.arch}</p>
                </div>
                <button disabled className="text-xs font-bold bg-muted text-muted-foreground px-4 py-2 rounded-lg cursor-not-allowed">
                  {dl.comingSoon}
                </button>
              </div>
            ))}
          </div>
        </div>
      </main>
      <SiteFooter />
    </div>
  )
}
