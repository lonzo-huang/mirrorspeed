'use client'

import { useEffect, useState } from 'react'
import Link from 'next/link'
import {
  Shield, Zap, Wifi, UserPlus, Gift, BarChart2,
  ChevronDown, ArrowRight, Star, Download,
} from 'lucide-react'
import { SiteFooter } from '@/components/site/SiteFooter'
import type { LatestRelease } from '@/app/api/releases/latest/route'

// ── 简化导航（纯中文，无语言切换）────────────────────────────
function CnNav() {
  const [open, setOpen] = useState(false)
  return (
    <nav className="sticky top-0 z-50 glass-panel border-b border-border">
      <div className="py-3 px-6 flex items-center justify-between">
        <Link href="/cn" className="text-lg font-extrabold tracking-tighter">
          镜速加速器
        </Link>
        <div className="hidden md:flex items-center gap-6 text-sm font-medium text-muted-foreground">
          <a href="#features"  className="hover:text-foreground transition-colors">功能特点</a>
          <a href="#pricing"   className="hover:text-foreground transition-colors">价格方案</a>
          <a href="#download"  className="hover:text-foreground transition-colors">下载</a>
          <a href="#faq"       className="hover:text-foreground transition-colors">常见问题</a>
        </div>
        <div className="flex items-center gap-3">
          <Link href="/login" className="hidden md:block text-sm text-muted-foreground hover:text-foreground transition-colors">登录</Link>
          <Link href="/login" className="text-sm font-semibold bg-primary text-primary-foreground px-4 py-2 rounded-full hover:bg-mirror transition-all">
            免费注册
          </Link>
        </div>
      </div>
    </nav>
  )
}

// ── 统计数字 ──────────────────────────────────────────────────
const STATS = [
  { value: '10ms', label: '香港节点延迟' },
  { value: '45+',  label: '全球节点' },
  { value: '500MB', label: '每日免费额度' },
  { value: '99.9%', label: '服务可用率' },
]

// ── 功能亮点 ──────────────────────────────────────────────────
const FEATURES = [
  {
    Icon: Zap,
    title: '智能分流路由',
    desc: '中国大陆 IP 直连，境外流量走 VPN，两全其美——国内速度不打折，境外内容随时访问。',
  },
  {
    Icon: Shield,
    title: 'WireGuard 加密',
    desc: '新一代 WireGuard 协议，比传统 OpenVPN 快 3 倍，加密强度全球顶级，代码量极小、安全性极高。',
  },
  {
    Icon: Wifi,
    title: 'WebSocket 中继',
    desc: '在网络管控严格的环境下，可自动切换 WebSocket 中继通道，确保连接稳定可用。',
  },
  {
    Icon: BarChart2,
    title: '每日免费流量',
    desc: '免费用户每天享有 500 MB 流量额度，充足应对日常轻度使用。付费用户无限制。',
  },
  {
    Icon: UserPlus,
    title: '多设备支持',
    desc: '一个账户同时支持 Android 手机、Windows 电脑，随时随地接入，设备无忧。',
  },
  {
    Icon: Gift,
    title: '邀请好友得会员',
    desc: '邀请好友订阅即可延长您的会员时长：对方购买月付延长 3 天，年付延长 30 天，两年付延长 60 天。',
  },
]

// ── 使用步骤 ──────────────────────────────────────────────────
const STEPS = [
  { title: '下载 APP',    desc: '扫码或点击按钮，下载镜速加速器安装包（Android APK）。' },
  { title: '邮箱注册',   desc: '输入邮箱地址，收取一次性验证码，无需密码，10 秒完成注册。' },
  { title: '一键连接',   desc: '选择节点，轻点连接按钮，智能模式自动处理分流，秒速上线。' },
]

// ── 套餐方案 ──────────────────────────────────────────────────
const PLANS = [
  {
    name: '免费',
    price: '¥0',
    per: '/月',
    highlight: false,
    badge: null,
    feats: ['每日 500 MB 流量', '全部节点可用', '1 台设备', '智能分流路由'],
    cta: '立即注册',
    href: '/login',
  },
  {
    name: '年付',
    price: '¥8',
    per: '/月',
    sub: '按年付 ¥96',
    highlight: true,
    badge: '最受欢迎 · 省 67%',
    feats: ['无限流量', '全部 45+ 节点', '不限设备数', '智能分流路由', 'WebSocket 中继', '7 天无理由退款'],
    cta: '立即开通',
    href: '/login',
  },
  {
    name: '月付',
    price: '¥24',
    per: '/月',
    highlight: false,
    badge: null,
    feats: ['无限流量', '全部 45+ 节点', '不限设备数', '智能分流路由', 'WebSocket 中继'],
    cta: '立即开通',
    href: '/login',
  },
]

// ── FAQ ───────────────────────────────────────────────────────
const FAQ = [
  { q: '是否需要科学知识才能安装？', a: '不需要。直接下载 APK 安装，打开 APP 注册邮箱，点连接即可，完全傻瓜式操作。' },
  { q: '智能模式和全局模式有什么区别？', a: '智能模式：国内网站直连（速度快），境外网站经过 VPN（可访问）。全局模式：所有流量走 VPN，适合需要完全匿名的场景。' },
  { q: '免费用户每天 500 MB 够用吗？', a: '日常轻度使用（刷推特、访问 Google、GitHub）完全够用。如果需要看视频或大量下载，建议升级付费方案。' },
  { q: '会不会封号？账号安全吗？', a: '登录仅需邮箱，无需手机号、无需实名，数据零日志，账号与真实身份无关联。' },
  { q: '安卓 APK 怎么安装？', a: '下载后打开文件，系统会提示"允许安装未知来源应用"，点允许后即可正常安装。iOS 版本正在开发中。' },
  { q: '邀请奖励怎么计算？', a: '受邀人首次订阅时奖励发放：月付 +3 天、季付 +10 天、年付 +30 天、两年付 +60 天。奖励叠加计入您的会员到期时间。' },
]

// ── 用户评价 ──────────────────────────────────────────────────
const REVIEWS = [
  { name: '小王',   role: '深圳 · 程序员',   body: '智能分流真的很实用，国内银行、支付宝不受影响，GitHub 又能正常访问，两全其美。' },
  { name: '阿梅',   role: '广州 · 设计师',   body: '注册超简单，邮箱验证就行，5 分钟搞定，延迟十几毫秒连香港，刷 YouTube 无压力。' },
  { name: '老李头', role: '上海 · 中小企业主', body: '价格比其他机场便宜很多，年付 96 块，关键是稳，没出现过大规模故障。' },
]

// ── 下载区组件 ────────────────────────────────────────────────
function DownloadSection() {
  const [release, setRelease] = useState<LatestRelease | null>(null)

  useEffect(() => {
    fetch('/api/releases/latest', { cache: 'no-store' })
      .then(r => r.json())
      .then(d => setRelease(d.version ? d : null))
      .catch(() => {})
  }, [])

  // 找 CN APK：优先找文件名含 JinSu 的 asset
  const cnAsset = release?.assets.find(a => a.name.toLowerCase().includes('jinsu'))
  // CN 镜像下载地址
  const cnMirrorUrl = release?.cn_apk_cn_url

  return (
    <div id="download" className="py-24 px-6 bg-white/[0.01]">
      <div className="max-w-3xl mx-auto text-center">
        <h2 className="text-4xl font-bold tracking-tight mb-3">下载镜速加速器</h2>
        <p className="text-muted-foreground mb-10">目前支持 Android；iOS 版本即将推出</p>

        <div className="glass-panel rounded-3xl p-8 flex flex-col md:flex-row items-center gap-6 text-left">
          {/* 图标 + 信息 */}
          <div className="flex-1">
            <div className="flex items-center gap-3 mb-3">
              <span className="text-4xl">🤖</span>
              <div>
                <h3 className="font-bold text-lg">Android APK</h3>
                <p className="text-sm text-muted-foreground">
                  {cnAsset
                    ? `${cnAsset.name} · ${(cnAsset.size / 1024 / 1024).toFixed(1)} MB`
                    : '镜速加速器 · arm64-v8a'}
                </p>
              </div>
            </div>
            <p className="text-sm text-muted-foreground">
              下载后打开 APK 文件，允许安装未知来源，完成安装后注册邮箱即可使用。
            </p>
          </div>

          {/* 下载按钮 */}
          <div className="flex flex-col gap-3 shrink-0 w-full md:w-auto">
            {cnMirrorUrl && (
              <a
                href={cnMirrorUrl}
                className="flex items-center justify-center gap-2 px-6 py-3 bg-red-500 hover:bg-red-400 text-white font-bold rounded-xl transition-colors"
              >
                <Download className="w-4 h-4" />
                🇨🇳 国内高速下载
              </a>
            )}
            {cnAsset && (
              <a
                href={`/api/download?id=${cnAsset.id}&name=${encodeURIComponent(cnAsset.name)}`}
                className="flex items-center justify-center gap-2 px-6 py-3 bg-primary text-primary-foreground font-bold rounded-xl hover:bg-mirror transition-colors"
              >
                <Download className="w-4 h-4" />
                {cnMirrorUrl ? '备用下载' : '立即下载'}
              </a>
            )}
            {!cnAsset && !cnMirrorUrl && (
              <div className="px-6 py-3 bg-white/5 border border-white/10 text-muted-foreground rounded-xl text-sm text-center">
                即将发布…
              </div>
            )}
          </div>
        </div>

        <p className="mt-5 text-xs text-muted-foreground">
          遇到下载问题？请发邮件至{' '}
          <a href="mailto:support@mirrorspeed.com" className="text-mirror hover:underline">
            support@mirrorspeed.com
          </a>
        </p>
      </div>
    </div>
  )
}

// ── 主页面 ────────────────────────────────────────────────────
export default function CnPage() {
  return (
    <div className="min-h-screen bg-background text-foreground">
      <CnNav />

      {/* ── Hero ── */}
      <header className="relative pt-24 pb-20 px-6 overflow-hidden">
        <div
          className="absolute inset-0 -z-20 opacity-20"
          style={{
            backgroundImage: 'radial-gradient(circle, rgba(255,255,255,0.15) 1px, transparent 1px)',
            backgroundSize: '32px 32px',
          }}
        />
        <div
          className="absolute inset-0 -z-10 opacity-40"
          style={{
            background: 'radial-gradient(ellipse at top, color-mix(in oklab, var(--color-mirror) 30%, transparent), transparent 65%)',
          }}
        />

        <div className="max-w-5xl mx-auto text-center">
          {/* 徽章 */}
          <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-mirror/10 border border-mirror/20 text-mirror text-[11px] font-bold tracking-widest uppercase mb-8">
            <span className="relative flex h-2 w-2">
              <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-mirror opacity-75" />
              <span className="relative inline-flex rounded-full h-2 w-2 bg-mirror" />
            </span>
            全球节点实时在线
          </div>

          {/* 主标题 */}
          <h1 className="text-6xl md:text-8xl font-extrabold tracking-tighter mb-6 leading-none">
            智能穿越{' '}
            <span className="text-shimmer">国内直连</span>
          </h1>
          <p className="text-xl text-muted-foreground max-w-2xl mx-auto mb-4">
            镜速加速器 — 专为国内用户设计的 VPN 工具。<br />
            中国 IP 直连，境外流量加速，鱼和熊掌兼得。
          </p>
          <p className="text-sm text-muted-foreground/70 mb-10">
            免费用户每日 500 MB · 无需信用卡 · 邮箱注册即用
          </p>

          {/* CTA */}
          <div className="flex flex-col md:flex-row gap-4 justify-center items-center mb-6">
            <a
              href="#download"
              className="group w-full md:w-auto flex items-center justify-center gap-2 px-8 py-4 bg-primary text-primary-foreground font-bold rounded-xl hover:shadow-[0_0_40px_color-mix(in_oklab,var(--color-mirror)_50%,transparent)] transition-all"
            >
              <Download className="w-4 h-4" />
              下载 Android APP
              <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition-transform" />
            </a>
            <Link
              href="/login"
              className="w-full md:w-auto px-8 py-4 glass-panel font-bold rounded-xl hover:bg-white/10 transition-all"
            >
              免费注册账号
            </Link>
          </div>

          {/* 用户信任 */}
          <p className="text-xs text-muted-foreground mb-14 flex items-center justify-center gap-1.5">
            <span className="flex">
              {[1, 2, 3, 4, 5].map(s => (
                <Star key={s} className="w-3 h-3 fill-mirror text-mirror" />
              ))}
            </span>
            已有数万用户每天使用，节点稳定
          </p>

          {/* 数据展示 */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4 max-w-3xl mx-auto">
            {STATS.map(s => (
              <div key={s.label} className="glass-panel p-4 rounded-2xl text-center">
                <div className="text-2xl font-bold font-mono text-mirror mb-1">{s.value}</div>
                <div className="text-[10px] text-muted-foreground uppercase tracking-wider font-mono">{s.label}</div>
              </div>
            ))}
          </div>
        </div>
      </header>

      {/* ── 使用步骤 ── */}
      <section className="py-24 px-6 border-y border-border bg-white/[0.02]">
        <div className="max-w-5xl mx-auto">
          <div className="text-center mb-14">
            <h2 className="text-4xl font-bold tracking-tight mb-3">三步搞定，60 秒上线</h2>
            <p className="text-muted-foreground">无需配置，傻瓜式操作</p>
          </div>
          <div className="grid md:grid-cols-3 gap-6 relative">
            <div className="hidden md:block absolute top-10 left-[calc(16.67%+1.5rem)] right-[calc(16.67%+1.5rem)] h-px border-t border-dashed border-mirror/30" />
            {STEPS.map((step, i) => {
              const Icon = [Download, UserPlus, Wifi][i]
              return (
                <div key={i} className="glass-panel p-8 rounded-2xl text-center relative">
                  <div className="inline-flex items-center justify-center w-14 h-14 rounded-2xl bg-mirror/10 border border-mirror/20 mb-5 mx-auto relative">
                    <Icon className="w-6 h-6 text-mirror" />
                    <span className="absolute -top-2 -right-2 w-5 h-5 rounded-full bg-mirror text-background text-[10px] font-black grid place-items-center">
                      {i + 1}
                    </span>
                  </div>
                  <h3 className="font-bold text-lg mb-2">{step.title}</h3>
                  <p className="text-sm text-muted-foreground">{step.desc}</p>
                </div>
              )
            })}
          </div>
        </div>
      </section>

      {/* ── 功能特点 ── */}
      <section id="features" className="py-24 px-6">
        <div className="max-w-6xl mx-auto">
          <div className="text-center mb-14">
            <h2 className="text-4xl font-bold tracking-tight mb-3">为国内用户专门优化</h2>
            <p className="text-muted-foreground">不是简单地把所有流量走 VPN，而是真正理解中国网络环境</p>
          </div>
          <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-4">
            {FEATURES.map(({ Icon, title, desc }, i) => (
              <div key={i} className="glass-panel p-6 rounded-2xl group hover:border-mirror/30 transition-colors">
                <div className="w-11 h-11 rounded-xl bg-mirror/10 border border-mirror/20 mb-4 grid place-items-center text-mirror group-hover:bg-mirror/15 transition-colors">
                  <Icon className="w-5 h-5" />
                </div>
                <h3 className="font-bold mb-2">{title}</h3>
                <p className="text-sm text-muted-foreground">{desc}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ── 用户评价 ── */}
      <section className="py-24 px-6 bg-white/[0.01]">
        <div className="max-w-5xl mx-auto">
          <div className="text-center mb-14">
            <h2 className="text-4xl font-bold tracking-tight mb-3">用户怎么说</h2>
            <p className="text-muted-foreground">真实用户，真实体验</p>
          </div>
          <div className="grid md:grid-cols-3 gap-6">
            {REVIEWS.map((item, i) => (
              <div key={i} className="glass-panel p-7 rounded-2xl flex flex-col">
                <div className="flex mb-4">
                  {[1, 2, 3, 4, 5].map(s => (
                    <Star key={s} className="w-4 h-4 fill-mirror text-mirror" />
                  ))}
                </div>
                <blockquote className="text-sm text-foreground/80 leading-relaxed flex-grow mb-6">
                  &ldquo;{item.body}&rdquo;
                </blockquote>
                <div className="flex items-center gap-3">
                  <div className="w-9 h-9 rounded-full bg-mirror/20 border border-mirror/30 grid place-items-center text-mirror font-bold text-sm">
                    {item.name[0]}
                  </div>
                  <div>
                    <p className="text-sm font-semibold">{item.name}</p>
                    <p className="text-[11px] text-muted-foreground">{item.role}</p>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ── 价格方案 ── */}
      <section id="pricing" className="py-24 px-6">
        <div className="max-w-5xl mx-auto">
          <div className="text-center mb-14">
            <h2 className="text-4xl font-bold tracking-tight mb-3">透明定价，随时取消</h2>
            <p className="text-muted-foreground">免费永久可用 · 付费解锁无限流量</p>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            {PLANS.map((p, i) => (
              <div
                key={i}
                className={`glass-panel p-8 rounded-3xl flex flex-col relative ${
                  p.highlight
                    ? 'border-mirror shadow-[0_0_40px_color-mix(in_oklab,var(--color-mirror)_10%,transparent)]'
                    : ''
                }`}
              >
                {p.badge && (
                  <div className="absolute -top-3 left-1/2 -translate-x-1/2 bg-mirror text-background text-[10px] font-black uppercase tracking-tighter px-4 py-1 rounded-full whitespace-nowrap">
                    {p.badge}
                  </div>
                )}
                <span className="text-sm text-muted-foreground mb-2">{p.name}</span>
                <div className="flex items-baseline gap-1 mb-1">
                  <span className={`text-4xl font-bold ${p.highlight ? 'text-mirror' : ''}`}>{p.price}</span>
                  <span className="text-muted-foreground">{p.per}</span>
                </div>
                {p.sub && <p className="text-[11px] text-mirror/70 mb-5">{p.sub}</p>}
                {!p.sub && <div className="mb-6" />}
                <ul className="space-y-3 text-sm text-foreground/80 mb-10 flex-grow">
                  {p.feats.map((f, j) => (
                    <li key={j} className="flex items-center gap-2.5">
                      <span className="w-4 h-4 rounded-full bg-mirror/10 border border-mirror/30 flex items-center justify-center flex-shrink-0">
                        <span className="w-1.5 h-1.5 bg-mirror rounded-full" />
                      </span>
                      {f}
                    </li>
                  ))}
                </ul>
                <Link
                  href={p.href}
                  className={`w-full py-3 text-center font-bold rounded-xl transition-all block ${
                    p.highlight
                      ? 'bg-primary text-primary-foreground hover:shadow-[0_0_20px_color-mix(in_oklab,var(--color-mirror)_40%,transparent)]'
                      : 'border border-white/20 hover:bg-white/5'
                  }`}
                >
                  {p.cta}
                </Link>
              </div>
            ))}
          </div>
          <p className="text-center mt-8 text-sm text-muted-foreground flex items-center justify-center gap-2">
            <Shield className="w-4 h-4 text-mirror" />
            付费方案均享 7 天无理由退款
          </p>
        </div>
      </section>

      {/* ── 下载区 ── */}
      <DownloadSection />

      {/* ── CTA Banner ── */}
      <section
        className="py-20 px-6 mx-6 mb-6 rounded-3xl relative overflow-hidden"
        style={{
          background: 'radial-gradient(ellipse at center, color-mix(in oklab, var(--color-mirror) 15%, transparent), transparent 70%), color-mix(in oklab, var(--color-foreground) 4%, transparent)',
          border: '1px solid color-mix(in oklab, var(--color-mirror) 20%, transparent)',
        }}
      >
        <div
          className="absolute inset-0 -z-10 opacity-10"
          style={{
            backgroundImage: 'radial-gradient(circle, rgba(255,255,255,0.4) 1px, transparent 1px)',
            backgroundSize: '24px 24px',
          }}
        />
        <div className="max-w-2xl mx-auto text-center">
          <h2 className="text-4xl md:text-5xl font-extrabold tracking-tight mb-4 text-shimmer">
            现在就开始
          </h2>
          <p className="text-muted-foreground mb-8 text-lg">
            免费用户无需信用卡，每天 500 MB 永久可用
          </p>
          <div className="flex flex-col sm:flex-row gap-4 justify-center">
            <a
              href="#download"
              className="group inline-flex items-center justify-center gap-2 px-8 py-4 bg-primary text-primary-foreground font-bold rounded-xl hover:shadow-[0_0_40px_color-mix(in_oklab,var(--color-mirror)_50%,transparent)] transition-all"
            >
              <Download className="w-5 h-5" />
              下载 APP
              <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition-transform" />
            </a>
            <Link
              href="/login"
              className="inline-flex items-center justify-center gap-2 px-8 py-4 glass-panel font-bold rounded-xl hover:bg-white/10 transition-all"
            >
              直接注册账号
            </Link>
          </div>
        </div>
      </section>

      {/* ── FAQ ── */}
      <section id="faq" className="py-24 px-6">
        <div className="max-w-3xl mx-auto">
          <h2 className="text-4xl font-bold tracking-tight mb-12 text-center">常见问题</h2>
          <div className="space-y-3">
            {FAQ.map((item, i) => (
              <details key={i} className="glass-panel rounded-2xl p-6 group">
                <summary className="cursor-pointer font-semibold flex justify-between items-center list-none">
                  {item.q}
                  <span className="text-mirror text-xl group-open:rotate-45 transition-transform flex-shrink-0 ml-4">+</span>
                </summary>
                <p className="mt-4 text-sm text-muted-foreground leading-relaxed">{item.a}</p>
              </details>
            ))}
          </div>
        </div>
      </section>

      {/* 底部切换到国际版的提示 */}
      <div className="text-center py-6 text-xs text-muted-foreground border-t border-white/5">
        寻找国际版？访问{' '}
        <Link href="/" className="text-mirror hover:underline">
          www.mirrorspeed.com
        </Link>
        {' '}（English）
      </div>

      <SiteFooter />
    </div>
  )
}
