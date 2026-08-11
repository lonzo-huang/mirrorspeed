import { createAdminClient } from '@/lib/supabase/server'
import { createClient } from '@supabase/supabase-js'
import { NextRequest, NextResponse } from 'next/server'
import type { Database } from '@/types/database.types'

// GET /api/mobile/free-nodes — 共享(免费机场)节点列表，交给 App 的 sing-box 引擎连接。
// 需登录(Bearer)：不做成公开接口，避免免费节点池被直接爬走/滥用。
// 返回每个节点的 sing-box outbound(端上零解析)+ 展示元信息。
export const dynamic = 'force-dynamic'
export const runtime  = 'nodejs'

async function getUser(req: NextRequest) {
  const auth  = req.headers.get('authorization') ?? ''
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : null
  if (!token) return null
  const supabase = createClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    { auth: { autoRefreshToken: false, persistSession: false } },
  )
  const { data: { user } } = await supabase.auth.getUser(token)
  return user
}

export async function GET(req: NextRequest) {
  const user = await getUser(req)
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const limit = Math.min(parseInt(req.nextUrl.searchParams.get('limit') ?? '50', 10) || 50, 200)

  const admin = createAdminClient()
  const { data, error } = await (admin.from('free_nodes' as any) as any)
    .select('id, protocol, name, server, port, country_code, outbound, latency_ms')
    .eq('is_active', true)
    .order('last_seen', { ascending: false })
    .limit(limit)

  if (error) {
    return NextResponse.json({ error: 'db error' }, { status: 500 })
  }

  const nodes = (data ?? []) as any[]
  return NextResponse.json(
    {
      count: nodes.length,
      nodes: nodes.map(n => ({
        id:           n.id,
        protocol:     n.protocol,
        name:         n.name,
        server:       n.server,
        port:         n.port,
        country_code: n.country_code,
        latency_ms:   n.latency_ms,
        outbound:     n.outbound,   // sing-box outbound JSON
      })),
    },
    { headers: { 'Cache-Control': 'private, max-age=30' } },
  )
}
