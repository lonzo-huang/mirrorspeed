'use client'

import { createContext, useContext, useEffect, useState, type ReactNode } from "react";

export type Lang = "en" | "zh" | "de" | "fr" | "it" | "es" | "uk" | "ja";

const dict = {
  en: {
    nav: { servers: "Servers", pricing: "Pricing", download: "Download", faq: "FAQ", dashboard: "Dashboard", login: "Login", signup: "Sign Up" },
    hero: {
      badge: "Global Network Online",
      title1: "Reflection is",
      title2: "Instant",
      sub: "Mirror-latency VPN by Mirror Group. Zero friction, total privacy, absolute speed.",
      cta1: "Start Mirroring",
      cta2: "View Live Status",
      trusted: "Trusted by 3M+ users worldwide",
    },
    stats: [
      { value: "3M+", label: "Active Users" },
      { value: "45+", label: "Global Locations" },
      { value: "99.9%", label: "Uptime SLA" },
      { value: "10Gbps", label: "Node Bandwidth" },
    ],
    howItWorks: {
      title: "Up in 60 Seconds",
      sub: "Three steps from signup to full-speed browsing.",
      steps: [
        { title: "Create Account", desc: "Sign up in seconds. No personal info required beyond your email." },
        { title: "Copy Your URL", desc: "Grab your Clash subscription URL from the dashboard with one click." },
        { title: "Connect & Browse", desc: "Paste into any WireGuard or Clash client. Auto-selects the fastest node." },
      ],
    },
    features: {
      title: "Why MirrorSpeed",
      sub: "Engineered for speed-of-light reflection.",
      items: [
        { t: "WireGuard Core", d: "Modern protocol with state-of-the-art cryptography and minimal attack surface." },
        { t: "No-Logs Policy", d: "Independently audited zero-logs. Your traffic is your business, period." },
        { t: "Multi-Device", d: "Up to 8 devices on one account. Mac, Windows, iOS, Android, Linux." },
        { t: "Auto Failover", d: "Clash subscription auto-selects the fastest node in real time." },
        { t: "Global Edge", d: "45+ locations across Asia, Americas, and Europe." },
        { t: "24/7 Support", d: "Real engineers, real responses, real fast. Average reply in under 5 min." },
      ],
    },
    servers: { title: "Live Server Matrix", sub: "Real-time telemetry from our global cluster.", load: "Load", latency: "Latency", uptime: "Uptime", online: "Online" },
    testimonials: {
      title: "Trusted Worldwide",
      sub: "Real users. Real speeds.",
      items: [
        { name: "Alex T.", role: "Developer, Shanghai", body: "HK01 consistently hits 14ms for me. Faster than any competitor I've tried — and I've tried them all." },
        { name: "Sarah M.", role: "Freelancer, Beijing", body: "The Clash integration is flawless. Set it once, forget it. I haven't had a single drop in three months." },
        { name: "Ken W.", role: "Startup Founder, Shenzhen", body: "8 devices on one account at this price is unbeatable. My entire team switched over the same day." },
      ],
    },
    pricing: {
      title: "Choose Your Reflection", sub: "Transparent pricing. Cancel anytime.",
      popular: "Most Popular", select: "Select Plan", featured: "Get Started",
      plans: [
        { name: "Yearly",    price: "$1",    per: "/mo", desc: "Billed $12/yr",         feats: ["All 45+ locations", "WireGuard + WebSocket relay", "Unlimited devices", "24/7 support", "7-day refund"] },
        { name: "2-Year",    price: "$0.90", per: "/mo", desc: "Billed $21.60/2 yrs",   feats: ["Everything in Yearly", "Dedicated IP option", "Stealth mode", "Priority queue"] },
        { name: "Monthly",   price: "$3",    per: "/mo", desc: "Billed monthly",         feats: ["All 45+ locations", "WireGuard + WebSocket relay", "Unlimited devices", "24/7 support"] },
        { name: "Quarterly", price: "$1.50", per: "/mo", desc: "Billed $4.50/quarter",  feats: ["All locations", "WireGuard + WebSocket relay", "Unlimited devices", "24/7 support"] },
      ],
    },
    faq: {
      title: "Frequently Asked",
      items: [
        { q: "How fast is MirrorSpeed?", a: "Sub-20ms latency to Hong Kong nodes from mainland China, sub-50ms across most of Asia." },
        { q: "Do you keep logs?", a: "No. Independently audited zero-logs policy — we cannot see your traffic even if we wanted to." },
        { q: "Which clients work?", a: "Any WireGuard or Clash-compatible client on Mac, Windows, iOS, Android, Linux, and OpenWrt." },
        { q: "Refunds?", a: "7-day no-questions-asked money-back guarantee on all plans." },
        { q: "How many devices can I connect?", a: "Monthly plans include 3 devices. Yearly and 2-Year plans support up to 8 simultaneous devices." },
      ],
    },
    cta: { title: "Start Reflecting Today", sub: "7-day money-back guarantee. No questions asked.", btn: "Get Started Free" },
    auth: {
      loginTitle: "Welcome back", signupTitle: "Create your account",
      google: "Continue with Google", microsoft: "Continue with Microsoft",
      orEmail: "Or email", email: "Email address", password: "Password",
      submit: "Send Code", switchToSignup: "No account? Sign up", switchToLogin: "Have an account? Log in",
      terms: "By continuing you agree to our Terms and Privacy Policy.",
      otpSent: "Check your inbox", enterOtp: "Enter the 8-digit code from your email",
      otpPlaceholder: "00000000", verify: "Verify & Sign In", resend: "Resend code",
      loading: "Loading...", sending: "Sending...", redirecting: "Signing in...", invalidOtp: "Invalid code, please try again.",
    },
    dash: {
      welcome: "Welcome back", plan: "Active Plan", expires: "Expires in", days: "days",
      subUrl: "Clash Subscription URL", encrypted: "Encrypted", copy: "Copy", copied: "Copied!",
      devices: "Connected Devices", account: "Account", renew: "Renew Plan", billing: "Billing History",
      manage: "Update billing info or upgrade plan.", logout: "Log out",
      usage: "Data Usage", thisMonth: "This month",
      overview: "Overview", myDevices: "My Devices", billingNav: "Billing", adminLabel: "Admin", logoutBtn: "Log out",
    },
    footer: { tagline: "The infrastructure of the open mirror-web.", product: "Product", legal: "Legal", support: "Support", contact: "Contact", disclaimer: "Disclaimer" },
    download: {
      title: "Download MirrorSpeed",
      sub: "Recommended Clash-based clients for every platform. One subscription URL works everywhere.",
      step: "Quick start",
      steps: ["Install the client for your platform below.", "Copy your subscription URL from the Dashboard.", "Paste it into the client and pick the fastest node."],
      install: "Download", guide: "Setup guide", recommended: "Recommended",
    },
    disclaimer: {
      title: "Disclaimer & Acceptable Use",
      updated: "Last updated: May 19, 2026",
      intro: "Please read this disclaimer carefully before using MirrorSpeed. By accessing or using our service, you agree to be bound by the terms below.",
      sections: [
        { h: "1. Service Purpose", p: "MirrorSpeed is provided solely to protect user privacy, secure data transmission on untrusted networks, and improve connection performance. It is not intended to facilitate any unlawful activity." },
        { h: "2. Legal Compliance", p: "You are solely responsible for complying with all applicable laws and regulations in your jurisdiction. The use of VPN services may be restricted or regulated in certain countries; please verify local laws before subscribing." },
        { h: "3. Prohibited Activities", p: "You must not use MirrorSpeed for: unauthorized access to systems, distribution of malware, copyright infringement, fraud, harassment, child exploitation material, or any activity that violates the rights of others." },
        { h: "4. No Warranty", p: "The service is provided \"as is\" without warranties of any kind. We do not guarantee uninterrupted availability, specific speeds, or fitness for any particular purpose." },
        { h: "5. Limitation of Liability", p: "To the maximum extent permitted by law, Mirror Group shall not be liable for any indirect, incidental, or consequential damages arising from the use or inability to use the service." },
        { h: "6. Privacy & Logs", p: "We operate a strict no-logs policy. We do not record browsing history, traffic destination, DNS queries, or IP addresses of connected users. Minimal billing metadata is retained as required by law." },
        { h: "7. Account Termination", p: "We reserve the right to suspend or terminate accounts that violate these terms without refund, including but not limited to abusive traffic patterns or fraudulent payment." },
        { h: "8. Contact", p: "For questions regarding this disclaimer, contact support@mirrorspeed.io." },
      ],
    },
  },

  zh: {
    nav: { servers: "服务器", pricing: "价格", download: "下载", faq: "常见问题", dashboard: "控制台", login: "登录", signup: "注册" },
    hero: {
      badge: "全球节点在线",
      title1: "镜面反射",
      title2: "即时极速",
      sub: "MirrorSpeed — 来自 Mirror 集团的镜面级低延迟 VPN。零摩擦、全隐私、极致速度。",
      cta1: "立即开始",
      cta2: "查看实时状态",
      trusted: "全球 300万+ 用户信赖",
    },
    stats: [
      { value: "300万+", label: "活跃用户" },
      { value: "45+", label: "全球节点" },
      { value: "99.9%", label: "服务可用性" },
      { value: "10Gbps", label: "节点带宽" },
    ],
    howItWorks: {
      title: "60秒极速上手",
      sub: "三步完成注册到高速浏览。",
      steps: [
        { title: "注册账户", desc: "几秒内完成注册，仅需邮箱，无需其他个人信息。" },
        { title: "复制订阅链接", desc: "在控制台一键获取您的 Clash 订阅链接。" },
        { title: "连接并畅游", desc: "粘贴至任意 WireGuard 或 Clash 客户端，自动选择最快节点。" },
      ],
    },
    features: {
      title: "为什么选择 MirrorSpeed",
      sub: "为光速反射而生。",
      items: [
        { t: "WireGuard 内核", d: "现代协议，最先进的加密技术，攻击面极小。" },
        { t: "零日志承诺", d: "独立审计的无日志政策，您的流量只属于您。" },
        { t: "多设备支持", d: "单账户最多 8 设备：Mac/Win/iOS/Android/Linux。" },
        { t: "自动切换", d: "Clash 订阅实时自动选择最快节点。" },
        { t: "全球边缘", d: "覆盖亚洲、美洲、欧洲 45+ 节点。" },
        { t: "7x24 支持", d: "真实工程师，实时响应，平均 5 分钟内回复。" },
      ],
    },
    servers: { title: "实时服务器矩阵", sub: "全球集群实时遥测数据。", load: "负载", latency: "延迟", uptime: "在线率", online: "在线" },
    testimonials: {
      title: "全球用户信赖",
      sub: "真实用户，真实速度。",
      items: [
        { name: "Alex T.", role: "开发者，上海", body: "HK01 稳定保持 14ms 延迟，比我用过的任何竞品都快，而且我全都试过了。" },
        { name: "Sarah M.", role: "自由职业者，北京", body: "Clash 集成非常流畅，设置一次即可，三个月来从未断线，体验极好。" },
        { name: "Ken W.", role: "创业者，深圳", body: "这个价格支持 8 台设备，性价比无敌，全团队当天就都换过来了。" },
      ],
    },
    pricing: {
      title: "选择您的方案", sub: "透明定价，随时取消。",
      popular: "最受欢迎", select: "选择此方案", featured: "立即开通",
      plans: [
        { name: "年付",  price: "¥8",  per: "/月", desc: "按年付 ¥96",      feats: ["全部 45+ 节点", "WireGuard + WebSocket 中继", "不限设备数", "7x24 支持", "7天退款"] },
        { name: "两年",  price: "¥7",  per: "/月", desc: "按两年付 ¥168",   feats: ["包含年付全部权益", "独立 IP 选项", "隐身模式", "优先队列"] },
        { name: "月付",  price: "¥24", per: "/月", desc: "按月付",           feats: ["全部 45+ 节点", "WireGuard + WebSocket 中继", "不限设备数", "7x24 支持"] },
        { name: "季付",  price: "¥12", per: "/月", desc: "按季付 ¥36",      feats: ["全部节点", "WireGuard + WebSocket 中继", "不限设备数", "7x24 支持"] },
      ],
    },
    faq: {
      title: "常见问题",
      items: [
        { q: "MirrorSpeed 有多快？", a: "国内到香港节点延迟低于 20ms，亚洲大部分地区低于 50ms。" },
        { q: "会保留日志吗？", a: "不会。独立审计的零日志政策，即便我们想看也看不到您的流量。" },
        { q: "支持哪些客户端？", a: "任何 WireGuard 或 Clash 兼容的客户端：Mac/Win/iOS/Android/Linux/OpenWrt。" },
        { q: "可以退款吗？", a: "所有方案均享 7 天无理由退款保证。" },
        { q: "可以连接多少设备？", a: "月付方案支持 3 台设备，年付和两年方案最多支持 8 台同时在线。" },
      ],
    },
    cta: { title: "立即开始镜速体验", sub: "7 天无理由退款保证，放心尝试。", btn: "免费开始" },
    auth: {
      loginTitle: "欢迎回来", signupTitle: "创建账户",
      google: "使用 Google 继续", microsoft: "使用 Microsoft 继续",
      orEmail: "或使用邮箱", email: "邮箱地址", password: "密码",
      submit: "发送验证码", switchToSignup: "还没有账户？注册", switchToLogin: "已有账户？登录",
      terms: "继续即表示同意服务条款和隐私政策。",
      otpSent: "验证码已发送，请查收邮件", enterOtp: "请输入邮件中的 8 位验证码",
      otpPlaceholder: "00000000", verify: "验证并登录", resend: "重新发送",
      loading: "加载中...", sending: "发送中...", redirecting: "正在登录...", invalidOtp: "验证码不正确，请重试。",
    },
    dash: {
      welcome: "欢迎回来", plan: "当前方案", expires: "剩余", days: "天",
      subUrl: "Clash 订阅链接", encrypted: "已加密", copy: "复制", copied: "已复制！",
      devices: "在线设备", account: "账户管理", renew: "续费", billing: "账单记录",
      manage: "更新账单信息或升级方案。", logout: "退出登录",
      usage: "流量使用", thisMonth: "本月",
      overview: "概览", myDevices: "我的设备", billingNav: "订阅与账单", adminLabel: "管理", logoutBtn: "退出登录",
    },
    footer: { tagline: "开放镜面网络的基础设施。", product: "产品", legal: "法律", support: "支持", contact: "联系我们", disclaimer: "免责声明" },
    download: {
      title: "下载 MirrorSpeed",
      sub: "推荐的 Clash 系客户端，覆盖全部平台。一个订阅链接，处处可用。",
      step: "快速开始",
      steps: ["下载对应平台的客户端。", "从控制台复制您的订阅链接。", "在客户端中粘贴链接，选择最快节点。"],
      install: "下载", guide: "配置教程", recommended: "推荐",
    },
    disclaimer: {
      title: "免责声明与使用条款",
      updated: "最后更新：2026 年 5 月 19 日",
      intro: "在使用 MirrorSpeed 之前，请仔细阅读本声明。访问或使用本服务即表示您同意以下条款的约束。",
      sections: [
        { h: "1. 服务用途", p: "MirrorSpeed 仅用于保护用户隐私、在不可信网络中加密数据传输以及提升连接性能，不得用于任何违法用途。" },
        { h: "2. 法律合规", p: "您需自行遵守所在司法辖区的全部法律法规。部分国家或地区对 VPN 服务的使用有限制或监管，请在订阅前核实当地法律。" },
        { h: "3. 禁止行为", p: "禁止使用本服务进行：未授权的系统入侵、传播恶意软件、侵犯版权、欺诈、骚扰、儿童色情或任何侵害他人权利的行为。" },
        { h: "4. 不作保证", p: "本服务按「现状」提供，不附带任何明示或默示的保证。我们不保证服务永久可用、达到特定速度或适用于任何特定用途。" },
        { h: "5. 责任限制", p: "在法律允许的最大范围内，Mirror 集团不对因使用或无法使用本服务而产生的任何间接、附带或衍生损失承担责任。" },
        { h: "6. 隐私与日志", p: "我们严格执行零日志政策。不会记录浏览历史、流量目的地、DNS 查询或用户连接 IP。仅依法保留必要的最少账单元数据。" },
        { h: "7. 账户终止", p: "对违反本条款的账户，我们保留暂停或终止且不予退款的权利，包括但不限于异常流量行为或欺诈付款。" },
        { h: "8. 联系方式", p: "如对本声明有疑问，请联系 support@mirrorspeed.io。" },
      ],
    },
  },

  de: {
    nav: { servers: "Server", pricing: "Preise", download: "Download", faq: "FAQ", dashboard: "Dashboard", login: "Anmelden", signup: "Registrieren" },
    hero: {
      badge: "Globales Netzwerk online",
      title1: "Reflexion ist",
      title2: "Sofortig",
      sub: "Mirror-Latenz-VPN von Mirror Group. Null Reibung, totale Privatsphäre, absolute Geschwindigkeit.",
      cta1: "Jetzt spiegeln",
      cta2: "Live-Status ansehen",
      trusted: "Von 3M+ Nutzern weltweit vertraut",
    },
    stats: [
      { value: "3M+", label: "Aktive Nutzer" },
      { value: "45+", label: "Globale Standorte" },
      { value: "99,9%", label: "Verfügbarkeit" },
      { value: "10Gbps", label: "Knoten-Bandbreite" },
    ],
    howItWorks: {
      title: "In 60 Sekunden bereit",
      sub: "Drei Schritte von der Anmeldung zum schnellen Surfen.",
      steps: [
        { title: "Konto erstellen", desc: "In Sekunden registrieren. Nur E-Mail erforderlich, keine weiteren Daten." },
        { title: "URL kopieren", desc: "Clash-Abonnement-URL mit einem Klick aus dem Dashboard holen." },
        { title: "Verbinden & surfen", desc: "In WireGuard- oder Clash-Client einfügen. Wählt automatisch den schnellsten Knoten." },
      ],
    },
    features: {
      title: "Warum MirrorSpeed",
      sub: "Entwickelt für lichtschnelle Reflexion.",
      items: [
        { t: "WireGuard-Kern", d: "Modernes Protokoll mit modernster Kryptographie und minimaler Angriffsfläche." },
        { t: "Keine-Logs-Richtlinie", d: "Unabhängig geprüfte Zero-Logs. Ihr Datenverkehr geht niemanden etwas an." },
        { t: "Multi-Gerät", d: "Bis zu 8 Geräte pro Konto. Mac, Windows, iOS, Android, Linux." },
        { t: "Auto-Failover", d: "Clash-Abonnement wählt in Echtzeit automatisch den schnellsten Knoten." },
        { t: "Globaler Edge", d: "45+ Standorte in Asien, Amerika und Europa." },
        { t: "24/7 Support", d: "Echte Ingenieure, echte Antworten, blitzschnell. Durchschnittliche Antwortzeit unter 5 Min." },
      ],
    },
    servers: { title: "Live-Server-Matrix", sub: "Echtzeit-Telemetrie aus unserem globalen Cluster.", load: "Last", latency: "Latenz", uptime: "Verfügbar", online: "Online" },
    testimonials: {
      title: "Weltweit vertraut",
      sub: "Echte Nutzer. Echte Geschwindigkeiten.",
      items: [
        { name: "Alex T.", role: "Entwickler, Shanghai", body: "HK01 zeigt bei mir konstant 14ms. Schneller als jeder Konkurrent, den ich ausprobiert habe — und ich habe alle ausprobiert." },
        { name: "Sarah M.", role: "Freiberuflerin, Peking", body: "Die Clash-Integration ist makellos. Einmal einrichten, vergessen. Seit drei Monaten kein einziger Ausfall." },
        { name: "Ken W.", role: "Startup-Gründer, Shenzhen", body: "8 Geräte pro Konto zu diesem Preis ist unschlagbar. Mein gesamtes Team hat am selben Tag gewechselt." },
      ],
    },
    pricing: {
      title: "Wählen Sie Ihre Reflexion", sub: "Transparente Preise. Jederzeit kündbar.",
      popular: "Beliebteste", select: "Plan wählen", featured: "Jetzt starten",
      plans: [
        { name: "Jährlich",    price: "$1",    per: "/Mo.", desc: "$12/Jahr",         feats: ["Alle 45+ Standorte", "WireGuard + WebSocket-Relay", "Unbegrenzte Geräte", "24/7 Support", "7-Tage-Rückgabe"] },
        { name: "2 Jahre",     price: "$0.90", per: "/Mo.", desc: "$21.60/2 Jahre",   feats: ["Alles im Jahresplan", "Dedizierte IP", "Stealth-Modus", "Prioritäts-Queue"] },
        { name: "Monatlich",   price: "$3",    per: "/Mo.", desc: "Monatlich",         feats: ["Alle 45+ Standorte", "WireGuard + WebSocket-Relay", "Unbegrenzte Geräte", "24/7 Support"] },
        { name: "Quartal",     price: "$1.50", per: "/Mo.", desc: "$4.50/Quartal",    feats: ["Alle Standorte", "WireGuard + WebSocket-Relay", "Unbegrenzte Geräte", "24/7 Support"] },
      ],
    },
    faq: {
      title: "Häufige Fragen",
      items: [
        { q: "Wie schnell ist MirrorSpeed?", a: "Unter 20ms Latenz zu Hongkong-Knoten aus Festlandchina, unter 50ms in den meisten Teilen Asiens." },
        { q: "Speichern Sie Logs?", a: "Nein. Unabhängig geprüfte Zero-Logs-Richtlinie — wir können Ihren Datenverkehr nicht sehen, selbst wenn wir wollten." },
        { q: "Welche Clients funktionieren?", a: "Jeder WireGuard- oder Clash-kompatible Client auf Mac, Windows, iOS, Android, Linux und OpenWrt." },
        { q: "Rückerstattungen?", a: "7-Tage-Geld-zurück-Garantie ohne Fragen für alle Pläne." },
        { q: "Wie viele Geräte kann ich verbinden?", a: "Monatliche Pläne umfassen 3 Geräte. Jährliche und 2-Jahres-Pläne unterstützen bis zu 8 gleichzeitige Geräte." },
      ],
    },
    cta: { title: "Heute mit dem Spiegeln beginnen", sub: "7-Tage-Geld-zurück-Garantie. Keine Fragen.", btn: "Kostenlos starten" },
    auth: {
      loginTitle: "Willkommen zurück", signupTitle: "Konto erstellen",
      google: "Mit Google fortfahren", microsoft: "Mit Microsoft fortfahren",
      orEmail: "Oder E-Mail", email: "E-Mail-Adresse", password: "Passwort",
      submit: "Code senden", switchToSignup: "Kein Konto? Registrieren", switchToLogin: "Bereits Konto? Anmelden",
      terms: "Mit dem Fortfahren stimmen Sie unseren AGB und Datenschutzrichtlinien zu.",
      otpSent: "Code gesendet — E-Mail prüfen", enterOtp: "8-stelligen Code aus der E-Mail eingeben",
      otpPlaceholder: "00000000", verify: "Verifizieren & Anmelden", resend: "Code erneut senden",
      loading: "Laden...", sending: "Senden...", redirecting: "Anmelden...", invalidOtp: "Ungültiger Code, bitte erneut versuchen.",
    },
    dash: {
      welcome: "Willkommen zurück", plan: "Aktiver Plan", expires: "Läuft ab in", days: "Tagen",
      subUrl: "Clash-Abonnement-URL", encrypted: "Verschlüsselt", copy: "Kopieren", copied: "Kopiert!",
      devices: "Verbundene Geräte", account: "Konto", renew: "Plan verlängern", billing: "Abrechnungsverlauf",
      manage: "Abrechnungsdaten aktualisieren oder Plan upgraden.", logout: "Abmelden",
      usage: "Datennutzung", thisMonth: "Diesen Monat",
      overview: "Übersicht", myDevices: "Meine Geräte", billingNav: "Abrechnung", adminLabel: "Admin", logoutBtn: "Abmelden",
    },
    footer: { tagline: "Die Infrastruktur des offenen Spiegel-Webs.", product: "Produkt", legal: "Rechtliches", support: "Support", contact: "Kontakt", disclaimer: "Haftungsausschluss" },
    download: {
      title: "MirrorSpeed herunterladen",
      sub: "Empfohlene Clash-basierte Clients für jede Plattform. Eine Abonnement-URL funktioniert überall.",
      step: "Schnellstart",
      steps: ["Installieren Sie den Client für Ihre Plattform.", "Kopieren Sie Ihre Abonnement-URL aus dem Dashboard.", "Fügen Sie sie in den Client ein und wählen Sie den schnellsten Knoten."],
      install: "Download", guide: "Einrichtungsanleitung", recommended: "Empfohlen",
    },
    disclaimer: {
      title: "Haftungsausschluss & Nutzungsbedingungen",
      updated: "Zuletzt aktualisiert: 19. Mai 2026",
      intro: "Bitte lesen Sie diesen Haftungsausschluss sorgfältig durch, bevor Sie MirrorSpeed nutzen.",
      sections: [
        { h: "1. Dienstzweck", p: "MirrorSpeed dient ausschließlich dem Schutz der Privatsphäre, der sicheren Datenübertragung in nicht vertrauenswürdigen Netzwerken und der Verbesserung der Verbindungsleistung." },
        { h: "2. Rechtliche Compliance", p: "Sie sind allein verantwortlich für die Einhaltung aller geltenden Gesetze in Ihrer Rechtsprechung. Bitte überprüfen Sie lokale Gesetze vor dem Abonnement." },
        { h: "3. Verbotene Aktivitäten", p: "Sie dürfen MirrorSpeed nicht verwenden für: unbefugten Systemzugriff, Malware-Verbreitung, Urheberrechtsverletzung, Betrug, Belästigung oder andere illegale Aktivitäten." },
        { h: "4. Keine Gewährleistung", p: "Der Dienst wird \"wie besehen\" ohne jegliche Gewährleistung bereitgestellt. Wir garantieren keine ununterbrochene Verfügbarkeit oder bestimmte Geschwindigkeiten." },
        { h: "5. Haftungsbeschränkung", p: "Im gesetzlich zulässigen Umfang haftet Mirror Group nicht für indirekte oder Folgeschäden aus der Nutzung oder Nichtnutzung des Dienstes." },
        { h: "6. Datenschutz & Logs", p: "Wir betreiben eine strikte No-Logs-Richtlinie. Wir erfassen keine Browserverlauf, Traffic-Ziele, DNS-Anfragen oder IP-Adressen verbundener Nutzer." },
        { h: "7. Konto-Kündigung", p: "Wir behalten uns das Recht vor, Konten, die gegen diese Bedingungen verstoßen, ohne Rückerstattung zu sperren oder zu kündigen." },
        { h: "8. Kontakt", p: "Bei Fragen wenden Sie sich bitte an support@mirrorspeed.io." },
      ],
    },
  },

  fr: {
    nav: { servers: "Serveurs", pricing: "Tarifs", download: "Télécharger", faq: "FAQ", dashboard: "Tableau de bord", login: "Connexion", signup: "S'inscrire" },
    hero: {
      badge: "Réseau mondial en ligne",
      title1: "La réflexion est",
      title2: "Instantanée",
      sub: "VPN à latence miroir par Mirror Group. Zéro friction, confidentialité totale, vitesse absolue.",
      cta1: "Commencer à refléter",
      cta2: "Voir le statut en direct",
      trusted: "Approuvé par 3M+ d'utilisateurs dans le monde",
    },
    stats: [
      { value: "3M+", label: "Utilisateurs actifs" },
      { value: "45+", label: "Emplacements mondiaux" },
      { value: "99,9%", label: "SLA de disponibilité" },
      { value: "10Gbps", label: "Bande passante des nœuds" },
    ],
    howItWorks: {
      title: "Prêt en 60 secondes",
      sub: "Trois étapes de l'inscription à la navigation rapide.",
      steps: [
        { title: "Créer un compte", desc: "Inscription en quelques secondes. Seul votre e-mail est nécessaire." },
        { title: "Copier votre URL", desc: "Récupérez votre URL d'abonnement Clash depuis le tableau de bord en un clic." },
        { title: "Se connecter et naviguer", desc: "Collez dans n'importe quel client WireGuard ou Clash. Sélectionne automatiquement le nœud le plus rapide." },
      ],
    },
    features: {
      title: "Pourquoi MirrorSpeed",
      sub: "Conçu pour une réflexion à la vitesse de la lumière.",
      items: [
        { t: "Cœur WireGuard", d: "Protocole moderne avec cryptographie de pointe et surface d'attaque minimale." },
        { t: "Politique sans journaux", d: "Zéro journaux audité indépendamment. Votre trafic vous appartient." },
        { t: "Multi-appareils", d: "Jusqu'à 8 appareils par compte. Mac, Windows, iOS, Android, Linux." },
        { t: "Basculement automatique", d: "L'abonnement Clash sélectionne automatiquement le nœud le plus rapide en temps réel." },
        { t: "Edge mondial", d: "45+ emplacements en Asie, Amériques et Europe." },
        { t: "Support 24/7", d: "De vrais ingénieurs, de vraies réponses, vraiment vite. Réponse moyenne en moins de 5 min." },
      ],
    },
    servers: { title: "Matrice de serveurs en direct", sub: "Télémétrie en temps réel de notre cluster mondial.", load: "Charge", latency: "Latence", uptime: "Disponibilité", online: "En ligne" },
    testimonials: {
      title: "Approuvé dans le monde entier",
      sub: "Vrais utilisateurs. Vraies vitesses.",
      items: [
        { name: "Alex T.", role: "Développeur, Shanghai", body: "HK01 affiche constamment 14ms pour moi. Plus rapide que tout concurrent que j'ai essayé." },
        { name: "Sarah M.", role: "Freelance, Pékin", body: "L'intégration Clash est parfaite. À configurer une fois, à oublier. Pas une seule coupure en trois mois." },
        { name: "Ken W.", role: "Fondateur de startup, Shenzhen", body: "8 appareils sur un seul compte à ce prix est imbattable. Toute mon équipe a changé le même jour." },
      ],
    },
    pricing: {
      title: "Choisissez votre réflexion", sub: "Tarification transparente. Annulable à tout moment.",
      popular: "Le plus populaire", select: "Choisir ce plan", featured: "Commencer",
      plans: [
        { name: "Annuel",      price: "$1",    per: "/mois", desc: "$12/an",           feats: ["Tous les 45+ emplacements", "WireGuard + relais WebSocket", "Appareils illimités", "Support 24/7", "Remboursement 7 jours"] },
        { name: "2 ans",       price: "$0,90", per: "/mois", desc: "$21,60/2 ans",     feats: ["Tout du plan annuel", "IP dédiée", "Mode furtif", "File prioritaire"] },
        { name: "Mensuel",     price: "$3",    per: "/mois", desc: "Mensuel",           feats: ["Tous les 45+ emplacements", "WireGuard + relais WebSocket", "Appareils illimités", "Support 24/7"] },
        { name: "Trimestriel", price: "$1,50", per: "/mois", desc: "$4,50/trimestre",  feats: ["Tous les emplacements", "WireGuard + relais WebSocket", "Appareils illimités", "Support 24/7"] },
      ],
    },
    faq: {
      title: "Questions fréquentes",
      items: [
        { q: "Quelle est la vitesse de MirrorSpeed ?", a: "Latence inférieure à 20ms vers les nœuds de Hong Kong depuis la Chine continentale, inférieure à 50ms dans la plupart de l'Asie." },
        { q: "Conservez-vous des journaux ?", a: "Non. Politique de zéro journaux auditée indépendamment." },
        { q: "Quels clients fonctionnent ?", a: "Tout client compatible WireGuard ou Clash sur Mac, Windows, iOS, Android, Linux et OpenWrt." },
        { q: "Remboursements ?", a: "Garantie de remboursement de 7 jours sans questions pour tous les plans." },
        { q: "Combien d'appareils puis-je connecter ?", a: "Les plans mensuels incluent 3 appareils. Les plans annuels et 2 ans supportent jusqu'à 8 appareils simultanés." },
      ],
    },
    cta: { title: "Commencez à refléter aujourd'hui", sub: "Garantie de remboursement de 7 jours. Sans questions.", btn: "Commencer gratuitement" },
    auth: {
      loginTitle: "Content de vous revoir", signupTitle: "Créer votre compte",
      google: "Continuer avec Google", microsoft: "Continuer avec Microsoft",
      orEmail: "Ou par e-mail", email: "Adresse e-mail", password: "Mot de passe",
      submit: "Envoyer le code", switchToSignup: "Pas de compte ? S'inscrire", switchToLogin: "Déjà un compte ? Se connecter",
      terms: "En continuant, vous acceptez nos Conditions et notre Politique de confidentialité.",
      otpSent: "Code envoyé — vérifiez vos e-mails", enterOtp: "Entrez le code à 8 chiffres reçu par e-mail",
      otpPlaceholder: "00000000", verify: "Vérifier et se connecter", resend: "Renvoyer le code",
      loading: "Chargement...", sending: "Envoi...", redirecting: "Connexion...", invalidOtp: "Code invalide, veuillez réessayer.",
    },
    dash: {
      welcome: "Content de vous revoir", plan: "Plan actif", expires: "Expire dans", days: "jours",
      subUrl: "URL d'abonnement Clash", encrypted: "Chiffré", copy: "Copier", copied: "Copié !",
      devices: "Appareils connectés", account: "Compte", renew: "Renouveler le plan", billing: "Historique de facturation",
      manage: "Mettre à jour les informations de facturation ou mettre à niveau le plan.", logout: "Se déconnecter",
      usage: "Utilisation des données", thisMonth: "Ce mois-ci",
      overview: "Aperçu", myDevices: "Mes appareils", billingNav: "Facturation", adminLabel: "Admin", logoutBtn: "Se déconnecter",
    },
    footer: { tagline: "L'infrastructure du web miroir ouvert.", product: "Produit", legal: "Légal", support: "Support", contact: "Contact", disclaimer: "Avertissement" },
    download: {
      title: "Télécharger MirrorSpeed",
      sub: "Clients Clash recommandés pour chaque plateforme. Une URL d'abonnement fonctionne partout.",
      step: "Démarrage rapide",
      steps: ["Installez le client pour votre plateforme.", "Copiez votre URL d'abonnement depuis le Tableau de bord.", "Collez-la dans le client et choisissez le nœud le plus rapide."],
      install: "Télécharger", guide: "Guide de configuration", recommended: "Recommandé",
    },
    disclaimer: {
      title: "Avertissement et utilisation acceptable",
      updated: "Dernière mise à jour : 19 mai 2026",
      intro: "Veuillez lire attentivement cet avertissement avant d'utiliser MirrorSpeed.",
      sections: [
        { h: "1. Objectif du service", p: "MirrorSpeed est fourni uniquement pour protéger la vie privée des utilisateurs, sécuriser la transmission de données et améliorer les performances de connexion." },
        { h: "2. Conformité légale", p: "Vous êtes seul responsable du respect de toutes les lois applicables dans votre juridiction. Vérifiez les lois locales avant de vous abonner." },
        { h: "3. Activités interdites", p: "Vous ne devez pas utiliser MirrorSpeed pour : accès non autorisé, distribution de logiciels malveillants, violation du droit d'auteur, fraude, harcèlement ou toute activité illégale." },
        { h: "4. Aucune garantie", p: "Le service est fourni \"tel quel\" sans garantie d'aucune sorte. Nous ne garantissons pas une disponibilité ininterrompue ni des vitesses spécifiques." },
        { h: "5. Limitation de responsabilité", p: "Dans la mesure permise par la loi, Mirror Group ne sera pas responsable des dommages indirects ou consécutifs découlant de l'utilisation du service." },
        { h: "6. Confidentialité et journaux", p: "Nous appliquons une stricte politique de zéro journaux. Nous n'enregistrons pas l'historique de navigation, les destinations de trafic, les requêtes DNS ou les adresses IP." },
        { h: "7. Résiliation de compte", p: "Nous nous réservons le droit de suspendre ou résilier les comptes qui violent ces conditions sans remboursement." },
        { h: "8. Contact", p: "Pour les questions concernant cet avertissement, contactez support@mirrorspeed.io." },
      ],
    },
  },

  it: {
    nav: { servers: "Server", pricing: "Prezzi", download: "Scarica", faq: "FAQ", dashboard: "Dashboard", login: "Accedi", signup: "Registrati" },
    hero: {
      badge: "Rete globale online",
      title1: "Il riflesso è",
      title2: "Istantaneo",
      sub: "VPN a latenza speculare di Mirror Group. Zero attrito, privacy totale, velocità assoluta.",
      cta1: "Inizia a riflettere",
      cta2: "Vedi stato live",
      trusted: "Scelto da 3M+ utenti in tutto il mondo",
    },
    stats: [
      { value: "3M+", label: "Utenti attivi" },
      { value: "45+", label: "Posizioni globali" },
      { value: "99,9%", label: "SLA di disponibilità" },
      { value: "10Gbps", label: "Larghezza di banda nodo" },
    ],
    howItWorks: {
      title: "Pronto in 60 secondi",
      sub: "Tre passi dalla registrazione alla navigazione veloce.",
      steps: [
        { title: "Crea account", desc: "Registrati in secondi. Serve solo la tua email." },
        { title: "Copia il tuo URL", desc: "Prendi il tuo URL di abbonamento Clash dalla dashboard con un clic." },
        { title: "Connetti e naviga", desc: "Incolla in qualsiasi client WireGuard o Clash. Seleziona automaticamente il nodo più veloce." },
      ],
    },
    features: {
      title: "Perché MirrorSpeed",
      sub: "Progettato per la riflessione alla velocità della luce.",
      items: [
        { t: "Core WireGuard", d: "Protocollo moderno con crittografia all'avanguardia e superficie di attacco minima." },
        { t: "Politica no-log", d: "Zero log verificati indipendentemente. Il tuo traffico è affar tuo." },
        { t: "Multi-dispositivo", d: "Fino a 8 dispositivi per account. Mac, Windows, iOS, Android, Linux." },
        { t: "Failover automatico", d: "L'abbonamento Clash seleziona automaticamente il nodo più veloce in tempo reale." },
        { t: "Edge globale", d: "45+ posizioni in Asia, Americhe ed Europa." },
        { t: "Supporto 24/7", d: "Veri ingegneri, risposte reali, velocissimo. Risposta media in meno di 5 min." },
      ],
    },
    servers: { title: "Matrice server live", sub: "Telemetria in tempo reale dal nostro cluster globale.", load: "Carico", latency: "Latenza", uptime: "Disponibilità", online: "Online" },
    testimonials: {
      title: "Scelto in tutto il mondo",
      sub: "Utenti reali. Velocità reali.",
      items: [
        { name: "Alex T.", role: "Sviluppatore, Shanghai", body: "HK01 raggiunge costantemente 14ms per me. Più veloce di qualsiasi concorrente che abbia provato." },
        { name: "Sarah M.", role: "Freelance, Pechino", body: "L'integrazione Clash è impeccabile. Configura una volta, dimentica. Non ho avuto una singola interruzione in tre mesi." },
        { name: "Ken W.", role: "Fondatore startup, Shenzhen", body: "8 dispositivi su un account a questo prezzo è imbattibile. Tutto il mio team è passato lo stesso giorno." },
      ],
    },
    pricing: {
      title: "Scegli il tuo riflesso", sub: "Prezzi trasparenti. Cancella in qualsiasi momento.",
      popular: "Più popolare", select: "Scegli piano", featured: "Inizia",
      plans: [
        { name: "Annuale",     price: "$1",    per: "/mese", desc: "$12/anno",          feats: ["Tutti i 45+ luoghi", "WireGuard + relay WebSocket", "Dispositivi illimitati", "Supporto 24/7", "Rimborso 7 giorni"] },
        { name: "2 anni",      price: "$0,90", per: "/mese", desc: "$21,60/2 anni",     feats: ["Tutto del piano annuale", "IP dedicato", "Modalità stealth", "Coda prioritaria"] },
        { name: "Mensile",     price: "$3",    per: "/mese", desc: "Mensile",            feats: ["Tutti i 45+ luoghi", "WireGuard + relay WebSocket", "Dispositivi illimitati", "Supporto 24/7"] },
        { name: "Trimestrale", price: "$1,50", per: "/mese", desc: "$4,50/trimestre",   feats: ["Tutti i luoghi", "WireGuard + relay WebSocket", "Dispositivi illimitati", "Supporto 24/7"] },
      ],
    },
    faq: {
      title: "Domande frequenti",
      items: [
        { q: "Quanto è veloce MirrorSpeed?", a: "Latenza inferiore a 20ms verso i nodi di Hong Kong dalla Cina continentale, inferiore a 50ms nella maggior parte dell'Asia." },
        { q: "Conservate i log?", a: "No. Politica zero-log verificata indipendentemente." },
        { q: "Quali client funzionano?", a: "Qualsiasi client compatibile WireGuard o Clash su Mac, Windows, iOS, Android, Linux e OpenWrt." },
        { q: "Rimborsi?", a: "Garanzia di rimborso di 7 giorni senza domande per tutti i piani." },
        { q: "Quanti dispositivi posso connettere?", a: "I piani mensili includono 3 dispositivi. I piani annuali e biennali supportano fino a 8 dispositivi simultanei." },
      ],
    },
    cta: { title: "Inizia a riflettere oggi", sub: "Garanzia di rimborso di 7 giorni. Nessuna domanda.", btn: "Inizia gratuitamente" },
    auth: {
      loginTitle: "Bentornato", signupTitle: "Crea il tuo account",
      google: "Continua con Google", microsoft: "Continua con Microsoft",
      orEmail: "O via email", email: "Indirizzo email", password: "Password",
      submit: "Invia codice", switchToSignup: "Nessun account? Registrati", switchToLogin: "Hai un account? Accedi",
      terms: "Continuando accetti i nostri Termini e la nostra Informativa sulla privacy.",
      otpSent: "Codice inviato — controlla la tua email", enterOtp: "Inserisci il codice a 8 cifre dalla tua email",
      otpPlaceholder: "00000000", verify: "Verifica e accedi", resend: "Invia di nuovo",
      loading: "Caricamento...", sending: "Invio...", redirecting: "Accesso...", invalidOtp: "Codice non valido, riprova.",
    },
    dash: {
      welcome: "Bentornato", plan: "Piano attivo", expires: "Scade tra", days: "giorni",
      subUrl: "URL abbonamento Clash", encrypted: "Crittografato", copy: "Copia", copied: "Copiato!",
      devices: "Dispositivi connessi", account: "Account", renew: "Rinnova piano", billing: "Cronologia fatturazione",
      manage: "Aggiorna le informazioni di fatturazione o aggiorna il piano.", logout: "Esci",
      usage: "Utilizzo dati", thisMonth: "Questo mese",
      overview: "Panoramica", myDevices: "I miei dispositivi", billingNav: "Fatturazione", adminLabel: "Admin", logoutBtn: "Esci",
    },
    footer: { tagline: "L'infrastruttura del web speculare aperto.", product: "Prodotto", legal: "Legale", support: "Supporto", contact: "Contatto", disclaimer: "Disclaimer" },
    download: {
      title: "Scarica MirrorSpeed",
      sub: "Client Clash consigliati per ogni piattaforma. Un URL di abbonamento funziona ovunque.",
      step: "Avvio rapido",
      steps: ["Installa il client per la tua piattaforma.", "Copia il tuo URL di abbonamento dalla Dashboard.", "Incollalo nel client e scegli il nodo più veloce."],
      install: "Scarica", guide: "Guida alla configurazione", recommended: "Consigliato",
    },
    disclaimer: {
      title: "Disclaimer e uso accettabile",
      updated: "Ultimo aggiornamento: 19 maggio 2026",
      intro: "Leggere attentamente questo disclaimer prima di utilizzare MirrorSpeed.",
      sections: [
        { h: "1. Scopo del servizio", p: "MirrorSpeed è fornito esclusivamente per proteggere la privacy degli utenti, proteggere la trasmissione dei dati e migliorare le prestazioni di connessione." },
        { h: "2. Conformità legale", p: "Sei l'unico responsabile del rispetto di tutte le leggi applicabili nella tua giurisdizione. Verifica le leggi locali prima di abbonarti." },
        { h: "3. Attività vietate", p: "Non devi utilizzare MirrorSpeed per: accesso non autorizzato a sistemi, distribuzione di malware, violazione del copyright, frode, molestie o qualsiasi attività illegale." },
        { h: "4. Nessuna garanzia", p: "Il servizio è fornito \"così com'è\" senza garanzie di alcun tipo." },
        { h: "5. Limitazione di responsabilità", p: "Nella misura consentita dalla legge, Mirror Group non sarà responsabile per danni indiretti o consequenziali derivanti dall'uso del servizio." },
        { h: "6. Privacy e log", p: "Applichiamo una rigorosa politica no-log. Non registriamo cronologia di navigazione, destinazioni del traffico, query DNS o indirizzi IP degli utenti connessi." },
        { h: "7. Chiusura account", p: "Ci riserviamo il diritto di sospendere o chiudere account che violano questi termini senza rimborso." },
        { h: "8. Contatto", p: "Per domande su questo disclaimer, contatta support@mirrorspeed.io." },
      ],
    },
  },

  es: {
    nav: { servers: "Servidores", pricing: "Precios", download: "Descargar", faq: "FAQ", dashboard: "Panel", login: "Iniciar sesión", signup: "Registrarse" },
    hero: {
      badge: "Red global en línea",
      title1: "El reflejo es",
      title2: "Instantáneo",
      sub: "VPN de latencia espejo por Mirror Group. Cero fricción, privacidad total, velocidad absoluta.",
      cta1: "Comenzar a reflejar",
      cta2: "Ver estado en vivo",
      trusted: "Confiado por 3M+ usuarios en todo el mundo",
    },
    stats: [
      { value: "3M+", label: "Usuarios activos" },
      { value: "45+", label: "Ubicaciones globales" },
      { value: "99,9%", label: "SLA de disponibilidad" },
      { value: "10Gbps", label: "Ancho de banda del nodo" },
    ],
    howItWorks: {
      title: "Listo en 60 segundos",
      sub: "Tres pasos desde el registro hasta la navegación rápida.",
      steps: [
        { title: "Crear cuenta", desc: "Regístrate en segundos. Solo se necesita tu email." },
        { title: "Copia tu URL", desc: "Obtén tu URL de suscripción Clash desde el panel con un clic." },
        { title: "Conecta y navega", desc: "Pega en cualquier cliente WireGuard o Clash. Selecciona automáticamente el nodo más rápido." },
      ],
    },
    features: {
      title: "Por qué MirrorSpeed",
      sub: "Diseñado para reflexión a velocidad de la luz.",
      items: [
        { t: "Núcleo WireGuard", d: "Protocolo moderno con criptografía de última generación y superficie de ataque mínima." },
        { t: "Política sin registros", d: "Cero registros auditados independientemente. Tu tráfico es solo tuyo." },
        { t: "Multi-dispositivo", d: "Hasta 8 dispositivos por cuenta. Mac, Windows, iOS, Android, Linux." },
        { t: "Conmutación automática", d: "La suscripción Clash selecciona automáticamente el nodo más rápido en tiempo real." },
        { t: "Edge global", d: "45+ ubicaciones en Asia, Américas y Europa." },
        { t: "Soporte 24/7", d: "Ingenieros reales, respuestas reales, muy rápido. Respuesta promedio en menos de 5 min." },
      ],
    },
    servers: { title: "Matriz de servidores en vivo", sub: "Telemetría en tiempo real de nuestro cluster global.", load: "Carga", latency: "Latencia", uptime: "Disponibilidad", online: "En línea" },
    testimonials: {
      title: "Confiado en todo el mundo",
      sub: "Usuarios reales. Velocidades reales.",
      items: [
        { name: "Alex T.", role: "Desarrollador, Shanghái", body: "HK01 me da consistentemente 14ms. Más rápido que cualquier competidor que haya probado." },
        { name: "Sarah M.", role: "Freelancer, Pekín", body: "La integración Clash es impecable. Configura una vez, olvida. No he tenido ni una sola caída en tres meses." },
        { name: "Ken W.", role: "Fundador de startup, Shenzhen", body: "8 dispositivos en una cuenta a este precio es imbatible. Todo mi equipo cambió el mismo día." },
      ],
    },
    pricing: {
      title: "Elige tu reflexión", sub: "Precios transparentes. Cancela en cualquier momento.",
      popular: "Más popular", select: "Elegir plan", featured: "Comenzar",
      plans: [
        { name: "Anual",      price: "$1",    per: "/mes", desc: "$12/año",           feats: ["Todos los 45+ lugares", "WireGuard + relay WebSocket", "Dispositivos ilimitados", "Soporte 24/7", "Reembolso 7 días"] },
        { name: "2 años",     price: "$0,90", per: "/mes", desc: "$21,60/2 años",     feats: ["Todo del plan anual", "IP dedicada", "Modo sigiloso", "Cola prioritaria"] },
        { name: "Mensual",    price: "$3",    per: "/mes", desc: "Mensual",            feats: ["Todos los 45+ lugares", "WireGuard + relay WebSocket", "Dispositivos ilimitados", "Soporte 24/7"] },
        { name: "Trimestral", price: "$1,50", per: "/mes", desc: "$4,50/trimestre",   feats: ["Todos los lugares", "WireGuard + relay WebSocket", "Dispositivos ilimitados", "Soporte 24/7"] },
      ],
    },
    faq: {
      title: "Preguntas frecuentes",
      items: [
        { q: "¿Qué tan rápido es MirrorSpeed?", a: "Latencia inferior a 20ms hacia nodos de Hong Kong desde China continental, inferior a 50ms en la mayor parte de Asia." },
        { q: "¿Guardan registros?", a: "No. Política de cero registros auditada independientemente." },
        { q: "¿Qué clientes funcionan?", a: "Cualquier cliente compatible con WireGuard o Clash en Mac, Windows, iOS, Android, Linux y OpenWrt." },
        { q: "¿Reembolsos?", a: "Garantía de devolución de dinero de 7 días sin preguntas para todos los planes." },
        { q: "¿Cuántos dispositivos puedo conectar?", a: "Los planes mensuales incluyen 3 dispositivos. Los planes anuales y bianuales soportan hasta 8 dispositivos simultáneos." },
      ],
    },
    cta: { title: "Empieza a reflejar hoy", sub: "Garantía de devolución de dinero de 7 días. Sin preguntas.", btn: "Comenzar gratis" },
    auth: {
      loginTitle: "Bienvenido de nuevo", signupTitle: "Crea tu cuenta",
      google: "Continuar con Google", microsoft: "Continuar con Microsoft",
      orEmail: "O con email", email: "Dirección de email", password: "Contraseña",
      submit: "Enviar código", switchToSignup: "¿Sin cuenta? Regístrate", switchToLogin: "¿Ya tienes cuenta? Inicia sesión",
      terms: "Al continuar aceptas nuestros Términos y Política de privacidad.",
      otpSent: "Código enviado — revisa tu correo", enterOtp: "Introduce el código de 8 dígitos de tu correo",
      otpPlaceholder: "00000000", verify: "Verificar e iniciar sesión", resend: "Reenviar código",
      loading: "Cargando...", sending: "Enviando...", redirecting: "Iniciando sesión...", invalidOtp: "Código inválido, inténtalo de nuevo.",
    },
    dash: {
      welcome: "Bienvenido de nuevo", plan: "Plan activo", expires: "Expira en", days: "días",
      subUrl: "URL de suscripción Clash", encrypted: "Cifrado", copy: "Copiar", copied: "¡Copiado!",
      devices: "Dispositivos conectados", account: "Cuenta", renew: "Renovar plan", billing: "Historial de facturación",
      manage: "Actualizar información de facturación o mejorar el plan.", logout: "Cerrar sesión",
      usage: "Uso de datos", thisMonth: "Este mes",
      overview: "Resumen", myDevices: "Mis dispositivos", billingNav: "Facturación", adminLabel: "Admin", logoutBtn: "Cerrar sesión",
    },
    footer: { tagline: "La infraestructura de la web espejo abierta.", product: "Producto", legal: "Legal", support: "Soporte", contact: "Contacto", disclaimer: "Aviso legal" },
    download: {
      title: "Descargar MirrorSpeed",
      sub: "Clientes Clash recomendados para cada plataforma. Una URL de suscripción funciona en todas partes.",
      step: "Inicio rápido",
      steps: ["Instala el cliente para tu plataforma.", "Copia tu URL de suscripción desde el Panel.", "Pégala en el cliente y elige el nodo más rápido."],
      install: "Descargar", guide: "Guía de configuración", recommended: "Recomendado",
    },
    disclaimer: {
      title: "Aviso legal y uso aceptable",
      updated: "Última actualización: 19 de mayo de 2026",
      intro: "Por favor, lee este aviso legal detenidamente antes de usar MirrorSpeed.",
      sections: [
        { h: "1. Propósito del servicio", p: "MirrorSpeed se proporciona únicamente para proteger la privacidad del usuario, asegurar la transmisión de datos y mejorar el rendimiento de la conexión." },
        { h: "2. Cumplimiento legal", p: "Eres el único responsable de cumplir con todas las leyes y regulaciones aplicables en tu jurisdicción." },
        { h: "3. Actividades prohibidas", p: "No debes usar MirrorSpeed para: acceso no autorizado a sistemas, distribución de malware, infracción de derechos de autor, fraude, acoso o cualquier actividad ilegal." },
        { h: "4. Sin garantía", p: "El servicio se proporciona \"tal como está\" sin garantías de ningún tipo." },
        { h: "5. Limitación de responsabilidad", p: "En la medida permitida por la ley, Mirror Group no será responsable de daños indirectos o consecuentes." },
        { h: "6. Privacidad y registros", p: "Operamos una estricta política de cero registros. No registramos historial de navegación, destinos de tráfico, consultas DNS o direcciones IP." },
        { h: "7. Terminación de cuenta", p: "Nos reservamos el derecho de suspender o cancelar cuentas que violen estos términos sin reembolso." },
        { h: "8. Contacto", p: "Para preguntas sobre este aviso legal, contacta a support@mirrorspeed.io." },
      ],
    },
  },

  uk: {
    nav: { servers: "Сервери", pricing: "Ціни", download: "Завантажити", faq: "FAQ", dashboard: "Панель", login: "Увійти", signup: "Реєстрація" },
    hero: {
      badge: "Глобальна мережа онлайн",
      title1: "Відображення —",
      title2: "Миттєве",
      sub: "VPN з дзеркальною затримкою від Mirror Group. Нульове тертя, повна конфіденційність, абсолютна швидкість.",
      cta1: "Почати дзеркалення",
      cta2: "Переглянути статус",
      trusted: "Довіряють 3M+ користувачів по всьому світу",
    },
    stats: [
      { value: "3M+", label: "Активних користувачів" },
      { value: "45+", label: "Глобальних локацій" },
      { value: "99,9%", label: "Доступність SLA" },
      { value: "10Gbps", label: "Пропускна здатність вузла" },
    ],
    howItWorks: {
      title: "Готово за 60 секунд",
      sub: "Три кроки від реєстрації до швидкого перегляду.",
      steps: [
        { title: "Створити акаунт", desc: "Реєструйся за секунди. Потрібна лише електронна пошта." },
        { title: "Скопіювати URL", desc: "Отримай URL підписки Clash з панелі одним кліком." },
        { title: "Підключитись і серфити", desc: "Встав у будь-який клієнт WireGuard або Clash. Автоматично обирає найшвидший вузол." },
      ],
    },
    features: {
      title: "Чому MirrorSpeed",
      sub: "Розроблено для відображення зі швидкістю світла.",
      items: [
        { t: "Ядро WireGuard", d: "Сучасний протокол із передовою криптографією та мінімальною поверхнею атаки." },
        { t: "Політика без журналів", d: "Нульові журнали, перевірені незалежно. Ваш трафік — тільки ваша справа." },
        { t: "Мультипристрій", d: "До 8 пристроїв на одному акаунті. Mac, Windows, iOS, Android, Linux." },
        { t: "Автоперемикання", d: "Підписка Clash автоматично обирає найшвидший вузол у реальному часі." },
        { t: "Глобальний Edge", d: "45+ локацій в Азії, Америці та Європі." },
        { t: "Підтримка 24/7", d: "Справжні інженери, справжні відповіді, дуже швидко. Середня відповідь менше 5 хв." },
      ],
    },
    servers: { title: "Матриця серверів наживо", sub: "Телеметрія в реальному часі з нашого глобального кластера.", load: "Навантаження", latency: "Затримка", uptime: "Доступність", online: "Онлайн" },
    testimonials: {
      title: "Довіра по всьому світу",
      sub: "Справжні користувачі. Справжня швидкість.",
      items: [
        { name: "Alex T.", role: "Розробник, Шанхай", body: "HK01 стабільно показує у мене 14мс. Швидше за будь-якого конкурента, якого я пробував." },
        { name: "Sarah M.", role: "Фрілансер, Пекін", body: "Інтеграція Clash бездоганна. Налаштував раз і забув. Жодного обриву за три місяці." },
        { name: "Ken W.", role: "Засновник стартапу, Шеньчжень", body: "8 пристроїв на одному акаунті за такою ціною — неперевершено. Вся моя команда перейшла того ж дня." },
      ],
    },
    pricing: {
      title: "Обери своє відображення", sub: "Прозоре ціноутворення. Скасуй будь-коли.",
      popular: "Найпопулярніший", select: "Обрати план", featured: "Почати",
      plans: [
        { name: "Річний",      price: "$1",    per: "/міс", desc: "$12/рік",          feats: ["Всі 45+ локацій", "WireGuard + WebSocket-реле", "Необмежено пристроїв", "Підтримка 24/7", "Повернення за 7 днів"] },
        { name: "2 роки",      price: "$0,90", per: "/міс", desc: "$21,60/2 роки",    feats: ["Все з річного плану", "Виділена IP", "Режим стелс", "Пріоритетна черга"] },
        { name: "Місячний",    price: "$3",    per: "/міс", desc: "Щомісяця",          feats: ["Всі 45+ локацій", "WireGuard + WebSocket-реле", "Необмежено пристроїв", "Підтримка 24/7"] },
        { name: "Квартальний", price: "$1,50", per: "/міс", desc: "$4,50/квартал",    feats: ["Всі локації", "WireGuard + WebSocket-реле", "Необмежено пристроїв", "Підтримка 24/7"] },
      ],
    },
    faq: {
      title: "Часті запитання",
      items: [
        { q: "Наскільки швидкий MirrorSpeed?", a: "Затримка менше 20 мс до вузлів Гонконгу з материкового Китаю, менше 50 мс у більшості Азії." },
        { q: "Ви зберігаєте журнали?", a: "Ні. Незалежно перевірена політика нульових журналів." },
        { q: "Які клієнти підтримуються?", a: "Будь-який клієнт, сумісний з WireGuard або Clash, на Mac, Windows, iOS, Android, Linux та OpenWrt." },
        { q: "Повернення коштів?", a: "7-денна гарантія повернення коштів без запитань для всіх планів." },
        { q: "Скільки пристроїв можна підключити?", a: "Місячні плани включають 3 пристрої. Річні та дворічні плани підтримують до 8 одночасних пристроїв." },
      ],
    },
    cta: { title: "Почни дзеркалення сьогодні", sub: "7-денна гарантія повернення коштів. Без запитань.", btn: "Почати безкоштовно" },
    auth: {
      loginTitle: "З поверненням", signupTitle: "Створи свій акаунт",
      google: "Продовжити з Google", microsoft: "Продовжити з Microsoft",
      orEmail: "Або за email", email: "Електронна пошта", password: "Пароль",
      submit: "Надіслати код", switchToSignup: "Немає акаунту? Зареєструватись", switchToLogin: "Вже є акаунт? Увійти",
      terms: "Продовжуючи, ви погоджуєтесь з нашими Умовами та Політикою конфіденційності.",
      otpSent: "Код надіслано — перевір пошту", enterOtp: "Введи 8-значний код з листа",
      otpPlaceholder: "00000000", verify: "Підтвердити та увійти", resend: "Надіслати знову",
      loading: "Завантаження...", sending: "Надсилання...", redirecting: "Вхід...", invalidOtp: "Невірний код, спробуй ще раз.",
    },
    dash: {
      welcome: "З поверненням", plan: "Активний план", expires: "Закінчується через", days: "днів",
      subUrl: "URL підписки Clash", encrypted: "Зашифровано", copy: "Копіювати", copied: "Скопійовано!",
      devices: "Підключені пристрої", account: "Акаунт", renew: "Поновити план", billing: "Історія рахунків",
      manage: "Оновити платіжну інформацію або оновити план.", logout: "Вийти",
      usage: "Використання даних", thisMonth: "Цього місяця",
      overview: "Огляд", myDevices: "Мої пристрої", billingNav: "Оплата", adminLabel: "Адмін", logoutBtn: "Вийти",
    },
    footer: { tagline: "Інфраструктура відкритого дзеркального вебу.", product: "Продукт", legal: "Правова інформація", support: "Підтримка", contact: "Контакт", disclaimer: "Відмова від відповідальності" },
    download: {
      title: "Завантажити MirrorSpeed",
      sub: "Рекомендовані клієнти на основі Clash для кожної платформи. Один URL підписки працює скрізь.",
      step: "Швидкий старт",
      steps: ["Встанови клієнт для своєї платформи.", "Скопіюй URL підписки з Панелі.", "Встав його в клієнт та обери найшвидший вузол."],
      install: "Завантажити", guide: "Посібник з налаштування", recommended: "Рекомендовано",
    },
    disclaimer: {
      title: "Відмова від відповідальності та прийнятне використання",
      updated: "Останнє оновлення: 19 травня 2026 р.",
      intro: "Будь ласка, уважно прочитайте цю відмову від відповідальності перед використанням MirrorSpeed.",
      sections: [
        { h: "1. Мета сервісу", p: "MirrorSpeed надається виключно для захисту конфіденційності користувачів, забезпечення безпечної передачі даних та покращення продуктивності з'єднання." },
        { h: "2. Дотримання законодавства", p: "Ви несете повну відповідальність за дотримання всіх чинних законів у вашій юрисдикції." },
        { h: "3. Заборонені дії", p: "Вам не дозволяється використовувати MirrorSpeed для: несанкціонованого доступу, поширення шкідливого ПЗ, порушення авторських прав, шахрайства або будь-якої незаконної діяльності." },
        { h: "4. Відсутність гарантій", p: "Сервіс надається \"як є\" без будь-яких гарантій. Ми не гарантуємо безперебійну доступність або конкретні швидкості." },
        { h: "5. Обмеження відповідальності", p: "У максимально дозволеній законом мірі Mirror Group не несе відповідальності за непрямі або побічні збитки." },
        { h: "6. Конфіденційність та журнали", p: "Ми дотримуємось суворої політики нульових журналів. Ми не записуємо історію перегляду, цільові адреси трафіку, DNS-запити або IP-адреси." },
        { h: "7. Закриття акаунту", p: "Ми залишаємо за собою право призупинити або закрити акаунти, які порушують ці умови, без відшкодування." },
        { h: "8. Контакт", p: "З питань щодо цієї відмови від відповідальності звертайтесь до support@mirrorspeed.io." },
      ],
    },
  },

  ja: {
    nav: { servers: "サーバー", pricing: "料金", download: "ダウンロード", faq: "よくある質問", dashboard: "ダッシュボード", login: "ログイン", signup: "登録" },
    hero: {
      badge: "グローバルネットワーク稼働中",
      title1: "反射は",
      title2: "瞬時",
      sub: "Mirror GroupによるミラーレイテンシVPN。ゼロ摩擦、完全なプライバシー、絶対的な速度。",
      cta1: "ミラーリング開始",
      cta2: "ライブ状況を見る",
      trusted: "世界中の300万人以上のユーザーに信頼されています",
    },
    stats: [
      { value: "300万+", label: "アクティブユーザー" },
      { value: "45+", label: "グローバル拠点" },
      { value: "99.9%", label: "稼働率SLA" },
      { value: "10Gbps", label: "ノード帯域幅" },
    ],
    howItWorks: {
      title: "60秒で開始",
      sub: "登録から高速ブラウジングまで3ステップ。",
      steps: [
        { title: "アカウント作成", desc: "数秒で登録。メールアドレスのみ必要です。" },
        { title: "URLをコピー", desc: "ダッシュボードからClashサブスクリプションURLをワンクリックで取得。" },
        { title: "接続してブラウジング", desc: "WireGuardまたはClashクライアントに貼り付け。最速ノードを自動選択。" },
      ],
    },
    features: {
      title: "MirrorSpeedを選ぶ理由",
      sub: "光速反射のために設計。",
      items: [
        { t: "WireGuardコア", d: "最先端の暗号化と最小限の攻撃面を持つ最新プロトコル。" },
        { t: "ノーログポリシー", d: "独立監査済みのゼロログ。あなたのトラフィックはあなただけのもの。" },
        { t: "マルチデバイス", d: "1アカウントで最大8台。Mac、Windows、iOS、Android、Linux対応。" },
        { t: "自動フェイルオーバー", d: "Clashサブスクリプションがリアルタイムで最速ノードを自動選択。" },
        { t: "グローバルエッジ", d: "アジア、南北アメリカ、ヨーロッパの45以上の拠点。" },
        { t: "24時間365日サポート", d: "本物のエンジニア、本物の回答、超高速。平均5分以内に返信。" },
      ],
    },
    servers: { title: "ライブサーバーマトリクス", sub: "グローバルクラスターからのリアルタイムテレメトリ。", load: "負荷", latency: "レイテンシ", uptime: "稼働率", online: "オンライン" },
    testimonials: {
      title: "世界中で信頼",
      sub: "実際のユーザー。実際の速度。",
      items: [
        { name: "Alex T.", role: "開発者、上海", body: "HK01は私に安定して14msを出してくれます。試したどの競合よりも速い。" },
        { name: "Sarah M.", role: "フリーランサー、北京", body: "Clashの統合は完璧です。一度設定したら忘れられます。3ヶ月間一度も接続が切れていません。" },
        { name: "Ken W.", role: "スタートアップ創業者、深圳", body: "この価格で1アカウント8台は無敵です。チーム全員が同じ日に乗り換えました。" },
      ],
    },
    pricing: {
      title: "あなたの反射を選ぶ", sub: "透明な料金。いつでもキャンセル可能。",
      popular: "最人気", select: "プランを選ぶ", featured: "始める",
      plans: [
        { name: "年払い",     price: "$1",    per: "/月", desc: "$12/年",          feats: ["45以上の全拠点", "WireGuard + WebSocketリレー", "デバイス無制限", "24時間サポート", "7日間返金"] },
        { name: "2年払い",    price: "$0.90", per: "/月", desc: "$21.60/2年",      feats: ["年払いの全機能", "専用IPオプション", "ステルスモード", "優先キュー"] },
        { name: "月払い",     price: "$3",    per: "/月", desc: "月払い",           feats: ["45以上の全拠点", "WireGuard + WebSocketリレー", "デバイス無制限", "24時間サポート"] },
        { name: "四半期払い", price: "$1.50", per: "/月", desc: "$4.50/四半期",    feats: ["全拠点", "WireGuard + WebSocketリレー", "デバイス無制限", "24時間サポート"] },
      ],
    },
    faq: {
      title: "よくある質問",
      items: [
        { q: "MirrorSpeedはどれくらい速いですか？", a: "中国本土から香港ノードへのレイテンシは20ms未満、アジアほとんどの地域で50ms未満です。" },
        { q: "ログを保存していますか？", a: "いいえ。独立監査済みのゼロログポリシー。" },
        { q: "どのクライアントが使えますか？", a: "Mac、Windows、iOS、Android、Linux、OpenWrt上のWireGuardまたはClash互換クライアント。" },
        { q: "返金はできますか？", a: "全プランで7日間の質問なし返金保証があります。" },
        { q: "何台のデバイスを接続できますか？", a: "月払いプランは3台。年払いと2年払いプランは最大8台同時接続をサポートします。" },
      ],
    },
    cta: { title: "今日から反射を始める", sub: "7日間返金保証。質問なし。", btn: "無料で始める" },
    auth: {
      loginTitle: "おかえりなさい", signupTitle: "アカウントを作成",
      google: "Googleで続ける", microsoft: "Microsoftで続ける",
      orEmail: "またはメールで", email: "メールアドレス", password: "パスワード",
      submit: "コードを送信", switchToSignup: "アカウントなし？登録する", switchToLogin: "アカウントあり？ログイン",
      terms: "続けることで、利用規約とプライバシーポリシーに同意します。",
      otpSent: "コードを送信しました — メールを確認してください", enterOtp: "メールに届いた8桁のコードを入力",
      otpPlaceholder: "00000000", verify: "確認してログイン", resend: "コードを再送",
      loading: "読み込み中...", sending: "送信中...", redirecting: "ログイン中...", invalidOtp: "コードが無効です。もう一度お試しください。",
    },
    dash: {
      welcome: "おかえりなさい", plan: "有効なプラン", expires: "残り", days: "日",
      subUrl: "Clashサブスクリプション URL", encrypted: "暗号化済み", copy: "コピー", copied: "コピーしました！",
      devices: "接続デバイス", account: "アカウント", renew: "プランを更新", billing: "請求履歴",
      manage: "請求情報を更新またはプランをアップグレード。", logout: "ログアウト",
      usage: "データ使用量", thisMonth: "今月",
      overview: "概要", myDevices: "デバイス", billingNav: "請求", adminLabel: "管理", logoutBtn: "ログアウト",
    },
    footer: { tagline: "オープンミラーウェブのインフラ。", product: "製品", legal: "法的事項", support: "サポート", contact: "お問い合わせ", disclaimer: "免責事項" },
    download: {
      title: "MirrorSpeedをダウンロード",
      sub: "全プラットフォーム向けの推奨Clashベースクライアント。1つのサブスクリプションURLでどこでも使えます。",
      step: "クイックスタート",
      steps: ["お使いのプラットフォーム用のクライアントをインストール。", "ダッシュボードからサブスクリプションURLをコピー。", "クライアントに貼り付けて最速ノードを選択。"],
      install: "ダウンロード", guide: "セットアップガイド", recommended: "おすすめ",
    },
    disclaimer: {
      title: "免責事項と許容される使用",
      updated: "最終更新：2026年5月19日",
      intro: "MirrorSpeedを使用する前に、この免責事項をよくお読みください。当サービスにアクセスまたは使用することにより、以下の条件に同意したことになります。",
      sections: [
        { h: "1. サービスの目的", p: "MirrorSpeedは、ユーザーのプライバシー保護、信頼できないネットワーク上でのデータ送信の安全確保、および接続パフォーマンスの向上のみを目的として提供されています。" },
        { h: "2. 法令遵守", p: "お客様の居住地域のすべての適用法令を遵守する責任はお客様のみにあります。" },
        { h: "3. 禁止行為", p: "システムへの不正アクセス、マルウェアの配布、著作権侵害、詐欺、嫌がらせ、またはその他の違法行為にMirrorSpeedを使用することはできません。" },
        { h: "4. 保証なし", p: "本サービスはいかなる保証もなく「現状のまま」提供されます。" },
        { h: "5. 責任の制限", p: "法律で許可される最大限の範囲で、Mirror Groupはサービスの使用から生じる間接的または結果的損害について責任を負いません。" },
        { h: "6. プライバシーとログ", p: "当社は厳格なノーログポリシーを運営しています。接続ユーザーの閲覧履歴、トラフィックの宛先、DNSクエリ、またはIPアドレスを記録しません。" },
        { h: "7. アカウントの終了", p: "当社は、これらの条件に違反するアカウントを返金なしで停止または終了する権利を留保します。" },
        { h: "8. お問い合わせ", p: "この免責事項に関するご質問は、support@mirrorspeed.ioまでお問い合わせください。" },
      ],
    },
  },
};

type Dict = typeof dict["en"];

const LANG_LABELS: Record<Lang, string> = {
  en: "EN", zh: "中文", de: "DE", fr: "FR", it: "IT", es: "ES", uk: "УК", ja: "日本語",
};

export { LANG_LABELS };

const BROWSER_LANG_MAP: Record<string, Lang> = {
  zh: "zh", de: "de", fr: "fr", it: "it", es: "es", uk: "uk", ja: "ja",
};

const I18nCtx = createContext<{ lang: Lang; setLang: (l: Lang) => void; t: Dict }>({
  lang: "en", setLang: () => {}, t: dict.en,
});

export function I18nProvider({ children }: { children: ReactNode }) {
  const [lang, setLangState] = useState<Lang>("en");

  useEffect(() => {
    const saved = typeof window !== "undefined" ? localStorage.getItem("ms-lang") as Lang | null : null;
    const allLangs: Lang[] = ["en", "zh", "de", "fr", "it", "es", "uk", "ja"];
    if (saved && allLangs.includes(saved)) {
      setLangState(saved);
    } else if (typeof navigator !== "undefined") {
      const prefix = navigator.language.slice(0, 2).toLowerCase();
      if (BROWSER_LANG_MAP[prefix]) setLangState(BROWSER_LANG_MAP[prefix]);
    }
  }, []);

  const setLang = (l: Lang) => {
    setLangState(l);
    if (typeof window !== "undefined") localStorage.setItem("ms-lang", l);
  };

  return <I18nCtx.Provider value={{ lang, setLang, t: dict[lang] }}>{children}</I18nCtx.Provider>;
}

export const useI18n = () => useContext(I18nCtx);
