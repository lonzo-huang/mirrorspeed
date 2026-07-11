import { NextResponse } from 'next/server'
import { makeCaptcha } from '@/lib/captcha'

export const dynamic = 'force-dynamic'
export const runtime  = 'nodejs'

// GET /api/support/captcha — 返回一道算术题及其签名 token（供 support 表单使用）。
export async function GET() {
  const { question, token } = makeCaptcha()
  return NextResponse.json({ question, token }, { headers: { 'Cache-Control': 'no-store' } })
}
