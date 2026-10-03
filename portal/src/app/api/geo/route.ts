import { NextRequest, NextResponse } from 'next/server'
import { unstable_noStore as noStore } from 'next/cache'

export const dynamic = 'force-dynamic'

// GET /api/geo → { country: "CN" | "ES" | ... | null }
//
// 客户端用它判断「出口是否在国内」，据此决定智能模式要不要做中国 IP 分流。
// 原先用的是 cloudflare.com/cdn-cgi/trace —— 该域名在国内经常不可达，探测失败
// 就退化成全局模式（所有流量进隧道）。本接口与 App 其余请求同域，国内可达。
//
// 国家码由边缘节点按客户端 IP 注入，不依赖任何第三方服务。
export async function GET(req: NextRequest) {
  noStore()

  const country =
    req.headers.get('x-vercel-ip-country') ??
    req.headers.get('cf-ipcountry') ??
    null

  return NextResponse.json(
    { country },
    { headers: { 'Cache-Control': 'no-store, max-age=0' } },
  )
}
