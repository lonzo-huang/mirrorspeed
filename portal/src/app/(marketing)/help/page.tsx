'use client'

import Link from 'next/link'
import { LandingChrome } from '@/components/landing/LandingPage'
import { useI18n }    from '@/lib/i18n'

const SUPPORT_URL = 'https://mirrorspeed.com/support'

// 把答案里的 URL 渲染成可点击链接。
const linkify = (text: string) =>
  text.split(/(https?:\/\/[^\s]+)/g).map((part, i) =>
    /^https?:\/\//.test(part)
      ? <a key={i} href={part} className="text-accent-cyan hover:underline break-all">{part}</a>
      : part
  )

const FAQ_EN = [
  { h: "How do I connect?", p: "Open the app and tap the big power button on the home screen. By default \"Auto select\" picks the fastest, least-busy node for you. Once it turns green you are connected and your traffic is protected." },
  { h: "How do I choose a specific node?", p: "Tap the node card (or \"Select node\") on the home screen. Each node shows its latency and a load indicator (Idle / Busy / Full). Tap any node to switch to it; your choice is remembered." },
  { h: "What is the free trial?", p: "Free users get a daily allowance of connection time that resets every day. While connected the timer counts down; when it reaches zero the VPN disconnects automatically. Upgrade to a membership for unlimited, ad-free use." },
  { h: "How do I get more free time?", p: "When your daily time runs out, tap \"Watch ads\". A short series of ads plays back-to-back; after about 50 seconds of viewing you are granted extra free minutes. Members never see ads or limits." },
  { h: "How do I sign in?", p: "On the login screen you can use a one-time email code, an email + password, or your Google account — switch between them using the tabs at the top." },
  { h: "Smart vs Global routing", p: "Smart mode keeps mainland-China traffic direct and only sends overseas traffic through the VPN, for the best speed. Global mode sends all traffic through the VPN. You can switch on the home screen." },
  { h: "It connected but websites won't load", p: "Tap disconnect and reconnect, or switch to a different node from the node list. If a node shows \"timeout\", pick another one. Make sure your underlying internet connection works first." },
  { h: "How do I upgrade / manage my subscription?", p: "Open \"My\" → membership, or visit your billing dashboard. Members get unlimited time, no ads, and priority nodes." },
  { h: "Contact support", p: `Still stuck? Submit a request at ${SUPPORT_URL} and we'll help as soon as possible.` },
]

const FAQ_ZH = [
  { h: "如何连接？", p: "打开 App，点主页中间的大电源按钮即可。默认的「智能选择」会自动为你接入延迟最低、最空闲的节点。按钮变绿即表示已连接，流量已受保护。" },
  { h: "如何选择指定节点？", p: "点主页上的节点卡片（或「选择节点」）。每个节点都会显示延迟和负载状态（空闲 / 适中 / 繁忙）。点任意节点即可切换，选择会被记住。" },
  { h: "免费试用是什么？", p: "免费用户每天有一定的连接时长额度，每天自动重置。连接时倒计时递减，归零后会自动断开。开通会员可无限制、无广告使用。" },
  { h: "如何获得更多免费时长？", p: "当日时长用完后，点「看广告解锁」。系统会连续播放几段广告，累计观看约 50 秒后即可获得额外免费分钟数。会员不会看到广告，也没有时长限制。" },
  { h: "如何登录？", p: "在登录页可使用邮箱验证码、邮箱 + 密码，或 Google 账号登录——用顶部的标签切换登录方式即可。" },
  { h: "智能模式与全局模式", p: "智能模式让中国大陆的流量直连，仅将境外流量走 VPN，速度最佳；全局模式则把所有流量都走 VPN。可在主页切换。" },
  { h: "连上了但网页打不开", p: "先断开再重连，或在节点列表里换一个节点。若某节点显示「超时」，请换其他节点。也请先确认你本身的网络是通的。" },
  { h: "如何升级 / 管理订阅？", p: "进入「我的」→ 会员，或打开账单中心。会员享无限时长、无广告及优先节点。" },
  { h: "联系客服", p: `仍未解决？请通过 ${SUPPORT_URL} 提交求助，我们会尽快协助你。` },
]

export default function HelpPage() {
  const { lang } = useI18n()
  const isZh = lang === 'zh'
  const FAQ = isZh ? FAQ_ZH : FAQ_EN

  return (
    <LandingChrome forcedLang={isZh ? 'zh' : 'en'}>
      <main className="px-6 pb-24">
        <article className="max-w-3xl mx-auto">
          <div className="text-center mb-14">
            <span className="font-mono text-xs text-accent-cyan tracking-widest uppercase mb-3 inline-block">
              // {isZh ? '帮助' : 'Help'}
            </span>
            <h1 className="font-heading text-4xl md:text-6xl font-black tracking-tighter mb-6">
              <span className="text-gradient-cyan">{isZh ? '使用帮助' : 'Help & FAQ'}</span>
            </h1>
            <p className="text-app-secondary text-lg max-w-2xl mx-auto">
              {isZh
                ? '关于连接、节点选择、免费时长与会员的常见问题。如未解答，欢迎联系我们。'
                : 'Common questions about connecting, choosing nodes, free time, and membership. If something is not covered, reach out to us.'}
            </p>
          </div>
          {isZh && (
            <Link href="/tutorials" className="glass-panel rounded-2xl p-5 mb-6 flex items-center justify-between hover:bg-app-tertiary transition-colors">
              <span className="text-sm text-app-primary font-medium">📘 图文使用教程：安装、连接与常见问题排查</span>
              <span className="text-sm text-accent-cyan">查看教程 →</span>
            </Link>
          )}
          <div className="space-y-4">
            {FAQ.map((s, i) => (
              <section key={i} className="glass-panel rounded-2xl p-6">
                <h2 className="text-lg font-bold mb-3 text-app-primary">{s.h}</h2>
                <p className="text-sm text-app-secondary leading-relaxed">{linkify(s.p)}</p>
              </section>
            ))}
          </div>
        </article>
      </main>
    </LandingChrome>
  )
}
