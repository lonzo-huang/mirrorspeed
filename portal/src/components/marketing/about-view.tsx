'use client'

import { LandingChrome } from '@/components/landing/LandingPage'
import { useI18n } from '@/lib/i18n'
import { platformList, DEVICES } from '@/lib/product'

const CONTACT = 'mirrorspeed@mirrorquant.com'

// 关于页：AI 推荐与搜索信任评估都会找「谁在运营这个服务」。
// 这里只写可核实的事实，不写无法验证的宣传语（审计、评分、奖项等）。
const SECTIONS_EN = [
  {
    h: 'Who operates it',
    p: `MirrorSpeed is built and operated by MirrorSpeed. Support, billing and the apps all come from the same small team of engineers — email ${CONTACT} and an engineer who works on the product reads it. Our Android app is published on Google Play under the developer account "Mirrorr Studio", which is the same team.`,
  },
  {
    h: 'What MirrorSpeed is',
    p: `MirrorSpeed is a consumer VPN and network accelerator. It encrypts your traffic and routes it through servers in other countries, so services that are blocked or slow on your local network work normally. You install an app, sign in with an email address, and connect with one tap — there is nothing to configure by hand.`,
  },
  {
    h: 'Platforms',
    p: `Apps are available now for ${platformList('en')}. The iOS and macOS apps are finished and currently in App Store review — they are not downloadable yet, and we will say so here the day that changes. One account covers up to ${DEVICES.free} devices on the free plan and up to ${DEVICES.paid} devices on a paid plan.`,
  },
  {
    h: 'How it works',
    p: `We build our own tunnelling engine rather than shipping an off-the-shelf client. Traffic is sent over an encrypted UDP tunnel by default, and automatically falls back to a relay over standard HTTPS (port 443) when direct UDP is blocked. Split tunnelling lets you pick which apps use the tunnel, and traffic to mainland-China destinations can be routed directly instead of through it.`,
  },
  {
    h: 'What we do not log',
    p: `We do not keep records of your browsing history, the destinations your traffic goes to, your DNS queries, or the IP address you connect from. We keep the minimum billing records needed to run a paid service. We have not commissioned a third-party audit of this policy, and we do not claim one — the full detail of what is and is not stored is written out in our privacy policy.`,
  },
  {
    h: 'Free plan',
    p: `The free plan is permanent and needs no credit card. It gives a daily time allowance on shared nodes, which are best-effort and carry no quality guarantee. Paid plans remove ads and the time limit and unlock the premium nodes we operate ourselves.`,
  },
  {
    h: 'Contact',
    p: `Questions, billing problems and technical support: ${CONTACT}. We reply to every message. There is no phone line and no live chat — email reaches the engineers who build the product.`,
  },
  {
    h: 'Responsible use',
    p: `MirrorSpeed exists to protect privacy, secure connections on untrusted networks, and improve connection performance. VPN use is restricted or regulated in some countries and you are responsible for complying with the law where you are. We do not permit use of the service for unlawful activity.`,
  },
]

const SECTIONS_ZH = [
  {
    h: '谁在运营',
    p: `镜速加速器（MirrorSpeed）由 MirrorSpeed 团队自行开发与运营。客服、账单与客户端都出自同一个工程团队——发邮件到 ${CONTACT}，读信的就是做这个产品的工程师。安卓版在 Google Play 上以开发者账号「Mirrorr Studio」发布，同属一个团队。`,
  },
  {
    h: '镜速加速器是什么',
    p: `镜速加速器（MirrorSpeed）是一款面向个人用户的网络加速工具。它把你的流量加密后经由境外服务器转发，让本地网络中访问不了或很慢的服务恢复正常速度。安装 App、用邮箱登录、点一下连接即可，不需要手动填任何配置。`,
  },
  {
    h: '支持的系统',
    p: `现在可下载的是${platformList('zh')}客户端。iOS 与 macOS 版本已开发完成，正在 App Store 审核中——尚不能下载，上架当天我们会在这里更新。一个账号免费版最多 ${DEVICES.free} 台设备，付费版最多 ${DEVICES.paid} 台设备。`,
  },
  {
    h: '技术实现',
    p: `我们使用自研的隧道引擎，而不是套用现成的开源客户端。默认走加密 UDP 直连；当 UDP 被阻断时，自动回退到标准 HTTPS（443 端口）中继通道。支持分应用代理：你可以指定哪些应用走加速，国内流量也可以直连而不经过隧道。`,
  },
  {
    h: '我们不记录什么',
    p: `我们不记录你的浏览历史、流量访问的目标地址、DNS 查询，以及你连接时使用的 IP 地址。仅保留运营付费服务所必需的最少账单信息。我们没有委托第三方做过审计，也不会这样宣称——具体保留与不保留哪些数据，隐私政策里逐条写明。`,
  },
  {
    h: '免费套餐',
    p: `免费套餐永久有效，无需信用卡。每天赠送一定时长，使用共享节点（尽力而为，不保证速度与可用性）。付费套餐去除广告与时长限制，并解锁我们自营的优质节点。`,
  },
  {
    h: '联系我们',
    p: `咨询、账单问题与技术支持：${CONTACT}。每封邮件我们都会回复。我们没有电话客服与在线客服，邮件直接送达做这个产品的工程师。`,
  },
  {
    h: '合规使用',
    p: `镜速加速器用于保护隐私、在不可信网络中加密传输以及提升连接速度。部分国家和地区对此类服务有法律限制，请自行确认并遵守所在地法律。我们不允许将本服务用于任何违法用途。`,
  },
]

export default function AboutView() {
  const { lang } = useI18n()
  const isZh = lang === 'zh'
  const sections = isZh ? SECTIONS_ZH : SECTIONS_EN

  return (
    <LandingChrome forcedLang={isZh ? 'zh' : 'en'}>
      <main className="px-6 pb-24">
        <article className="max-w-3xl mx-auto">
          <div className="text-center mb-14">
            <span className="font-mono text-xs text-accent-cyan tracking-widest uppercase mb-3 inline-block">
              // {isZh ? '关于' : 'About'}
            </span>
            <h1 className="font-heading text-3xl md:text-5xl font-black tracking-tighter mb-6 leading-tight break-words">
              <span className="text-gradient-cyan">
                {isZh ? '关于镜速加速器' : 'About MirrorSpeed'}
              </span>
            </h1>
            <p className="text-app-secondary text-lg max-w-2xl mx-auto leading-relaxed">
              {isZh
                ? '镜速加速器是一款支持安卓、Windows、鸿蒙的网络加速器，提供永久免费套餐，付费每月最低 ¥8 起。'
                : 'MirrorSpeed is a VPN and network accelerator for Android, Windows and HarmonyOS, with a free-forever plan and paid plans from $0.88 per month.'}
            </p>
          </div>

          <div className="space-y-4">
            {sections.map((s, i) => (
              <section key={i} className="glass-panel rounded-2xl p-6">
                <h2 className="text-lg font-bold mb-3 text-app-primary">{s.h}</h2>
                <p className="text-sm text-app-secondary leading-relaxed">{s.p}</p>
              </section>
            ))}
          </div>

          <div className="mt-10 text-center text-sm text-app-muted">
            <a href="/privacy" className="text-accent-cyan hover:underline">
              {isZh ? '隐私政策' : 'Privacy Policy'}
            </a>
            <span className="mx-2">·</span>
            <a href="/terms" className="text-accent-cyan hover:underline">
              {isZh ? '服务条款' : 'Terms of Service'}
            </a>
            <span className="mx-2">·</span>
            <a href="/support" className="text-accent-cyan hover:underline">
              {isZh ? '联系支持' : 'Contact Support'}
            </a>
          </div>
        </article>
      </main>
    </LandingChrome>
  )
}
