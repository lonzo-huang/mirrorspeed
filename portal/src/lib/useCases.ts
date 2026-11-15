// 场景落地页数据（中英双语，原创内容）。
//
// 这类页面针对的是「用户真正会搜的问题」和「AI 会被问到的问题」：
//   - 为什么 ChatGPT 老是转圈 / 加速器怎么选 / 游戏延迟高怎么办
// 写法原则：先讲清问题成因（可验证的网络常识），再说本产品如何处理，
// 不做无法验证的承诺（例如「保证解锁某某流媒体」——平台会主动封锁，谁都保证不了）。
//
// 新增场景：在 USE_CASES 里加一条即可，/use-cases 与 /cn/use-cases 两侧自动生效。

export interface UseCaseSection { h: string; p: string }
export interface UseCaseFaq { q: string; a: string }

export interface UseCaseContent {
  title: string          // <title> 用
  h1: string             // 页面大标题
  summary: string        // meta description + 页头副标题
  intro: string
  sections: UseCaseSection[]
  faq: UseCaseFaq[]
}

export interface UseCase {
  slug: string
  en: UseCaseContent
  zh: UseCaseContent
}

export const USE_CASES: UseCase[] = [
  // ── AI 工具 ────────────────────────────────────────────────────────────────
  {
    slug: 'ai-tools',
    en: {
      title: 'VPN for ChatGPT, Claude and Gemini — Why Connections Drop',
      h1: 'Using ChatGPT, Claude and Gemini',
      summary:
        'Why AI chat connections stall or drop mid-answer, what actually causes it, and how to get a stable connection to ChatGPT, Claude and Gemini.',
      intro:
        'AI chat tools are unusually sensitive to connection quality. They stream the answer token by token over a single long-lived connection, so a two-second interruption does not slow the answer down — it kills it. Here is what actually goes wrong, and what helps.',
      sections: [
        {
          h: 'Streaming answers break on any interruption',
          p: 'ChatGPT, Claude and Gemini send their replies as a stream rather than one finished page. That connection has to stay open for the whole answer. A brief packet loss spike that you would never notice while browsing is enough to cut the stream, which is why an answer stops halfway and never resumes.',
        },
        {
          h: 'Shared IP addresses trigger verification',
          p: 'Most VPN services put hundreds of users behind one shared IP. AI providers see a large volume of requests from a single address and respond with CAPTCHAs, rate limits, or outright blocks. The more people share your exit address, the worse this gets. MirrorSpeed assigns each device its own address inside the tunnel rather than pooling everyone behind one.',
        },
        {
          h: 'Latency compounds over a long conversation',
          p: 'Every message in a conversation is a new round trip. A node 250 ms away adds half a second of dead time to every exchange before the model even starts generating. Over a long session that is the difference between a tool that feels instant and one that feels sluggish. Picking a node that is geographically close to you matters more than picking one in any particular country.',
        },
        {
          h: 'What to do in the app',
          p: 'Leave automatic node selection on — it scores nodes by live latency and current load, which is usually better than guessing. If an answer stalls repeatedly, switch to a different node rather than reconnecting to the same one. If direct connection is being blocked on your network, the app falls back to a relay over standard HTTPS automatically, which is slower but far harder to interfere with.',
        },
      ],
      faq: [
        {
          q: 'Why does ChatGPT stop halfway through an answer?',
          a: 'The answer arrives as a stream over one long-lived connection. If that connection is interrupted — by packet loss, a network switch, or an idle timeout — the stream ends and the remaining text is lost. A stable connection matters more here than raw bandwidth.',
        },
        {
          q: 'Why am I asked to verify I am human?',
          a: 'That is usually triggered by the IP address you are coming from, not by anything you did. Addresses shared by many users attract rate limits and verification challenges. An address used by fewer people is much less likely to be flagged.',
        },
        {
          q: 'Which node should I pick for AI tools?',
          a: 'The closest one that is not busy. Automatic selection handles this for you by scoring live latency and load. Distance sets a floor on round-trip time that no amount of bandwidth can overcome.',
        },
      ],
    },
    zh: {
      title: 'ChatGPT 加速 — 为什么回答到一半就断，怎么连才稳',
      h1: '使用 ChatGPT、Claude 与 Gemini',
      summary:
        'AI 对话为什么总是转圈、回答到一半断掉？讲清真正的成因，以及怎样才能稳定使用 ChatGPT、Claude 和 Gemini。',
      intro:
        'AI 对话工具对连接质量格外敏感。它的回答是一个字一个字「流式」传回来的，全程依赖同一条长连接——所以两秒的中断不会让回答变慢，而是直接让它中断。下面说清楚问题出在哪，以及什么做法真正有用。',
      sections: [
        {
          h: '流式回答经不起任何中断',
          p: 'ChatGPT、Claude、Gemini 不是把整篇答案生成好再发给你，而是边生成边推送，整个过程要靠同一条连接撑住。平时浏览网页根本察觉不到的一次丢包，就足以把这条流打断——这就是「回答到一半不动了，而且不会自己恢复」的原因。',
        },
        {
          h: '共用 IP 会触发人机验证',
          p: '多数加速服务让几百个用户共用一个出口 IP。AI 平台看到同一个地址涌来大量请求，就会用验证码、限流甚至直接封锁来应对。共用的人越多，被拦的概率越高。镜速加速器为每台设备在隧道内分配独立地址，而不是把所有人挤在一个出口后面。',
        },
        {
          h: '长对话里延迟会累积',
          p: '对话中的每一条消息都是一次往返。如果节点离你有 250 毫秒，那么在模型开始生成之前，每一轮交互都要先白等半秒。一次长对话下来，这就是「跟手」和「卡顿」的差别。选一个地理上离你近的节点，比纠结选哪个国家更重要。',
        },
        {
          h: '在 App 里该怎么设置',
          p: '保持「智能选择」开启——它按实时延迟和当前负载给节点打分，通常比手动猜更准。如果反复在同一处断掉，换一个节点，而不是对着同一个节点反复重连。如果你的网络在阻断直连，App 会自动回退到走标准 HTTPS 的中继通道：速度慢一些，但更难被干扰。',
        },
      ],
      faq: [
        {
          q: 'ChatGPT 为什么回答到一半就停了？',
          a: '答案是通过一条长连接流式传回的。这条连接一旦被打断——丢包、切换网络、连接闲置超时都可能——流就结束了，剩下的内容不会再送达。这种场景里，连接稳不稳比带宽大不大更关键。',
        },
        {
          q: '为什么总让我做人机验证？',
          a: '多半是你的出口 IP 导致的，和你的操作无关。被大量用户共用的地址更容易触发限流和验证。使用人数更少的地址，被标记的概率要低得多。',
        },
        {
          q: '用 AI 工具该选哪个节点？',
          a: '选离你最近、且不繁忙的那个。开启智能选择会自动按实时延迟和负载帮你挑。物理距离决定了往返延迟的下限，这一点再大的带宽也补不回来。',
        },
      ],
    },
  },

  // ── 流媒体 ────────────────────────────────────────────────────────────────
  {
    slug: 'streaming',
    en: {
      title: 'VPN for Streaming — Why 4K Buffers and What Fixes It',
      h1: 'Streaming video without buffering',
      summary:
        'What actually causes 4K video to buffer or drop resolution over a VPN, and how to get the steady bandwidth streaming needs.',
      intro:
        '4K video needs roughly 25 Mbps held steadily for the whole programme. Streaming players react to any dip by dropping resolution or pausing to rebuffer, so consistency matters more than peak speed.',
      sections: [
        {
          h: 'Steady bandwidth beats fast bandwidth',
          p: 'A connection that bursts to 200 Mbps and then sags to 10 Mbps will buffer, while a flat 40 Mbps will not. Players measure throughput continuously and step the quality down the moment they predict the buffer will run dry. This is why a "fast" connection can still look worse than a slower, steadier one.',
        },
        {
          h: 'Busy nodes are the usual culprit at peak hours',
          p: 'Evening is when everyone streams. On a node that is already saturated, your share of the available bandwidth drops regardless of how fast the server itself is. Checking the load indicator and moving to a quieter node usually fixes evening buffering immediately.',
        },
        {
          h: 'Per-user speed limits',
          p: 'Many services throttle each user, and some throttle video traffic specifically. MirrorSpeed does not rate-limit paid accounts or treat video differently from any other traffic — the ceiling is 1000 Mbps per user, which is far above what any streaming service asks for. Free accounts run on shared best-effort nodes and are not suitable for 4K.',
        },
        {
          h: 'About region availability',
          p: 'Being able to reach a service and being entitled to watch a particular title are different things. Streaming platforms actively detect and block VPN traffic, and what works can change week to week. We do not promise that any specific platform or catalogue will be available, and you should treat any service that guarantees it with suspicion.',
        },
      ],
      faq: [
        {
          q: 'Why does my video drop to a lower resolution?',
          a: 'The player predicted that the buffer would run out at the current quality. It is reacting to a dip in throughput, not to your average speed. A steadier connection, or a less busy node, is the fix.',
        },
        {
          q: 'Does MirrorSpeed slow down video traffic?',
          a: 'No. Paid accounts are not rate-limited and video is not treated differently from any other traffic. Free accounts use shared best-effort nodes, which are not built for 4K.',
        },
        {
          q: 'Will it unblock a specific streaming service?',
          a: 'We do not make that promise. Streaming platforms actively detect VPN traffic and what works changes over time. Any provider guaranteeing permanent access to a named platform is overstating what it can control.',
        },
      ],
    },
    zh: {
      title: '流媒体加速 — 4K 为什么缓冲、怎么才能不卡',
      h1: '看视频不缓冲',
      summary: '用加速器看 4K 为什么还会缓冲、掉画质？解释真正的成因，以及怎样获得视频需要的稳定带宽。',
      intro:
        '4K 视频大约需要 25 Mbps 并且全程稳定。播放器只要察觉速度下滑，就会降画质或者暂停缓冲——所以「稳」比「峰值高」更重要。',
      sections: [
        {
          h: '稳定的带宽胜过很快的带宽',
          p: '一条忽而 200 Mbps、忽而掉到 10 Mbps 的线路会卡；而稳定在 40 Mbps 的线路不会。播放器持续测量吞吐，一旦预判缓冲区要见底就立刻降画质。这就是为什么「测速很快」的连接，观感反而不如一条更慢但更稳的连接。',
        },
        {
          h: '晚高峰卡顿，多半是节点挤了',
          p: '晚上是所有人都在看视频的时间。如果节点本身已经跑满，不管服务器带宽多大，分到你头上的都会变少。看一眼节点的负载标识，换一个空闲的节点，晚高峰的卡顿通常当场就好。',
        },
        {
          h: '有没有针对单用户限速',
          p: '很多服务会对每个用户限速，有些还专门针对视频流量限速。镜速加速器不对付费账号限速，也不对视频流量区别对待——单用户上限是 1000 Mbps，远高于任何流媒体平台的需求。免费账号使用的是共享的尽力而为节点，不适合看 4K。',
        },
        {
          h: '关于地区可用性',
          p: '「能连上某个服务」和「有权观看某部片子」是两回事。流媒体平台会主动识别并封锁加速流量，哪些线路可用可能每周都在变。我们不承诺任何特定平台或片库一定可用——任何敢做这种保证的服务，都值得你打个问号。',
        },
      ],
      faq: [
        {
          q: '为什么视频会自动降到低画质？',
          a: '播放器判断按当前画质继续播会把缓冲区耗尽。它反应的是速度的一次下滑，而不是你的平均速度。解决办法是换一条更稳的线路，或者换一个不那么繁忙的节点。',
        },
        {
          q: '镜速加速器会限制视频速度吗？',
          a: '不会。付费账号不限速，视频流量也不会被区别对待。免费账号用的是共享的尽力而为节点，本身就不是为 4K 准备的。',
        },
        {
          q: '能解锁某个指定的流媒体平台吗？',
          a: '我们不做这个承诺。流媒体平台会主动识别加速流量，可用情况随时间变化。任何声称「永久解锁某平台」的服务，都夸大了它实际能控制的范围。',
        },
      ],
    },
  },

  // ── 游戏 ──────────────────────────────────────────────────────────────────
  {
    slug: 'gaming',
    en: {
      title: 'VPN for Gaming — How to Actually Lower Ping',
      h1: 'Lowering ping in online games',
      summary:
        'What ping is made of, why a VPN can sometimes lower it, when it cannot, and how to set it up for international game servers.',
      intro:
        'Game acceleration does not make your connection faster in the way a download is fast. It tries to give your packets a shorter, steadier path to the game server. Understanding which part of ping you can change — and which you cannot — saves a lot of wasted effort.',
      sections: [
        {
          h: 'Distance sets a floor you cannot beat',
          p: 'Light travels through fibre at about two-thirds of its speed in vacuum. Shanghai to the US west coast is roughly 60 to 80 ms each way no matter what you pay. If a service advertises a ping lower than physics allows for that distance, it is measuring something else. What can be improved is everything above that floor: routing detours, congestion and queueing.',
        },
        {
          h: 'Packet loss hurts more than high ping',
          p: 'A steady 150 ms is playable; 80 ms with intermittent loss is not. Loss shows up as rubber-banding, skipped animations and dropped connections mid-match. Routes are not all equal here — two paths with similar ping can behave completely differently under load.',
        },
        {
          h: 'Jitter is what breaks muscle memory',
          p: 'Jitter is ping that keeps changing. Players adapt to consistent delay surprisingly well, but not to delay that swings between 40 and 200 ms. A stable route at moderate latency generally feels better than an unstable fast one.',
        },
        {
          h: 'Setting it up',
          p: 'Connect to a node in or near the region the game server is in, not the one closest to you. Use per-app routing so only the game goes through the tunnel and everything else stays on your normal connection — this reduces the load and avoids odd behaviour in other apps. Test in a practice or casual match before a ranked one.',
        },
      ],
      faq: [
        {
          q: 'Can a VPN lower my ping?',
          a: 'Sometimes. It cannot beat the physical distance to the server, but it can avoid congested or roundabout routing, which is often where the extra latency comes from. If your current route is already direct and uncongested, expect little or no gain.',
        },
        {
          q: 'Which node should I connect to for an overseas game server?',
          a: 'The one closest to the game server, not the one closest to you. The goal is to shorten the path between the tunnel exit and the server.',
        },
        {
          q: 'Should I route the whole system or just the game?',
          a: 'Just the game, using per-app routing. It keeps everything else on your normal connection and avoids unexpected behaviour in other applications.',
        },
      ],
    },
    zh: {
      title: '游戏加速 — 延迟到底能降多少，怎么设置才对',
      h1: '降低国际服游戏延迟',
      summary: '延迟由哪几部分组成、加速器什么时候能降、什么时候降不了，以及连国际服该怎么设置。',
      intro:
        '游戏加速并不是把网络「变快」——那是下载意义上的快。它做的是给你的数据包找一条更短、更稳的路到游戏服务器。弄清楚延迟里哪部分能改、哪部分改不了，能少走很多弯路。',
      sections: [
        {
          h: '物理距离是改不掉的下限',
          p: '光在光纤里的速度约为真空中的三分之二。上海到美国西海岸单程就注定有 60～80 毫秒，花多少钱都一样。如果某个服务宣称的延迟低于这个距离的物理极限，那它测的一定是别的东西。真正能优化的是下限之上的部分：绕路、拥堵和排队。',
        },
        {
          h: '丢包比高延迟更致命',
          p: '稳定的 150 毫秒是能玩的；80 毫秒但时不时丢包则没法玩。丢包的表现是瞬移、技能动作吞掉、团战中途掉线。不同线路在这方面差别很大——两条延迟相近的路径，在高负载下的表现可能完全不同。',
        },
        {
          h: '抖动才是毁掉手感的东西',
          p: '抖动就是延迟忽高忽低。人对稳定的延迟适应得出奇地好，但对在 40 和 200 毫秒之间来回跳的延迟束手无策。一条延迟中等但稳定的线路，手感通常好过一条很快却不稳的线路。',
        },
        {
          h: '怎么设置',
          p: '连接到游戏服务器所在区域（或附近）的节点，而不是离你最近的节点。用分应用代理，只让游戏走加速、其他应用保持原网络——这样既减轻负载，也避免别的软件出现异常。正式排位前，先在训练或休闲模式里试一局。',
        },
      ],
      faq: [
        {
          q: '加速器真的能降低延迟吗？',
          a: '有时候能。它跨不过你与服务器之间的物理距离，但可以绕开拥堵或绕远的路由——多余的延迟常常正是来自这里。如果你当前的线路本来就直连且不拥堵，提升会很有限甚至没有。',
        },
        {
          q: '玩国际服该连哪个节点？',
          a: '连离游戏服务器最近的，而不是离你最近的。目标是缩短「隧道出口到服务器」这一段的距离。',
        },
        {
          q: '该全局加速还是只加速游戏？',
          a: '只加速游戏，用分应用代理。这样其余流量仍走原网络，也不会让别的软件出现意外状况。',
        },
      ],
    },
  },

  // ── 如何挑选 ──────────────────────────────────────────────────────────────
  {
    slug: 'how-to-choose',
    en: {
      title: 'How to Choose a VPN — What Actually Matters',
      h1: 'How to choose a VPN',
      summary:
        'The criteria that actually affect daily use — logging, speed limits, device count, protocol and refund terms — and the claims worth ignoring.',
      intro:
        'Most VPN comparisons rank providers by numbers that do not affect how the product feels to use. These are the criteria that do, and how to check each one yourself rather than taking anyone\'s word for it.',
      sections: [
        {
          h: 'Check what is logged, not whether it says "no logs"',
          p: 'Every provider says "no logs". The useful question is what specifically is not recorded: browsing history, traffic destinations, DNS queries, and the IP address you connect from. A policy that lists these individually is more meaningful than a slogan. If a provider claims an independent audit, look for the auditor\'s name and the report itself — a claim without a linked report tells you nothing.',
        },
        {
          h: 'Look for per-user speed limits',
          p: 'Advertised server bandwidth is not what you get. What matters is whether the provider limits each user, and whether it treats some traffic (video, downloads) differently. This is usually buried in the terms rather than on the pricing page.',
        },
        {
          h: 'Count devices and check what happens at the limit',
          p: 'Household use adds up quickly: phone, laptop, tablet, TV. Check the simultaneous device limit, and whether exceeding it blocks the new device or silently disconnects an old one.',
        },
        {
          h: 'Protocol matters where networks interfere',
          p: 'On an ordinary network almost any modern protocol works. Where traffic is actively filtered, the protocol decides whether you connect at all. Standard WireGuard is fast but has a recognisable handshake; providers that operate in filtered networks add obfuscation on top, or fall back to tunnelling over ordinary HTTPS. A provider offering exactly one protocol and no fallback has no answer when that protocol is blocked.',
        },
        {
          h: 'Test during your own peak hours',
          p: 'Speed at 2pm tells you little about 9pm, when everyone is online. Use the refund window to test at the times you will actually be using it, on the devices you will actually use. A 7-day refund policy exists so you can do exactly this.',
        },
        {
          h: 'Be sceptical of free, and of unverifiable numbers',
          p: 'Running servers costs money. If a service is free with no paid tier and no limits, the revenue is coming from somewhere — usually advertising built on usage data. Equally, treat self-reported ratings, user counts and server counts as marketing until you can verify them somewhere independent, such as an app store listing.',
        },
      ],
      faq: [
        {
          q: 'Is a free VPN safe?',
          a: 'It depends on how it is funded. A free tier offered alongside paid plans is paid for by the paid users. A service that is free with no paid option has to earn money another way, and that usually means monetising usage data or injecting advertising.',
        },
        {
          q: 'How many devices do I actually need?',
          a: 'Count the devices you want connected at the same time, not the ones you own. A typical household runs two to four at once; four to eight covers most families comfortably.',
        },
        {
          q: 'Does a bigger server count mean a better service?',
          a: 'Not by itself. What matters is whether there is a node near you, how busy it is at the hours you use it, and how much bandwidth each node actually has. A handful of well-provisioned nodes in the right places beats a long list of saturated ones.',
        },
      ],
    },
    zh: {
      title: '加速器怎么选 — 哪些指标真的有用',
      h1: '加速器怎么选',
      summary: '真正影响日常使用的几项标准——日志、限速、设备数、协议与退款条款——以及可以直接忽略的宣传话术。',
      intro:
        '大多数加速器对比，比的是一些并不影响实际体验的数字。下面是真正有影响的几项，以及怎样自己去核实，而不是听谁的一面之词。',
      sections: [
        {
          h: '看它「不记录什么」，而不是看它说没说「零日志」',
          p: '所有服务都会说「零日志」。有用的问法是：具体不记录哪些——浏览历史、流量访问的目标、DNS 查询，以及你连接时用的 IP 地址。逐条列出来的政策，比一句口号有意义得多。如果声称做过独立审计，请找审计机构的名字和报告本身；只有声明、没有报告链接，说明不了任何问题。',
        },
        {
          h: '查有没有针对单用户的限速',
          p: '宣传页上的服务器带宽不等于你能用到的带宽。关键是服务商有没有对每个用户限速，以及会不会对某类流量（视频、下载）区别对待。这些内容通常写在条款里，而不是价格页上。',
        },
        {
          h: '数清设备数，并弄清超限会怎样',
          p: '家里的设备很快就会凑够：手机、笔记本、平板、电视。要看同时在线的设备上限，以及超出后是拦住新设备，还是悄悄把旧设备踢下线。',
        },
        {
          h: '在受干扰的网络里，协议决定成败',
          p: '在普通网络下，现代协议基本都能用。但在流量被主动过滤的网络里，协议直接决定你能不能连上。标准 WireGuard 速度快，但握手特征明显；面向这类网络的服务会在其上叠加混淆，或者回退到走普通 HTTPS 的通道。只提供单一协议、没有任何回退方案的服务，一旦该协议被封就没有后手。',
        },
        {
          h: '在你自己的高峰时段测试',
          p: '下午两点的速度说明不了晚上九点的情况——那时所有人都在线。利用退款期，在你真正会用的时间、用你真正会用的设备去测。7 天退款期的意义正在于此。',
        },
        {
          h: '对「免费」和无法核实的数字保持警惕',
          p: '服务器是要花钱的。如果一个服务完全免费、没有付费档也不设限制，收入必然来自别处——通常是基于使用数据的广告。同理，自报的评分、用户数、节点数在你能从独立渠道（比如应用商店页面）核实之前，都只能当作宣传。',
        },
      ],
      faq: [
        {
          q: '免费加速器安全吗？',
          a: '取决于它靠什么赚钱。与付费套餐并存的免费档，成本由付费用户承担。而一个完全免费、没有付费选项的服务，必须用别的方式赚钱，通常意味着把使用数据变现或植入广告。',
        },
        {
          q: '我到底需要几台设备？',
          a: '数的是你希望同时在线的设备，而不是你拥有的设备。一般家庭同时在用的是 2～4 台；4～8 台足以覆盖绝大多数家庭。',
        },
        {
          q: '节点数越多就越好吗？',
          a: '不一定。真正重要的是有没有离你近的节点、你常用的时段它忙不忙、以及每个节点实际有多少带宽。几个位置合适、带宽充足的节点，胜过一长串挤满人的节点。',
        },
      ],
    },
  },
]

export const getUseCase = (slug: string) => USE_CASES.find(u => u.slug === slug)
