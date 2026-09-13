# MirrorSpeed 抗封锁 / 可达性 Roadmap

> 主题：对抗 GFW 对「引导域名」和「数据链路」的封锁，保证国内用户装了 App 就能连。
> 最近更新：2026-09-13

## 背景（三层链路，互不相干）

```
① 引导/控制链路  客户端 ──HTTPS──> portal.mirrorspeed.com (Vercel)   ← 兜底 mirrorspeed.eu.cc
                 作用：登录、发节点配置、建 peer、通告、版本检查（只发配置，不跑流量）
② VPN 数据链路    客户端 ──WG/wstunnel/CF Tunnel──> 各 VPN 节点
                 层1 直连(endpoint,多为裸IP,UDP)｜层2 强力(wss://relayHost,*.mirrorspeed.com 子域)｜层3 暴力(cfRelayUrl,*.cfargotunnel.com)
③ 官网(给人看)    mirrorspeed.com — 下载/介绍/SEO；被封只影响新用户获取，不影响老用户 App
```

核心认知：
- **官网可随时换**（告诉新用户新地址即可）；**App 连的后端域名不能随便换**（已安装 App 域名是编译进去的，改了推不过去）→ 必须靠「内置备用列表 + 远程域名发现」。
- CF 只能藏源站 IP / 防攻击 / 统一管 DNS，**防不了域名被 GFW 拉黑**，对 China 可达性帮助有限甚至倒退。
- 最大隐患：官网 `www.mirrorspeed.com` 与后端 `portal.mirrorspeed.com` **同父域**，GFW 一封一锅端。

## ✅ 已完成并推送（代码层）
- 优质节点配置本地缓存（加密落盘，冷启动秒出，引导域名不通也能连上次节点）
- 免费订阅源「域名优先 + 固定 IP 兜底」：国内 `scanner.mirrorspeed.com`+`218.11.5.114`；海外 `scanner-os.mirrorspeed.com`+`185.93.70.165`
- 引导域名 failover：`kApiBase`(主) + `kApiBaseFallback`(兜底 mirrorspeed.eu.cc)，连接级失败才切，切成功本会话记住

---

## A. 让兜底引导域名真正可用（你：后端/DNS）
- [ ] 把 `mirrorspeed.eu.cc` 加进**同一个 Vercel 项目** Domains（同一套 API、自动 TLS）
- [ ] 在 eu.cc 配 DNS 指向 Vercel —— **先确认 eu.cc 给的是真 DNS 控制权（能加 A/CNAME、做域名验证），不是 URL 转发**，否则签不了证书
- [ ] 验证：`curl https://mirrorspeed.eu.cc/api/servers` 返回与 portal 相同 JSON
- [ ] 待定：fallback 用 apex 还是子域（确认 eu.cc 能力后调整客户端 `kApiBaseFallback`）

## B. 架构解耦（昨天讨论，未动手）
- [ ] **官网 A 与 App 后端 B 拆到不同父域名**（消除同父域一锅端隐患）
- [ ] **域名发现渠道**：让已安装 App 不发版就能拿最新可用后端域名
  - 方向未定：**B1 先拆父域名** / **B2 直接上域名发现**
  - 推荐做法：**DoH 查 TXT 记录**（走 443，最耐封、成本最低，不依赖 GitHub 国内可用性）
  - 备选：GitHub/Gitee raw + jsDelivr 镜像；Cloudflare Worker 返回域名列表
  - 目标流程：启动 → 试内置域名列表 → 全挂 → 走发现渠道拿新域名 → 继续连；后台随时上新域名，老用户自动获取，无需发版

## C. 数据链路抗封（等数据，才判断要不要动节点）
- [ ] 你从 Supabase 导 `vpn_servers` 表的 `name, api_url, cf_relay_url, endpoint` 几列
- [ ] 分析：节点 wstunnel relay 域名是否都挤在 `mirrorspeed.com` 下（整域被封则「强力模式」全死）；有几台配了 Cloudflare Tunnel（唯一能扛整域封锁的一层）
- [ ] 结论输出：补哪几台、怎么补最省事（首选给每台节点都配 Cloudflare Tunnel，`cfargotunnel.com` 与 mirrorspeed.com 无关且免费）

## D. Cloudflare 整域迁移（可选，优先级低，排 B/C 之后）
- 结论：只解决藏源站/防攻击/统一 DNS，**不解决域名被墙**
- 素材：Hostinger zone 文件已备（含残留记录如 `_acme-challenge.spain01.ionos` TTL 60、`_acme-challenge.scanner` 可清理）
- [ ] 要迁则出 zone 文件 + 迁移脚本（用自己的 CF token 在本地跑，token 不进对话）
- 迁移要点：只有 `@`/`www`/`portal`(Vercel) 开橙云🟠；`scanner*`(端口 10611/10612 非标) 和邮件记录必须灰云⚪；SSL 用 Full(strict)

---

## E. 长期挂起（进行中/待办，非本轮抗封重点）
- [进行中] iOS/macOS 版本：已在 MacBook 上编好包，**等 Apple 开发者账号审批**；Mac 端改动在独立分支
- [ ] 剩余节点 JP01/HK01/US01/DE02 跑一遍 `vpn/fix-cert.sh`（续证方式还是旧的）
- [ ] Google Play 上架（2.6.1 AAB 已就绪）
- [ ] airlane.cloud 的 og:image 换成 PNG/JPG（1200×630 栅格图）

## 优先级建议
1. **A**（eu.cc 接通）—— 兜底域名现在只是代码占位，接通才生效
2. **B 定方向**（B1 拆父域 / B2 域名发现）
3. **C**（给数据后分析节点）
4. D 靠后
