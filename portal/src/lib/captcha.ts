import crypto from 'crypto'

// 无状态算术验证码：服务端出题并对答案签名（HMAC），客户端回传 token+答案，
// 服务端重新签名比对。无需数据库/外部服务。
// 密钥用服务端专有的 SUPABASE_SERVICE_ROLE_KEY（永不下发前端），可用 CAPTCHA_SECRET 覆盖。

const TTL_MS = 10 * 60 * 1000

function secret(): string {
  return process.env.CAPTCHA_SECRET || process.env.SUPABASE_SERVICE_ROLE_KEY || 'insecure-dev-secret'
}

function sign(answer: number, exp: number): string {
  return crypto.createHmac('sha256', secret()).update(`${answer}.${exp}`).digest('hex')
}

export function makeCaptcha(): { question: string; token: string } {
  const a = 1 + Math.floor(Math.random() * 9)
  const b = 1 + Math.floor(Math.random() * 9)
  const exp = Date.now() + TTL_MS
  return { question: `${a} + ${b}`, token: `${exp}.${sign(a + b, exp)}` }
}

export function verifyCaptcha(token: unknown, answerRaw: unknown): boolean {
  if (typeof token !== 'string') return false
  const dot = token.indexOf('.')
  if (dot < 0) return false
  const exp = parseInt(token.slice(0, dot), 10)
  const sig = token.slice(dot + 1)
  if (!exp || Date.now() > exp) return false
  const answer = parseInt(String(answerRaw).trim(), 10)
  if (Number.isNaN(answer)) return false
  const expected = sign(answer, exp)
  if (sig.length !== expected.length) return false
  try {
    return crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected))
  } catch {
    return false
  }
}
