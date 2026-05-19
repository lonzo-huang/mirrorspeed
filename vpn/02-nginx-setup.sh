#!/bin/bash
# 02-nginx-setup.sh — Nginx TLS 1.3 前置层 + 静态站 + 路径分流
# 修复：certbot 鸡蛋问题（先HTTP验证签发，再启用HTTPS配置）
#       移除 default 站点，增加安全响应头，wstunnel 路径代理
set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "ERROR: 必须以 root 执行"; exit 1; }

# ── 配置变量（部署前修改）────────────────────────────────────────────────
DOMAIN="${1:-remote.yourcompany.com}"
EMAIL="${2:-it-admin@yourcompany.com}"
WEBROOT="/var/www/html/enterprise-portal"
TUNNEL_BACKEND="127.0.0.1:2080"   # wstunnel 监听地址

echo "[1/5] 安装 Nginx 与 Certbot..."
apt-get update -qq
apt-get install -y nginx certbot python3-certbot-nginx

# 停用默认站点
rm -f /etc/nginx/sites-enabled/default
systemctl enable nginx

echo "[2/5] 创建静态门户站点..."
mkdir -p "${WEBROOT}"
cat > "${WEBROOT}/index.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Enterprise Secure Portal</title>
  <style>
    body { font-family: Arial, sans-serif; max-width: 600px; margin: 120px auto;
           color: #333; text-align: center; }
    h1 { color: #1a73e8; }
    p  { color: #666; }
  </style>
</head>
<body>
  <h1>Enterprise Secure Access Portal</h1>
  <p>Authorized employees only. Contact IT support for assistance.</p>
</body>
</html>
HTMLEOF

echo "[3/5] 配置 HTTP 临时站（用于 certbot webroot 域名验证）..."
# 修复原框架 bug：先以 HTTP 通过 certbot 验证，再上线 HTTPS 配置
cat > /etc/nginx/sites-available/enterprise-http-temp << NGINXEOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    root ${WEBROOT};
    location /.well-known/acme-challenge/ {
        allow all;
    }
    location / {
        return 301 https://\$host\$request_uri;
    }
}
NGINXEOF

ln -sf /etc/nginx/sites-available/enterprise-http-temp \
       /etc/nginx/sites-enabled/enterprise-http-temp
nginx -t && systemctl reload nginx

echo "[4/5] 签发 Let's Encrypt TLS 证书..."
certbot certonly \
    --webroot \
    --webroot-path "${WEBROOT}" \
    --domain "${DOMAIN}" \
    --email "${EMAIL}" \
    --agree-tos \
    --non-interactive \
    --staple-ocsp \
    --must-staple

# 移除临时 HTTP 配置
rm -f /etc/nginx/sites-enabled/enterprise-http-temp

echo "[5/5] 部署 TLS 1.3 + 路径分流正式配置..."
cat > /etc/nginx/sites-available/enterprise-vpn << NGINXEOF
# ── HTTPS 主站 ────────────────────────────────────────────────────────────
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN};

    # TLS 1.3 强制（兼容 TLS 1.2 供部分旧客户端）
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_certificate     /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

    # Session 优化（减少握手开销）
    ssl_session_timeout 1d;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_tickets off;

    # OCSP Stapling
    ssl_stapling        on;
    ssl_stapling_verify on;
    ssl_trusted_certificate /etc/letsencrypt/live/${DOMAIN}/chain.pem;
    resolver 1.1.1.1 8.8.8.8 valid=300s;
    resolver_timeout 5s;

    # 安全响应头（正常网站标配，增强伪装可信度）
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Content-Type-Options    nosniff always;
    add_header X-Frame-Options           DENY always;
    add_header Referrer-Policy           "no-referrer" always;

    # 日志：关闭访问日志，仅保留错误日志
    access_log off;
    error_log  /var/log/nginx/enterprise-error.log warn;

    root  ${WEBROOT};
    index index.html;

    # ── WireGuard-over-WebSocket 隧道路径 ─────────────────────────────────
    # 流量特征：标准 WSS 升级请求，与普通 WebSocket 应用无差别
    location /secure-tunnel/ {
        proxy_pass         http://${TUNNEL_BACKEND}/;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade    \$http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host       \$host;

        # 隐藏真实后端，不暴露内网 IP
        proxy_hide_header  X-Real-IP;
        proxy_hide_header  X-Forwarded-For;

        # 长连接保活（WireGuard 隧道需要持久连接）
        proxy_read_timeout    86400s;
        proxy_send_timeout    86400s;
        proxy_connect_timeout 10s;

        # 关闭代理层缓冲（减少隧道延迟）
        proxy_buffering off;
    }

    # ── 安全加固：阻断扫描与探测 ─────────────────────────────────────────
    location ~ /\.            { deny all; return 404; }
    location ~* \.(log|bak|swp|tmp|env|git)$ { deny all; return 404; }

    # 默认返回静态站内容
    location / {
        try_files \$uri \$uri/ =404;
    }
}

# ── HTTP 永久跳转 HTTPS ───────────────────────────────────────────────────
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}
NGINXEOF

ln -sf /etc/nginx/sites-available/enterprise-vpn \
       /etc/nginx/sites-enabled/enterprise-vpn
nginx -t && systemctl reload nginx

# 证书自动续期（certbot 安装后已默认配置 systemd timer，此处确认）
systemctl is-enabled certbot.timer &>/dev/null && \
    echo "  certbot 自动续期 timer 已启用" || \
    echo "  WARNING: certbot.timer 未找到，请手动配置续期 cron"

echo ""
echo "Nginx 部署完成："
echo "  普通访问  https://${DOMAIN}/          → 静态站点"
echo "  隧道路径  https://${DOMAIN}/secure-tunnel/  → wstunnel 2080"
