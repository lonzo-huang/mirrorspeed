/**
 * Apple App Store 内购（StoreKit 2）签名数据的本地验证。
 *
 * StoreKit 2 的交易 / 续订信息、以及 App Store Server Notifications V2 都是 JWS
 * （ES256 签名 + x5c 证书链）。证书链验到 Apple Root CA G3 即可确认真伪，
 * **不需要**在服务器保存任何苹果 API 密钥 —— 这也是官方推荐做法。
 *
 * 只用 Node 内置 crypto，不引入新依赖。
 */
import { X509Certificate, createVerify, createPublicKey } from 'crypto'

/** Apple Root CA - G3（https://www.apple.com/certificateauthority/AppleRootCA-G3.cer） */
const APPLE_ROOT_CA_G3 = `-----BEGIN CERTIFICATE-----
MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwS
QXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9u
IEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcN
MTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBS
b290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9y
aXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49
AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtf
TjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517
IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySr
MA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gA
MGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4
at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM
6BgD56KyKA==
-----END CERTIFICATE-----`

/** 允许的 App bundle id（与 iOS 工程一致）。 */
export const APPLE_BUNDLE_ID =
  process.env.APPLE_BUNDLE_ID ?? 'com.mirrorspeed.mirrorspeedVpn'

export interface AppleTransaction {
  transactionId: string
  originalTransactionId: string
  productId: string
  bundleId: string
  purchaseDate: number            // ms
  originalPurchaseDate: number    // ms
  expiresDate?: number            // ms（自动续订订阅才有）
  type: string                    // 'Auto-Renewable Subscription' 等
  environment: string             // 'Production' | 'Sandbox'
  revocationDate?: number         // 退款/撤销时间，存在即应停用会员
  appAccountToken?: string        // 购买时带上的我方 user id（关键：把交易关联到账号）
  inAppOwnershipType?: string
}

function b64urlToBuf(s: string): Buffer {
  return Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64')
}

function decodeSegment<T>(seg: string): T {
  return JSON.parse(b64urlToBuf(seg).toString('utf8')) as T
}

/**
 * 校验一段 Apple JWS 并返回其 payload。
 * 失败抛异常 —— 调用方一律当作「无效购买」处理，不要降级放行。
 */
export function verifyAppleJWS<T = unknown>(jws: string): T {
  const parts = jws.split('.')
  if (parts.length !== 3) throw new Error('malformed JWS')
  const [headerB64, payloadB64, sigB64] = parts

  const header = decodeSegment<{ alg: string; x5c?: string[] }>(headerB64)
  if (header.alg !== 'ES256') throw new Error(`unexpected alg: ${header.alg}`)
  if (!header.x5c || header.x5c.length < 2) throw new Error('missing x5c chain')

  // x5c: [叶子, 中间CA, 根CA]，都是 base64 DER
  const chain = header.x5c.map(
    (der) => new X509Certificate(Buffer.from(der, 'base64')),
  )
  const root = new X509Certificate(APPLE_ROOT_CA_G3)

  // 1) 链上每一级都必须由上一级签发，最后一级必须是（或等同于）Apple Root CA G3
  for (let i = 0; i < chain.length - 1; i++) {
    if (!chain[i].verify(chain[i + 1].publicKey)) {
      throw new Error(`certificate chain broken at ${i}`)
    }
  }
  const last = chain[chain.length - 1]
  const anchoredToApple =
    last.fingerprint256 === root.fingerprint256 || last.verify(root.publicKey)
  if (!anchoredToApple) throw new Error('chain not anchored to Apple Root CA G3')

  // 2) 有效期
  const now = Date.now()
  for (const cert of chain) {
    if (now < Date.parse(cert.validFrom) || now > Date.parse(cert.validTo)) {
      throw new Error('certificate expired or not yet valid')
    }
  }

  // 3) 验签：JWS 的 ES256 签名是裸 R||S，需告诉 Node 用 ieee-p1363 编码
  const verifier = createVerify('SHA256')
  verifier.update(`${headerB64}.${payloadB64}`)
  verifier.end()
  const ok = verifier.verify(
    { key: createPublicKey(chain[0].publicKey), dsaEncoding: 'ieee-p1363' },
    b64urlToBuf(sigB64),
  )
  if (!ok) throw new Error('signature verification failed')

  return decodeSegment<T>(payloadB64)
}

/** 校验一笔交易，并确认它属于本 App。 */
export function verifyTransaction(signedTransaction: string): AppleTransaction {
  const txn = verifyAppleJWS<AppleTransaction>(signedTransaction)
  if (txn.bundleId !== APPLE_BUNDLE_ID) {
    throw new Error(`bundleId mismatch: ${txn.bundleId}`)
  }
  return txn
}

/** 该交易此刻是否应当享有会员（未过期、未退款）。 */
export function isTransactionActive(txn: AppleTransaction): boolean {
  if (txn.revocationDate) return false
  if (!txn.expiresDate) return true            // 非订阅型（买断）视为长期有效
  return txn.expiresDate > Date.now()
}
