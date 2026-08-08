# 双引擎架构规划：sing-box(低价区) + AmneziaWG(中价区)

> 状态：**规划中(未实施)**。本文是实施蓝图,落地时按「实施阶段」逐步推进。
> 最后更新:2026-07。

## 1. 产品定位:两个区段

| | 低价区 | 中价区 |
|---|---|---|
| 引擎 | **sing-box** | **AmneziaWG**(现有) |
| 节点来源 | **免费机场**(扫描器抓取,见 §5) | **自建付费服务器**(现有 7 台) |
| 带宽/延迟 | 不保证(实测延迟 700ms+、带宽 2–4Mbps) | 带宽固定、延迟有保障(几十 ms) |
| 抗封锁 | 取决于机场节点协议(vless/trojan/hysteria 等) | AmneziaWG 混淆 + wstunnel/CF 三层回退(现有) |
| 卖点 | 免费/低价 + **精细分流** | **稳定** |
| 变现 | 广告(激励视频,走机场节点分散出口 IP) | 订阅 |

核心取舍:低价区不保证速度,但功能最全(智能分流);中价区保证延迟,分流粒度较粗。

## 2. 铁律:同一时刻只有一条系统隧道

iOS(`NEPacketTunnelProvider`)和安卓(`VpnService`)都**只允许一条 VPN 隧道同时活跃**。因此:
- 两个引擎是**运行时互斥**(二选一),不能同时连;
- 切换 = 先拆掉当前隧道,再起另一个;
- 用户选低价节点 → sing-box 引擎;选付费节点 → AmneziaWG 引擎;免费用户只可能连机场,不会切换。

## 3. 分流能力矩阵(关键)

分流粒度**取决于当前用哪个引擎 + 什么平台**,不是全局统一。

| 分流方式 | 判据 | 低价区(sing-box) | 中价区(AmneziaWG) | 备注 |
|---|---|---|---|---|
| 按 **IP 段** | 目的 IP | ✅ | ✅(现有智能模式) | WG 的 AllowedIPs 只能到这级 |
| 按 **域名规则** | DNS/SNI 嗅探 | ✅ **原生** | ❌ | 这是 sing-box 独有 |
| 按 **应用** | Bundle/包名 | ✅ 安卓 / ❌ iOS | ✅ 安卓 / ❌ iOS | 在 VpnService 层实现,与引擎无关 |

**为什么 iOS 不能按应用**:`NEPacketTunnelProvider` 只拿到 IP 数据包,系统**不告诉你包是哪个 App 发的**(按应用路由是 MDM 托管设备专属)。但 iOS **能做域名规则分流**——拦 DNS + 读 TLS ClientHello 的 SNI,按域名判定。效果上接近「按应用」(微信只连腾讯域名、YouTube 只连 google 域名)。这正是 Clash/sing-box/Surge 在 iOS 上的做法。

**为什么 AmneziaWG 区不能按域名**:WireGuard 的 `AllowedIPs` 只认 IP 段。想在中价区也做域名分流,唯一办法是付费节点也改用 sing-box 出站——但 **sing-box 不支持 AmneziaWG 的混淆**(只支持标准 WireGuard),会丢掉抗封锁能力。**中价区取舍:抗封锁 vs 域名分流,二选一;当前选抗封锁,维持 IP 段级。**

## 4. 客户端引擎抽象

```
abstract VpnEngine {
  Future<void> start(EngineConfig cfg)   // cfg 含节点信息 + 分流规则
  Future<void> stop()
  Stream<VpnStage> stage
  Future<List<int>> transferRxTx()       // 用量计量
  EngineCapabilities get caps            // 该引擎支持哪些分流粒度(供 UI 决定显示什么)
}
  ├─ AmneziaWgEngine   // 现有逻辑收进来:直连/中继/CF 三层 + IP 段智能路由
  └─ ProxyCoreEngine   // 新:包 sing-box(gomobile),支持域名规则 + 机场协议
```

- `VpnProvider` 里把写死的 `AmneziaWG.instance` 换成 `VpnEngine current`,按所选节点的 `tier`(paid/free)选引擎。
- **应用分流(安卓)** 做在共享的 VpnService 封装层(`addAllowedApplication`/`addDisallowedApplication`),两个引擎都能叠加。
- **用量计量/试用/广告** 等逻辑保持引擎无关(现有 `VpnProvider` 已经是这个结构)。

### flavor(编译期)
- **pure**:只注册 `AmneziaWgEngine`,不打包 sing-box,隐藏免费区/广告 UI → 纯净付费版,包更小、iOS 过审故事干净。
- **hybrid**:两个引擎都在,含免费区 + 广告。
- 一套代码 + `--dart-define=HYBRID`,不用两条 git 分支。

## 5. 免费节点管道(扫描器 → Supabase → App)

```
[扫描器,必须在中国境内]  每 N 分钟
   抓源 → sing-box 实测(延迟/抖动/丢包/带宽)→ 打分 → 取 top-N
   已完成:D:\projects\airportscanner(build_singbox_config 直接产出 sing-box outbound)
      ↓ push
[Supabase: free_nodes 表]  直接存 sing-box outbound JSON(端上零解析)
      ↓ App 拉取(带 JWT,不做成公开免费节点 API)
[App: ProxyCoreEngine]
```

- ⚠️ **扫描器必须留在中国境内**:测的是「从中国到节点」的可达性,搬到海外榜单对用户无意义。需一台国内常驻机器(注意在国内 VPS 跑批量翻墙连接的合规风险,自行权衡)。
- 免费节点质量差(实测香港 0、新加坡少、多为欧洲 1000ms+),免费区体验会差 → 客服/差评会涨,这既是成本也是「逼升级」的设计。
- 库里存已算好的 sing-box outbound + 元数据(country/score/latency),App 直接用。

## 6. 广告受限隧道(依赖 sing-box)

免费用户时长耗尽、未连接时要看激励视频换时长 —— 但国内直连 AdMob 看不了。方案:
- 建一条 **只放行 Google 广告域名**的 sing-box 隧道(域名规则:`*.doubleclick.net` `*.googlesyndication.com` `*.googleadservices.com`),走**免费机场节点**;
- 看完激励视频拿奖励,再断开/转正常。
- 好处:出口 IP **分散在几十个机场 IP**(而非集中在自己 7 台节点)→ 大幅降低被 Google 判「无效流量」封号的风险;广告 700ms/2Mbps 完全够看。
- 长期正解仍是**接国内广告联盟(穿山甲/优量汇)**,受限隧道是过渡。

## 7. 关键约束清单(实施时反复对照)

1. 单系统隧道 → 引擎运行时互斥,切换要先拆后起。
2. iOS 无按应用分流(除非 MDM);但有域名规则分流。
3. AmneziaWG 区无域名分流;要域名分流必须 sing-box,但会丢 AWG 混淆。
4. sing-box 的 WireGuard 出站 = 标准 WG,国内会被 GFW 识别;机场节点靠自身协议(vless/trojan/hysteria)抗封锁。
5. 免费机场节点不稳、香港稀缺;广告/域名嗅探会再叠加延迟。
6. 原生插件工程量大(gomobile 编译 sing-box + 安卓 VpnService + iOS Network Extension),数周级。
7. 应用分流的「选择应用」UI + 偏好持久化,安卓专属。

## 8. 实施阶段(建议顺序)

- **阶段 0 — 地基(纯 Dart,零风险)**:把 `VpnProvider` 重构成引擎无关,抽出 `VpnEngine` 接口,现有 AWG 逻辑收进 `AmneziaWgEngine`;给节点加 `tier` 字段。
- **阶段 1 — 免费节点后端**:扫描器产品化(国内常驻 + push)→ Supabase `free_nodes` 表 + App 拉取接口(JWT 保护)。此时还没接 sing-box,只是有了节点池。
- **阶段 2 — sing-box 原生插件**:gomobile 编译 libbox,封装安卓 VpnService / iOS PacketTunnelProvider,做成 Flutter 插件;实现 `ProxyCoreEngine`。低价区可连通。
- **阶段 3 — 分流规则**:sing-box route rules(域名/IP);安卓 VpnService 应用白/黑名单(两引擎共享);UI 按引擎 `caps` 显示可用选项。
- **阶段 4 — 广告受限隧道**:基于 sing-box 域名规则,只放行 Google 广告域名走机场节点。
- **阶段 5 — flavor 化**:pure/hybrid 两套构建。

## 9. 相关文件 / 现状

- 现有引擎:`client/lib/providers/vpn_provider.dart`(直连/中继/CF 三层、智能路由、用量、试用、广告都在这)
- 现有广告:`client/lib/services/ad_service.dart`(AdMob:开屏 + 激励)
- 扫描器:`D:\projects\airportscanner`(已完成,含 `build_singbox_config`、sing-box 实测、Clash/订阅产出)
- 节点表(现有付费):Supabase `vpn_servers` / `vpn_device_peers`
- 免费节点表(待建):`free_nodes`
