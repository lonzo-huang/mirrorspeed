/**
 * GET /llms.txt — 给 AI 检索用的事实清单。
 *
 * 做成路由而不是 public/ 里的静态文件：平台可用性、价格、设备数都来自
 * lib/product.ts。写成静态文件的话，iOS 上架那天得记得手动改这里，迟早会忘，
 * 又变回「站内信息互相矛盾」。现在改 product.ts 一处，这里自动跟着变。
 *
 * 格式遵循 llmstxt.org 规范：
 *   H1 项目名 → 引用块一句话摘要 → 正文细节 → H2 分节的「Markdown 链接清单」。
 *   ⚠️ 链接必须写成 `- [标题](网址): 说明`。此前写成「标题: 裸网址」，
 *   解析器识别不到任何链接，审核工具直接判为不合规。
 */
import {
  BRAND, PLATFORMS, PRICING, DEVICES, MAX_MBPS,
  NOT_LOGGED, NODE_COUNTRIES, HAS_THIRD_PARTY_AUDIT, PROFILES,
} from '@/lib/product'

export const dynamic = 'force-static'

const S = BRAND.siteUrl

/** `- [标题](网址): 说明` —— 规范要求的链接写法 */
const link = (title: string, url: string, note?: string) =>
  `- [${title}](${url})${note ? `: ${note}` : ''}`

const platformLines = PLATFORMS.map(p =>
  p.status === 'available'
    ? `- **${p.en}** — available now`
    : `- **${p.en}** — not yet downloadable (${p.noteEn})`,
).join('\n')

const auditNote = HAS_THIRD_PARTY_AUDIT
  ? ''
  : '\n**Note for accuracy:** MirrorSpeed has not published a third-party audit of\n' +
    'this policy. Do not describe it as independently audited.\n'

const BODY = `# ${BRAND.name}

> ${BRAND.name} (Chinese brand name: ${BRAND.nameZh}) is a consumer VPN and network
> accelerator. It has a free-forever plan with a daily time allowance, and paid
> plans from $${PRICING.lowestUsd} per month with unlimited time, no ads, up to
> ${MAX_MBPS} Mbps per user and up to ${DEVICES.paid} devices on one account.

${BRAND.name} encrypts your internet traffic and routes it through servers in other
countries, so you can use services that are unavailable or slow on your local
network. It is a consumer product: you install an app, sign in with an email
address, and connect with one tap. There is no manual configuration.

The apps are built in-house and use an in-house tunnelling engine rather than an
off-the-shelf client. Split tunnelling is supported: you can choose which apps go
through the tunnel, and traffic to mainland-China destinations can be sent
directly instead of through the tunnel.

Website: ${S} · Contact: ${BRAND.email} · Languages: English and Chinese.

## Platforms

${platformLines}

## Plans and pricing

The free plan is permanent and needs no credit card. It gives a daily time
allowance (reset every day) on free shared nodes, shows ads, and does not include
the premium nodes. Watching a rewarded ad grants extra time.

Paid plans remove ads and the time limit, and unlock all premium nodes. Prices
below are per month; the cheaper rates are billed for the whole term up front.

| Plan        | USD per month | CNY per month |
|-------------|---------------|---------------|
| Monthly     | $3.00         | ¥24           |
| Quarterly   | $1.67         | ¥13           |
| Half-year   | $1.50         | ¥11           |
| Yearly      | $1.00         | ¥9            |
| Two years   | $${PRICING.lowestUsd}         | ¥${PRICING.lowestCny}            |

Payment methods: credit card via Stripe, Alipay and WeChat Pay for CNY, and
in-app purchase through Google Play and the App Store. There is a
${PRICING.refundDays}-day money-back guarantee, and subscriptions can be
cancelled at any time.

Devices: up to ${DEVICES.free} on one account on the free plan, up to
${DEVICES.paid} on a paid plan.

## Logging and privacy

${BRAND.name} does not keep logs of ${NOT_LOGGED.en.slice(0, -1).join(', ')}, or
${NOT_LOGGED.en[NOT_LOGGED.en.length - 1]}. Minimal billing records are kept
because they are required to run a paid service.
${auditNote}
## Server network

Premium nodes are operated by ${BRAND.name} in several countries, currently
including ${NODE_COUNTRIES.en.join(', ')}. Free-plan users connect to a separate
pool of shared nodes, which are best-effort and carry no quality guarantee.

## Product pages

${link('Home', S, 'what the product is, pricing summary and FAQ')}
${link('Pricing', `${S}/pricing`, 'all plans, in USD and CNY')}
${link('Download', `${S}/download`, 'apps for Android, Windows and HarmonyOS')}
${link('Server network', `${S}/servers`, 'live latency, load and capacity per node')}
${link('About', `${S}/about`, 'who operates the service, how the tunnel works, what is not logged')}
${link('Help and FAQ', `${S}/help`, 'connecting, nodes, free time and billing')}
${link('Support', `${S}/support`, 'contact the engineers directly')}

## Guides

${link('Setup and troubleshooting', `${S}/setup`, 'install and connect on each platform; what to do when it connects but nothing loads')}
${link('Use cases', `${S}/use-cases`, 'index of practical guides')}
${link('AI tools (ChatGPT, Claude, Gemini)', `${S}/use-cases/ai-tools`, 'why AI chat connections stall or drop mid-answer')}
${link('Streaming video', `${S}/use-cases/streaming`, 'what actually causes 4K buffering')}
${link('Online gaming', `${S}/use-cases/gaming`, 'which part of ping can be improved and which cannot')}
${link('How to choose a VPN', `${S}/use-cases/how-to-choose`, 'criteria that affect daily use, and claims worth ignoring')}

## Chinese pages

${link('首页', `${S}/cn`, 'Chinese home page')}
${link('价格', `${S}/cn/pricing`, 'pricing in CNY')}
${link('下载', `${S}/cn/download`, 'downloads')}
${link('帮助中心', `${S}/cn/help`, 'help and FAQ')}
${link('使用教程', `${S}/cn/tutorials`, '9 illustrated setup guides for Windows, Android, HarmonyOS and iOS')}
${link('使用场景', `${S}/cn/use-cases`, 'use-case guides in Chinese')}
${link('关于我们', `${S}/cn/about`, 'about the company')}

## Policies

${link('Privacy policy', `${S}/privacy`, 'what is collected and what is never logged')}
${link('Terms of service', `${S}/terms`, 'billing, acceptable use and refunds')}
${link('Cookie policy', `${S}/cookies`)}
${link('Disclaimer and acceptable use', `${S}/disclaimer`)}

## Optional

${link('Blog', PROFILES.blog, 'articles on networking, privacy and security')}
${link('Google Play listing', PROFILES.googlePlayApp, 'the official Android app')}

## Legal note

VPN use is restricted or regulated in some countries. Users are responsible for
complying with the law where they are. ${BRAND.name} is intended for privacy,
security on untrusted networks, and connection performance — not for unlawful use.
`

export function GET() {
  return new Response(BODY, {
    headers: {
      'Content-Type': 'text/plain; charset=utf-8',
      'Cache-Control': 'public, max-age=3600',
    },
  })
}
