/**
 * 券商「强制走代理」域名管理（仅 admin）。
 *   GET    → 当前生效列表 + 是否为内置默认 + 默认列表（供「恢复默认」对照）
 *   POST   → 保存自定义列表（规范化 + 校验），写入 app_config.force_proxy_domains（逗号分隔）
 *   DELETE → 删除该 app_config 行，回退到内置默认
 * 客户端通过 /api/mobile/configs 下发 force_proxy_domains，连接时把这些域名强制走代理，
 * 压过智能分流 airlane-cn 的 CN ip_cidr，避免老虎/富途等中资券商被判「国内网络」。
 */
import { createAdminClient, getUser } from '@/lib/supabase/server'
import { NextResponse } from 'next/server'

export const dynamic = 'force-dynamic'
export const runtime  = 'nodejs'

const KEY = 'force_proxy_domains'

// 需与 /api/mobile/configs 的 DEFAULT_FORCE_PROXY_DOMAINS 及客户端
// ApiService.defaultForceProxyDomains 保持一致（三处内置默认同源）。
const DEFAULT_FORCE_PROXY_DOMAINS = [
  'tigerfintech.com', 'itigerup.net', 'itiger.com', 'laohu8.com',
  'tigersecurities.com', 'tigerbrokers.com', 'tigertrade.com',
  'futunn.com', 'futu5.com', 'moomoo.com', 'futuhk.com',
]

async function requireAdmin() {
  const user = await getUser()
  if (!user) return { ok: false as const, status: 401 }
  const admin = createAdminClient()
  const { data: profile } = await admin.from('profiles').select('role').eq('id', user.id).single()
  if ((profile as any)?.role !== 'admin') return { ok: false as const, status: 403 }
  return { ok: true as const, admin }
}

// 规范化并校验域名：小写、去协议/路径/前导 *.、去重；丢弃不合法项。
function normalizeDomains(input: unknown): string[] {
  const raw = Array.isArray(input) ? input : String(input ?? '').split(/[\s,]+/)
  const seen = new Set<string>()
  const out: string[] = []
  for (const item of raw) {
    let d = String(item).trim().toLowerCase()
    if (!d) continue
    d = d.replace(/^https?:\/\//, '').replace(/\/.*$/, '')   // 去协议 + 路径
         .replace(/^\*\./, '').replace(/^\.+/, '').replace(/\.+$/, '')  // 去前导 *. 和首尾点
    // 基本域名校验：至少两级，末级为字母
    if (!/^(?=.{1,253}$)([a-z0-9](-?[a-z0-9])*\.)+[a-z]{2,}$/.test(d)) continue
    if (!seen.has(d)) { seen.add(d); out.push(d) }
  }
  return out
}

async function readCustom(admin: any): Promise<string[] | null> {
  const { data } = await admin.from('app_config').select('value').eq('key', KEY).maybeSingle()
  const raw = (data?.value as string | undefined) ?? ''
  if (!raw.trim()) return null
  const list = raw.split(',').map((s: string) => s.trim()).filter(Boolean)
  return list.length ? list : null
}

export async function GET() {
  const gate = await requireAdmin()
  if (!gate.ok) return NextResponse.json({ error: 'Forbidden' }, { status: gate.status })
  const custom = await readCustom(gate.admin as any)
  return NextResponse.json({
    domains:   custom ?? DEFAULT_FORCE_PROXY_DOMAINS,
    isDefault: !custom,
    defaults:  DEFAULT_FORCE_PROXY_DOMAINS,
  })
}

export async function POST(req: Request) {
  const gate = await requireAdmin()
  if (!gate.ok) return NextResponse.json({ error: 'Forbidden' }, { status: gate.status })
  const admin = gate.admin as any

  let body: any
  try { body = await req.json() } catch { return NextResponse.json({ error: '请求体不是合法 JSON' }, { status: 400 }) }

  const domains = normalizeDomains(body?.domains)
  if (!domains.length) return NextResponse.json({ error: '至少需要一个有效域名' }, { status: 400 })
  if (domains.length > 500) return NextResponse.json({ error: '域名数量超过上限（500）' }, { status: 400 })

  const { error } = await admin.from('app_config').upsert({ key: KEY, value: domains.join(',') }, { onConflict: 'key' })
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ domains, isDefault: false, saved: true })
}

export async function DELETE() {
  const gate = await requireAdmin()
  if (!gate.ok) return NextResponse.json({ error: 'Forbidden' }, { status: gate.status })
  const admin = gate.admin as any
  const { error } = await admin.from('app_config').delete().eq('key', KEY)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ domains: DEFAULT_FORCE_PROXY_DOMAINS, isDefault: true, reset: true })
}
