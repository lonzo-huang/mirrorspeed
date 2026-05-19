import { createServerSupabaseClient } from '@/lib/supabase/server'
import { NextResponse } from 'next/server'

// GET /api/servers — 返回所有服务器列表（含缓存状态）
// 前端每 30 秒轮询一次，数据来自 Supabase 缓存（由 cron 每分钟刷新）
export async function GET() {
  const supabase = await createServerSupabaseClient()

  const { data: servers, error } = await supabase
    .from('vpn_servers')
    .select(`
      id, name, display_name, location, country_code, flag_emoji,
      endpoint, port, status, latency_ms, active_peers, max_peers,
      load_percent, cpu_percent, mem_percent, bandwidth_mbps,
      last_checked_at, sort_order
    `)
    .eq('is_active', true)
    .order('sort_order', { ascending: true })

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }

  return NextResponse.json({ servers }, {
    headers: {
      // 30 秒缓存（stale-while-revalidate 允许后台刷新时仍用旧数据）
      'Cache-Control': 'public, s-maxage=30, stale-while-revalidate=60',
    },
  })
}
