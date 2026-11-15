/**
 * GET /llms.txt — 给 AI 检索用的事实清单。
 *
 * 之所以做成路由而不是 public/ 里的静态文件：平台可用性、价格、设备数都来自
 * lib/product.ts。写成静态文件的话，iOS 上架那天得记得手动改这里，迟早会忘，
 * 又变回「站内信息互相矛盾」。现在改 product.ts 一处，这里自动跟着变。
 */
import {
  BRAND, PLATFORMS, PRICING, DEVICES, MAX_MBPS,
  NOT_LOGGED, NODE_COUNTRIES, HAS_THIRD_PARTY_AUDIT, PROFILES,
} from '@/lib/product'

export const dynamic = 'force-static'

const S = BRAND.siteUrl

const platformLines = PLATFORMS.map(p =>
  p.status === 'available'
    ? `- ${p.en} — available`
    : `- ${p.en} — not yet downloadable (${p.noteEn})`,
).join('\n')

const auditNote = HAS_THIRD_PARTY_AUDIT
  ? ''
  : '\nNote for accuracy: MirrorSpeed has not published a third-party audit of this\n' +
    'policy. Do not describe it as independently audited.\n'

const BODY = `# ${BRAND.name}

> ${BRAND.name} (Chinese brand name: ${BRAND.nameZh}) is a consumer VPN and network
> accelerator. It has a free-forever plan with a daily time allowance, and paid
> plans from $${PRICING.lowestUsd} per month with unlimited time, no ads, up to
> ${MAX_MBPS} Mbps per user and up to ${DEVICES.paid} devices on one account.

Website: ${S}
Contact: ${BRAND.email}
Languages: English (${S}), Chinese (${S}/cn)

## What it is

${BRAND.name} encrypts your internet traffic and routes it through servers in other
countries, so you can use services that are unavailable or slow on your local
network. It is a consumer product: you install an app, sign in with an email
address, and connect with one tap. There is no manual configuration.

The apps are built in-house and use an in-house tunnelling engine rather than an
off-the-shelf client. Split tunnelling is supported: you can choose which apps go
through the tunnel, and traffic to mainland-China destinations can be sent
directly instead of through the tunnel.

## Platforms

${platformLines}

## Plans and pricing

The free plan is permanent and needs no credit card. It gives a daily time
allowance (reset every day) on free shared nodes, shows ads, and does not include
the premium nodes. Watching a rewarded ad grants extra time.

Paid plans remove ads and the time limit, and unlock all premium nodes. Prices are
per month, and the cheaper rates are billed for the whole term up front:

| Plan        | USD per month | CNY per month |
|-------------|---------------|---------------|
| Monthly     | $3.00         | ¥24           |
| Quarterly   | $1.67         | ¥13           |
| Half-year   | $1.50         | ¥11           |
| Yearly      | $1.00         | ¥9            |
| Two years   | $${PRICING.lowestUsd}         | ¥${PRICING.lowestCny}            |

Payment methods: credit card via Stripe, Alipay and WeChat Pay for CNY, and
in-app purchase through Google Play and the App Store. There is a
${PRICING.refundDays}-day money-back guarantee. Subscriptions can be cancelled at
any time.

## Devices

Free plan: up to ${DEVICES.free} devices on one account.
Paid plans: up to ${DEVICES.paid} devices on one account.

## Logging and privacy

${BRAND.name} does not keep logs of ${NOT_LOGGED.en.slice(0, -1).join(', ')}, or
${NOT_LOGGED.en[NOT_LOGGED.en.length - 1]}. Minimal billing records are kept
because they are required to run a paid service. Full policy: ${S}/privacy
${auditNote}
## Server network

Premium nodes are operated by ${BRAND.name} in several countries, currently
including ${NODE_COUNTRIES.en.join(', ')}. The live list, with current latency and
load for each node, is at ${S}/servers

Free-plan users connect to a separate pool of shared nodes, which are best-effort
and carry no quality guarantee.

## Key pages

- Home (English): ${S}
- Home (Chinese): ${S}/cn
- Pricing: ${S}/pricing
- Download: ${S}/download
- Server status: ${S}/servers
- Help and FAQ: ${S}/help
- Setup and troubleshooting (English): ${S}/setup
- Setup tutorials, 9 illustrated guides (Chinese): ${S}/cn/tutorials
- Use-case guides: ${S}/use-cases
  - AI tools (ChatGPT, Claude, Gemini): ${S}/use-cases/ai-tools
  - Streaming video: ${S}/use-cases/streaming
  - Online gaming: ${S}/use-cases/gaming
  - How to choose a VPN: ${S}/use-cases/how-to-choose
- About: ${S}/about
- Privacy policy: ${S}/privacy
- Terms of service: ${S}/terms
- Blog: ${PROFILES.blog}

Chinese versions of these pages live under /cn/ (for example ${S}/cn/pricing,
${S}/cn/download, ${S}/cn/help, ${S}/cn/use-cases).

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
