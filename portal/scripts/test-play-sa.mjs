// 验证 Google Play 服务账号能否访问本 app 的 Play Developer API（不需要任何真实购买）。
// 用法（在 portal 目录下，用了 portal 的 node_modules 里的 google-auth-library）：
//   node scripts/test-play-sa.mjs <服务账号JSON路径> [包名]
// 例：node scripts/test-play-sa.mjs C:\Users\you\Downloads\sa.json com.mirrorspeed.vpn
//
// 结果判读：
//   200  → 服务账号 OK、API 已启用、对该 app 有权限 → verify 到时能跑。
//   401/403 → 权限没授予/没生效（Play「用户和权限」里邀请该 SA 邮箱并授权，等几分钟~几小时）。
//   404  → 包名不对，或该 app 下还没建订阅商品。
//   其它 → 看打印的错误详情。
import fs from 'node:fs'
import { GoogleAuth } from 'google-auth-library'

const keyPath = process.argv[2]
const pkg = process.argv[3] || 'com.mirrorspeed.vpn'
if (!keyPath) { console.error('用法: node scripts/test-play-sa.mjs <服务账号JSON路径> [包名]'); process.exit(1) }

const credentials = JSON.parse(fs.readFileSync(keyPath, 'utf8'))
console.log('服务账号邮箱:', credentials.client_email)
console.log('包名:', pkg)

const auth = new GoogleAuth({ credentials, scopes: ['https://www.googleapis.com/auth/androidpublisher'] })
const client = await auth.getClient()
const at = (await client.getAccessToken()).token
console.log('拿到 access token:', at ? 'OK' : '失败')

// 列出该 app 的订阅商品（monetization）——能列出就说明整条链路通。
const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${pkg}/subscriptions`
const res = await fetch(url, { headers: { Authorization: `Bearer ${at}` } })
const body = await res.text()
console.log('\nPlay API 状态:', res.status)
try {
  const j = JSON.parse(body)
  if (Array.isArray(j.subscriptions)) {
    console.log('✓ 可访问。该 app 的订阅商品 productId:')
    for (const s of j.subscriptions) console.log('  -', s.productId)
  } else {
    console.log(JSON.stringify(j, null, 2).slice(0, 800))
  }
} catch { console.log(body.slice(0, 800)) }
