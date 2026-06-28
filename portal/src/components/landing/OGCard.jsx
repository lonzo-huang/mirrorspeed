'use client';
import { useEffect } from "react";

// OG card rendered at 1200x630 — used for Twitter/X social previews
// Routes: /og/cn (Chinese) and /og/en (English)
// Captured to /public/og-cn.png and og-en.png via Playwright

const COPY = {
  zh: {
    title_top: "MIRROR SPEED",
    tagline: "无惧干扰 · 极速连接全球",
    tags: [
      { e: "🎁", t: "永久免费试用" },
      { e: "🚀", t: "自研加速引擎" },
      { e: "⚡", t: "极速不限速" },
      { e: "🌍", t: "多国节点 · 零日志" },
    ],
    platforms_label: "秒开全球主流平台",
    url: "mirrorspeed.com",
  },
  en: {
    title_top: "MIRROR SPEED",
    tagline: "Unstoppable. Globally Fast.",
    tags: [
      { e: "🎁", t: "Free Forever Tier" },
      { e: "🚀", t: "Hyperspeed Engine" },
      { e: "⚡", t: "Unlimited Speed" },
      { e: "🌍", t: "Global Nodes · No Logs" },
    ],
    platforms_label: "Instant access, worldwide",
    url: "mirrorspeed.com",
  },
};

// Platform icons (using emoji + inline SVG for crisp render at 1200x630)
const PlatformIcons = () => (
  <div style={{ display: "flex", gap: "20px", alignItems: "center", flexWrap: "wrap" }}>
    {[
      { label: "ChatGPT", svg: <svg viewBox="0 0 24 24" width="32" height="32" fill="#ffffff"><path d="M22.282 9.821a5.985 5.985 0 0 0-.516-4.91 6.046 6.046 0 0 0-6.51-2.9A6.065 6.065 0 0 0 4.981 4.18a5.985 5.985 0 0 0-3.998 2.9 6.046 6.046 0 0 0 .743 7.097 5.98 5.98 0 0 0 .51 4.911 6.051 6.051 0 0 0 6.515 2.9A5.985 5.985 0 0 0 13.26 24a6.056 6.056 0 0 0 5.772-4.206 5.99 5.99 0 0 0 3.997-2.9 6.056 6.056 0 0 0-.747-7.073zM13.26 22.43a4.476 4.476 0 0 1-2.876-1.04l.141-.081 4.779-2.758a.795.795 0 0 0 .392-.681v-6.737l2.02 1.168a.071.071 0 0 1 .038.052v5.583a4.504 4.504 0 0 1-4.494 4.494zM3.6 18.304a4.47 4.47 0 0 1-.535-3.014l.142.085 4.783 2.759a.771.771 0 0 0 .78 0l5.843-3.369v2.332a.08.08 0 0 1-.033.062L9.74 19.95a4.5 4.5 0 0 1-6.14-1.646zM2.34 7.896a4.485 4.485 0 0 1 2.366-1.973V11.6a.766.766 0 0 0 .388.676l5.815 3.355-2.02 1.168a.076.076 0 0 1-.071 0l-4.83-2.786A4.504 4.504 0 0 1 2.34 7.872zm16.597 3.855-5.833-3.387L15.119 7.2a.076.076 0 0 1 .071 0l4.83 2.791a4.494 4.494 0 0 1-.676 8.105v-5.678a.79.79 0 0 0-.407-.667zm2.01-3.023-.141-.085-4.774-2.782a.776.776 0 0 0-.785 0L9.409 9.23V6.897a.066.066 0 0 1 .028-.061l4.83-2.787a4.5 4.5 0 0 1 6.68 4.66zm-12.64 4.135-2.02-1.164a.08.08 0 0 1-.038-.057V6.075a4.5 4.5 0 0 1 7.375-3.453l-.142.08L8.704 5.46a.795.795 0 0 0-.393.681zm1.097-2.365 2.602-1.5 2.607 1.5v2.999l-2.597 1.5-2.607-1.5z"/></svg>, color: "#10A37F" },
      { label: "X", svg: <svg viewBox="0 0 24 24" width="32" height="32" fill="#ffffff"><path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z"/></svg> },
      { label: "Google", svg: <svg viewBox="0 0 24 24" width="32" height="32"><path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/><path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/><path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18A10.97 10.97 0 0 0 1 12c0 1.77.42 3.45 1.18 4.93l2.85-2.22.81-.62z"/><path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84C6.71 7.31 9.14 5.38 12 5.38z"/></svg> },
      { label: "TikTok", svg: <svg viewBox="0 0 24 24" width="32" height="32" fill="#ffffff"><path d="M19.59 6.69a4.83 4.83 0 0 1-3.77-4.25V2h-3.45v13.67a2.89 2.89 0 0 1-5.2 1.74 2.89 2.89 0 0 1 2.31-4.64 2.93 2.93 0 0 1 .88.13V9.4a6.84 6.84 0 0 0-1-.05A6.33 6.33 0 0 0 5.8 20.1a6.34 6.34 0 0 0 10.86-4.43v-7a8.16 8.16 0 0 0 4.77 1.52v-3.4a4.85 4.85 0 0 1-1.84-.1z"/></svg> },
      { label: "YouTube", svg: <svg viewBox="0 0 24 24" width="32" height="32" fill="#FF0000"><path d="M23.498 6.186a3.016 3.016 0 0 0-2.122-2.136C19.505 3.545 12 3.545 12 3.545s-7.505 0-9.377.505A3.017 3.017 0 0 0 .502 6.186C0 8.07 0 12 0 12s0 3.93.502 5.814a3.016 3.016 0 0 0 2.122 2.136c1.871.505 9.376.505 9.376.505s7.505 0 9.377-.505a3.015 3.015 0 0 0 2.122-2.136C24 15.93 24 12 24 12s0-3.93-.502-5.814zM9.545 15.568V8.432L15.818 12l-6.273 3.568z"/></svg> },
      { label: "Facebook", svg: <svg viewBox="0 0 24 24" width="32" height="32" fill="#1877F2"><path d="M24 12.073c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.99 4.388 10.954 10.125 11.854v-8.385H7.078v-3.47h3.047V9.43c0-3.007 1.792-4.669 4.533-4.669 1.312 0 2.686.235 2.686.235v2.953H15.83c-1.491 0-1.956.925-1.956 1.874v2.25h3.328l-.532 3.47h-2.796v8.385C19.612 23.027 24 18.062 24 12.073z"/></svg> },
      { label: "Instagram", svg: <svg viewBox="0 0 24 24" width="32" height="32"><defs><linearGradient id="ig-grad" x1="0%" y1="100%" x2="100%" y2="0%"><stop offset="0%" stopColor="#FFDC80"/><stop offset="50%" stopColor="#E1306C"/><stop offset="100%" stopColor="#833AB4"/></linearGradient></defs><path fill="url(#ig-grad)" d="M12 2.163c3.204 0 3.584.012 4.85.07 1.366.062 2.633.336 3.608 1.311.975.975 1.249 2.242 1.311 3.608.058 1.266.069 1.646.069 4.851 0 3.205-.012 3.584-.069 4.849-.062 1.366-.336 2.633-1.311 3.608-.975.975-2.242 1.249-3.608 1.311-1.266.058-1.646.07-4.85.07-3.204 0-3.584-.012-4.849-.07-1.366-.062-2.633-.336-3.608-1.311-.975-.975-1.249-2.242-1.311-3.608C2.175 15.647 2.163 15.268 2.163 12s.012-3.584.07-4.85c.062-1.366.336-2.633 1.311-3.608.975-.975 2.242-1.249 3.608-1.311 1.265-.057 1.645-.069 4.849-.069zM12 0C8.741 0 8.332.014 7.052.072 5.775.131 4.903.333 4.14.63a5.875 5.875 0 0 0-2.126 1.384A5.876 5.876 0 0 0 .63 4.14C.333 4.903.131 5.775.072 7.052.014 8.332 0 8.741 0 12s.014 3.668.072 4.948c.059 1.277.261 2.149.558 2.913a5.875 5.875 0 0 0 1.384 2.126A5.875 5.875 0 0 0 4.14 23.37c.764.297 1.636.499 2.913.558C8.332 23.986 8.741 24 12 24s3.668-.014 4.948-.072c1.277-.059 2.149-.261 2.913-.558a5.875 5.875 0 0 0 2.126-1.384 5.875 5.875 0 0 0 1.384-2.126c.297-.764.499-1.636.558-2.913.058-1.28.072-1.689.072-4.948s-.014-3.668-.072-4.948c-.059-1.277-.261-2.149-.558-2.913a5.875 5.875 0 0 0-1.384-2.126A5.875 5.875 0 0 0 19.86.63c-.764-.297-1.636-.499-2.913-.558C15.668.014 15.259 0 12 0zm0 5.838a6.162 6.162 0 1 0 0 12.324 6.162 6.162 0 0 0 0-12.324zM12 16a4 4 0 1 1 0-8 4 4 0 0 1 0 8zm6.406-11.845a1.44 1.44 0 1 0 0 2.881 1.44 1.44 0 0 0 0-2.881z"/></svg> },
      { label: "Stocks", svg: <svg viewBox="0 0 24 24" width="32" height="32" fill="none" stroke="#22d3a0" strokeWidth="2"><path d="M3 17l6-6 4 4 8-8M14 7h7v7"/></svg> },
      { label: "BTC", svg: <svg viewBox="0 0 24 24" width="32" height="32" fill="#F7931A"><path d="M23.638 14.904c-1.602 6.43-8.113 10.34-14.542 8.736C2.67 22.05-1.244 15.525.362 9.105 1.962 2.67 8.475-1.243 14.9.358c6.43 1.605 10.342 8.115 8.738 14.546zm-6.35-4.613c.24-1.59-.974-2.45-2.64-3.03l.54-2.153-1.315-.33-.525 2.107c-.345-.087-.705-.167-1.064-.25l.526-2.127-1.32-.33-.54 2.165c-.285-.067-.565-.132-.84-.2l-1.815-.45-.35 1.407s.974.225.955.236c.535.136.63.486.615.766l-1.477 5.92c-.075.18-.24.45-.615.35.015.02-.96-.24-.96-.24l-.66 1.51 1.71.426.93.236-.54 2.19 1.32.327.54-2.17c.36.1.705.19 1.05.273l-.51 2.154 1.32.33.545-2.19c2.24.427 3.93.257 4.64-1.774.57-1.637-.03-2.58-1.217-3.196.854-.193 1.5-.76 1.68-1.93zm-3.01 4.22c-.404 1.64-3.157.75-4.05.53l.72-2.9c.896.22 3.757.67 3.33 2.37zm.41-4.24c-.37 1.49-2.662.735-3.405.55l.654-2.64c.744.18 3.137.524 2.75 2.084z"/></svg> },
    ].map((p) => (
      <div key={p.label} style={{
        display: "flex", flexDirection: "column", alignItems: "center", gap: "4px",
        padding: "10px 14px", borderRadius: "12px",
        background: "rgba(255,255,255,0.04)",
        border: "1px solid rgba(34,211,160,0.18)",
      }}>
        {p.svg}
      </div>
    ))}
  </div>
);

const OGCard = ({ lang = "en" }) => {
  const c = COPY[lang];

  useEffect(() => {
    // mark body so playwright knows it's ready
    document.body.setAttribute("data-og-ready", "1");
  }, []);

  return (
    <div
      style={{
        width: "1200px",
        height: "630px",
        background: "#06090E",
        position: "relative",
        overflow: "hidden",
        fontFamily: "'Manrope', sans-serif",
        color: "#ffffff",
      }}
      data-testid={`og-card-${lang}`}
    >
      {/* Background grid + glow */}
      <div
        style={{
          position: "absolute", inset: 0,
          backgroundImage: "linear-gradient(rgba(34,211,160,0.05) 1px, transparent 1px), linear-gradient(90deg, rgba(34,211,160,0.05) 1px, transparent 1px)",
          backgroundSize: "60px 60px",
        }}
      />
      <div style={{ position: "absolute", top: "-150px", right: "-150px", width: "600px", height: "600px", borderRadius: "50%", background: "radial-gradient(circle, rgba(34,211,160,0.25), transparent 70%)", filter: "blur(40px)" }} />
      <div style={{ position: "absolute", bottom: "-200px", left: "-100px", width: "500px", height: "500px", borderRadius: "50%", background: "radial-gradient(circle, rgba(0,180,255,0.20), transparent 70%)", filter: "blur(40px)" }} />

      {/* Diagonal speed lines */}
      <svg viewBox="0 0 1200 630" style={{ position: "absolute", inset: 0, opacity: 0.5 }} aria-hidden="true">
        <defs>
          <linearGradient id="sl1" x1="0" y1="0" x2="1" y2="0">
            <stop offset="0%" stopColor="#22d3a0" stopOpacity="0" />
            <stop offset="50%" stopColor="#22d3a0" stopOpacity="0.9" />
            <stop offset="100%" stopColor="#22d3a0" stopOpacity="0" />
          </linearGradient>
          <linearGradient id="sl2" x1="0" y1="0" x2="1" y2="0">
            <stop offset="0%" stopColor="#00d4ff" stopOpacity="0" />
            <stop offset="50%" stopColor="#00d4ff" stopOpacity="0.8" />
            <stop offset="100%" stopColor="#00d4ff" stopOpacity="0" />
          </linearGradient>
        </defs>
        {[100, 180, 260, 340, 420, 500].map((y, i) => (
          <path key={y} d={`M${700 + i * 20} ${y} L${1180 - i * 10} ${y - 40 + i * 12}`} stroke={i % 2 === 0 ? "url(#sl1)" : "url(#sl2)"} strokeWidth={i === 2 ? "3" : "1.5"} fill="none" />
        ))}
      </svg>

      {/* LEFT: text content */}
      <div style={{ position: "absolute", top: "70px", left: "70px", right: "560px", display: "flex", flexDirection: "column", gap: "28px" }}>
        {/* Brand row */}
        <div style={{ display: "flex", alignItems: "center", gap: "14px" }}>
          <img src="/logo.png" alt="MirrorSpeed" style={{ width: "60px", height: "60px", borderRadius: "14px", boxShadow: "0 0 30px rgba(34,211,160,0.5)" }} />
          <div style={{ fontFamily: "'Unbounded', sans-serif", fontWeight: 800, fontSize: "30px", letterSpacing: "-0.02em", color: "#fff" }}>MirrorSpeed</div>
        </div>

        {/* Main headline */}
        <div>
          <h1 style={{
            margin: 0,
            fontFamily: "'Unbounded', sans-serif",
            fontWeight: 900,
            fontSize: "78px",
            lineHeight: 0.95,
            letterSpacing: "-0.04em",
            color: "#ffffff",
            textShadow: "0 0 30px rgba(34,211,160,0.6), 0 0 60px rgba(34,211,160,0.3)",
          }}>
            {c.title_top}
          </h1>
          <p style={{
            margin: "18px 0 0 0",
            fontSize: lang === "zh" ? "32px" : "30px",
            fontWeight: 600,
            color: "#22d3a0",
            letterSpacing: lang === "zh" ? "0.02em" : "-0.01em",
          }}>
            {c.tagline}
          </p>
        </div>

        {/* Pill tags */}
        <div style={{ display: "flex", flexWrap: "wrap", gap: "12px", marginTop: "4px" }}>
          {c.tags.map((tg) => (
            <div key={tg.t} style={{
              display: "inline-flex", alignItems: "center", gap: "8px",
              padding: "10px 16px",
              borderRadius: "999px",
              background: "rgba(34,211,160,0.10)",
              border: "1px solid rgba(34,211,160,0.45)",
              fontSize: lang === "zh" ? "17px" : "16px",
              fontWeight: 600,
              color: "#e8fff5",
              boxShadow: "0 0 20px rgba(34,211,160,0.15) inset",
            }}>
              <span style={{ fontSize: "18px" }}>{tg.e}</span>
              <span>{tg.t}</span>
            </div>
          ))}
        </div>
      </div>

      {/* RIGHT: device mockup */}
      <div style={{ position: "absolute", top: "100px", right: "60px", width: "480px", height: "330px" }}>
        {/* Glow halo */}
        <div style={{ position: "absolute", inset: "-40px", borderRadius: "32px", background: "radial-gradient(ellipse at center, rgba(34,211,160,0.35), transparent 60%)", filter: "blur(20px)" }} />

        {/* "Window" frame */}
        <div style={{
          position: "relative",
          width: "100%", height: "100%",
          borderRadius: "20px",
          background: "linear-gradient(135deg, #0d1520 0%, #0a1018 100%)",
          border: "1px solid rgba(34,211,160,0.4)",
          boxShadow: "0 30px 80px rgba(0,0,0,0.6), 0 0 60px rgba(34,211,160,0.2)",
          overflow: "hidden",
          transform: "perspective(1200px) rotateY(-10deg) rotateX(4deg)",
        }}>
          {/* Title bar */}
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "12px 16px", borderBottom: "1px solid rgba(255,255,255,0.06)", background: "rgba(255,255,255,0.02)" }}>
            <div style={{ display: "flex", gap: "6px" }}>
              <div style={{ width: 10, height: 10, borderRadius: 5, background: "#ff5f57" }} />
              <div style={{ width: 10, height: 10, borderRadius: 5, background: "#febc2e" }} />
              <div style={{ width: 10, height: 10, borderRadius: 5, background: "#28c840" }} />
            </div>
            <div style={{ fontFamily: "'JetBrains Mono', monospace", fontSize: "11px", color: "#22d3a0", letterSpacing: "0.1em" }}>MIRRORSPEED ENGINE</div>
            <div style={{ width: 36 }} />
          </div>

          {/* Body */}
          <div style={{ padding: "26px 28px", height: "calc(100% - 38px)", display: "flex", flexDirection: "column", justifyContent: "space-between" }}>
            <div>
              <div style={{ fontFamily: "'JetBrains Mono', monospace", fontSize: "10px", color: "#7a8290", letterSpacing: "0.18em" }}>{lang === "zh" ? "状态" : "STATUS"}</div>
              <div style={{ display: "flex", alignItems: "center", gap: "10px", marginTop: "8px" }}>
                <div style={{ width: 10, height: 10, borderRadius: 5, background: "#22d3a0", boxShadow: "0 0 10px #22d3a0" }} />
                <div style={{ fontFamily: "'Unbounded', sans-serif", fontWeight: 800, fontSize: "28px", color: "#fff" }}>{lang === "zh" ? "已连接" : "CONNECTED"}</div>
              </div>
              <div style={{ fontFamily: "'JetBrains Mono', monospace", fontSize: "11px", color: "#22d3a0", marginTop: "8px" }}>
                {lang === "zh" ? "镜像延迟 · UDP · 加密通道" : "Mirror-latency · UDP · Encrypted"}
              </div>
            </div>

            {/* Speed bars */}
            <div>
              <div style={{ display: "flex", justifyContent: "space-between", fontFamily: "'JetBrains Mono', monospace", fontSize: "10px", color: "#7a8290", letterSpacing: "0.18em" }}>
                <span>{lang === "zh" ? "吞吐量" : "THROUGHPUT"}</span>
                <span style={{ color: "#22d3a0" }}>1000 Mbps</span>
              </div>
              <div style={{ display: "flex", alignItems: "flex-end", gap: "3px", height: "60px", marginTop: "10px" }}>
                {Array.from({ length: 36 }).map((_, i) => {
                  const h = 20 + Math.abs(Math.sin(i * 0.7)) * 70 + (i % 5 === 0 ? 15 : 0);
                  return <div key={i} style={{ flex: 1, height: `${h}%`, background: `linear-gradient(180deg, ${i % 4 === 0 ? "#00d4ff" : "#22d3a0"}, rgba(34,211,160,0.15))`, borderRadius: "2px" }} />;
                })}
              </div>
            </div>

            {/* Connect button */}
            <div style={{
              padding: "12px 18px",
              borderRadius: "999px",
              background: "linear-gradient(135deg, #22d3a0, #00d4ff)",
              color: "#001a14",
              fontFamily: "'Unbounded', sans-serif",
              fontWeight: 800,
              fontSize: "14px",
              textAlign: "center",
              letterSpacing: "0.04em",
              boxShadow: "0 10px 30px rgba(34,211,160,0.45)",
              alignSelf: "stretch",
            }}>
              {lang === "zh" ? "一键加速" : "ONE-TAP ACCELERATE"}
            </div>
          </div>
        </div>
      </div>

      {/* BOTTOM: platform icons */}
      <div style={{ position: "absolute", left: "70px", right: "70px", bottom: "40px" }}>
        <div style={{ fontFamily: "'JetBrains Mono', monospace", fontSize: "12px", color: "#7a8290", letterSpacing: "0.2em", textTransform: "uppercase", marginBottom: "14px" }}>
          {c.platforms_label}
        </div>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <PlatformIcons />
          <div style={{ fontFamily: "'JetBrains Mono', monospace", fontSize: "14px", color: "#22d3a0", letterSpacing: "0.15em" }}>{c.url}</div>
        </div>
      </div>
    </div>
  );
};

export default OGCard;
