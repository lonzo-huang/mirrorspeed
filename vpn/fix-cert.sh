#!/usr/bin/env bash
# fix-cert.sh — 在【某个节点】上跑：续期该节点的 mirrorspeed.com 管理域名证书，
# 并把自动续期方式固化为 nginx(http-01)，根治「证书过期 → 控制机探测失败 → 节点被
# 误标 offline」。此前多台节点的 certbot 自动续期是坏的(webroot 取不到校验文件 / 原本
# 用 dns-01 与 nginx 冲突)，会每 ~90 天一台台到期。跑一次即永久修好。
#
# 用法(在节点上，root)：
#   sudo bash /opt/mirrorspeed/vpn/fix-cert.sh
#
# 只动本机 nginx/certbot，不碰数据库；续好后 ≤60s 控制机健康检查会把它翻回 online。
set -uo pipefail
[[ $EUID -ne 0 ]] && { echo "请用 root 运行：sudo bash $0"; exit 1; }

# 找本节点的 mirrorspeed.com 管理域名证书(取第一个)
D=$(ls /etc/letsencrypt/live/ 2>/dev/null | grep 'mirrorspeed\.com' | head -1)
if [[ -z "$D" ]]; then
  echo "✗ 没找到 mirrorspeed.com 的证书目录，无法自动定位域名。"
  echo "  手动看：ls /etc/letsencrypt/live/"
  exit 1
fi
echo "==> 本节点管理域名: $D"

echo "==> 续期证书(nginx / http-01，强制)..."
if ! certbot certonly --nginx -d "$D" --preferred-challenges http-01 --force-renewal -n; then
  echo "✗ 续期失败。常见原因：80 端口未对公网开放 / nginx 未服务该域名。"
  echo "  应急：把数据库 vpn_servers 该行 api_url 改回一个证书未过期的域名。"
  exit 1
fi

echo "==> 重载 nginx..."
systemctl reload nginx || true

CONF="/etc/letsencrypt/renewal/${D}.conf"
if [[ -f "$CONF" ]]; then
  echo "==> 固化自动续期为 nginx..."
  sed -i 's/^authenticator = .*/authenticator = nginx/' "$CONF"
fi

echo "==> 演练自动续期(dry-run)..."
certbot renew --cert-name "$D" --dry-run || echo "  (dry-run 有告警，见上；不影响本次已续好的证书)"

echo "==> 验证对外可达..."
CODE=$(curl -sS -o /dev/null -w "%{http_code}" "https://$D/vpn-api/health" || echo 000)
echo "    https://$D/vpn-api/health -> HTTP $CODE"

if [[ "$CODE" == "200" ]]; then
  echo "✅ 完成。证书已续 + 自动续期已固化为 nginx。≤60s 后该节点会自动翻 online。"
else
  echo "⚠️ 证书已续，但对外 /vpn-api/health 返回 $CODE(非 200)。检查 nginx 反代 / 防火墙。"
fi
