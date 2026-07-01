'use client';
import { useEffect, useState, useRef, createContext, useContext } from "react";
import { motion, AnimatePresence } from "framer-motion";
import {
  Shield, Zap, Globe, Lock, Smartphone, Shuffle, Headphones, Check,
  ArrowRight, Menu, X, ChevronDown, Download, Mail, Power, Sparkles, TrendingUp,
  Sun, Moon, Languages, Cpu, Infinity as InfinityIcon,
} from "lucide-react";
import { t as translate, detectLang, SUPPORTED_LANGS, RTL_LANGS } from "./i18n";
import "./landing.css";

// ============ Contexts ============
const AppCtx = createContext({ lang: "en", setLang: () => {}, theme: "dark", setTheme: () => {} });
export const useApp = () => useContext(AppCtx);
const useT = () => {
  const { lang } = useApp();
  return (k) => translate(k, lang);
};

// ============ SVG Illustrations ============
const OrbitGraphic = ({ className = "" }) => (
  <svg viewBox="0 0 400 400" className={className} fill="none" aria-hidden="true">
    <defs>
      <radialGradient id="og-core" cx="50%" cy="50%" r="50%">
        <stop offset="0%" stopColor="var(--accent-cyan)" stopOpacity="0.9" />
        <stop offset="100%" stopColor="var(--accent-cyan)" stopOpacity="0" />
      </radialGradient>
      <linearGradient id="og-ring" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0%" stopColor="var(--accent-cyan)" stopOpacity="0.8" />
        <stop offset="100%" stopColor="var(--accent-magenta)" stopOpacity="0.4" />
      </linearGradient>
    </defs>
    <circle cx="200" cy="200" r="60" fill="url(#og-core)" />
    <g className="orbit-spin" style={{ transformOrigin: "200px 200px" }}>
      <ellipse cx="200" cy="200" rx="170" ry="60" stroke="url(#og-ring)" strokeWidth="1" />
      <circle cx="370" cy="200" r="4" fill="var(--accent-cyan)" />
    </g>
    <g className="orbit-spin-rev" style={{ transformOrigin: "200px 200px" }}>
      <ellipse cx="200" cy="200" rx="120" ry="160" stroke="url(#og-ring)" strokeWidth="1" />
      <circle cx="200" cy="40" r="3" fill="var(--accent-magenta)" />
    </g>
    <g className="orbit-spin" style={{ transformOrigin: "200px 200px", animationDuration: "20s" }}>
      <ellipse cx="200" cy="200" rx="180" ry="140" stroke="var(--border-strong)" strokeWidth="0.5" strokeDasharray="2 6" />
      <circle cx="20" cy="200" r="3" fill="var(--accent-success)" />
    </g>
  </svg>
);

const CircuitGraphic = ({ className = "" }) => (
  <svg viewBox="0 0 600 200" className={className} fill="none" aria-hidden="true">
    <defs>
      <linearGradient id="cg" x1="0" y1="0" x2="1" y2="0">
        <stop offset="0%" stopColor="var(--accent-cyan)" stopOpacity="0" />
        <stop offset="50%" stopColor="var(--accent-cyan)" stopOpacity="0.8" />
        <stop offset="100%" stopColor="var(--accent-magenta)" stopOpacity="0" />
      </linearGradient>
    </defs>
    {[40, 80, 120, 160].map((y, i) => (
      <path
        key={y}
        d={`M0 ${y} L${80 + i * 30} ${y} L${120 + i * 30} ${y - 20} L${300 + i * 20} ${y - 20} L${340 + i * 20} ${y} L600 ${y}`}
        stroke="url(#cg)"
        strokeWidth="1"
        className="circuit-pulse"
        style={{ animationDelay: `${i * 0.4}s` }}
      />
    ))}
    {[100, 200, 350, 480].map((x, i) => (
      <circle key={x} cx={x} cy={40 + (i % 2) * 80} r="3" fill="var(--accent-cyan)" className="pulse-dot" />
    ))}
  </svg>
);

// ============ Nav ============
const Nav = () => {
  const t = useT();
  const { lang, setLang, theme, setTheme } = useApp();
  const [open, setOpen] = useState(false);
  const [langOpen, setLangOpen] = useState(false);
  const [scrolled, setScrolled] = useState(false);
  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 30);
    window.addEventListener("scroll", onScroll);
    return () => window.removeEventListener("scroll", onScroll);
  }, []);
  const links = [
    { href: "/#features", key: "nav_features" },
    { href: "/#network", key: "nav_network" },
    { href: "/#pricing", key: "nav_pricing" },
    { href: "/download", key: "ob_s1_t" },
    { href: "/#faq", key: "nav_faq" },
  ];
  const currentLang = SUPPORTED_LANGS.find((l) => l.code === lang);

  return (
    <header className={`fixed top-0 left-0 right-0 z-50 transition-all duration-300 ${scrolled ? "py-3" : "py-5"}`} data-testid="main-nav">
      <div className="mx-auto max-w-7xl px-6 sm:px-8">
        <div className={`flex flex-nowrap items-center justify-between gap-2 rounded-full px-4 sm:px-5 py-3 ${scrolled ? "glass" : ""}`}>
          <a href="/" className="flex items-center gap-2 min-w-0" data-testid="nav-logo">
            <img src="/icon-192.png" alt="MirrorSpeed" className="h-8 w-8 rounded-lg shrink-0" style={{ boxShadow: "0 0 12px rgba(34,211,160,0.4)" }} />
            <span className="font-heading font-bold text-lg tracking-tight text-app-primary truncate">MirrorSpeed</span>
          </a>

          <nav className="hidden md:flex items-center gap-7">
            {links.map((l) => (
              <a key={l.href} href={l.href} className="text-sm text-app-secondary hover:text-app-primary transition-colors" data-testid={`nav-link-${l.key.replace("nav_", "")}`}>
                {t(l.key)}
              </a>
            ))}
          </nav>

          <div className="flex items-center gap-2 shrink-0">
            <button
              onClick={() => setTheme(theme === "dark" ? "light" : "dark")}
              className="p-2 rounded-full hover:bg-app-tertiary transition-colors text-app-secondary"
              aria-label="Toggle theme"
              data-testid="theme-toggle"
            >
              {theme === "dark" ? <Sun className="h-4 w-4" /> : <Moon className="h-4 w-4" />}
            </button>

            <div className="relative">
              <button
                onClick={() => setLangOpen(!langOpen)}
                className="inline-flex items-center gap-1 p-2 rounded-full hover:bg-app-tertiary transition-colors text-app-secondary"
                data-testid="lang-toggle"
                aria-label="Language"
              >
                <Languages className="h-4 w-4" />
                <span className="text-xs font-mono hidden sm:inline">{currentLang?.code.toUpperCase()}</span>
              </button>
              <AnimatePresence>
                {langOpen && (
                  <motion.div
                    initial={{ opacity: 0, y: -8 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={{ opacity: 0, y: -8 }}
                    className="absolute right-0 mt-2 w-44 glass rounded-2xl p-2 max-h-80 overflow-y-auto"
                    data-testid="lang-menu"
                  >
                    {SUPPORTED_LANGS.map((l) => (
                      <button
                        key={l.code}
                        onClick={() => { setLang(l.code); setLangOpen(false); }}
                        className={`w-full text-left px-3 py-2 rounded-lg text-sm hover:bg-app-tertiary transition-colors ${lang === l.code ? "text-accent-cyan font-semibold" : "text-app-secondary"}`}
                        data-testid={`lang-option-${l.code}`}
                      >
                        {l.native}
                      </button>
                    ))}
                  </motion.div>
                )}
              </AnimatePresence>
            </div>

            <a href="https://mirrorspeed.com/login" className="hidden sm:inline-flex text-sm text-app-secondary hover:text-app-primary px-3 py-2" data-testid="nav-login-link">
              {t("nav_signin")}
            </a>
            {/* 手机端隐藏 CTA（移入汉堡菜单），避免与 logo/主题键挤在一起、文字被压成竖排 */}
            <a href="/download" className="group hidden sm:inline-flex items-center gap-1.5 rounded-full px-4 py-2 text-sm font-semibold whitespace-nowrap shrink-0 hover:opacity-90 transition" style={{ background: "var(--text-primary)", color: "var(--bg-primary)" }} data-testid="nav-cta-button">
              {t("nav_get_started")}
              <ArrowRight className="h-3.5 w-3.5 transition-transform group-hover:translate-x-0.5" />
            </a>
            <button onClick={() => setOpen(!open)} className="md:hidden p-2 text-app-primary shrink-0" aria-label="Menu" data-testid="nav-mobile-toggle">
              {open ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
            </button>
          </div>
        </div>
        <AnimatePresence>
          {open && (
            <motion.div initial={{ opacity: 0, y: -8 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -8 }} className="md:hidden glass mt-2 rounded-2xl p-4 space-y-2">
              {links.map((l) => (
                <a key={l.href} href={l.href} onClick={() => setOpen(false)} className="block py-2 text-app-secondary">{t(l.key)}</a>
              ))}
              <div className="pt-2 mt-1 border-t border-app-subtle flex flex-col gap-2">
                <a href="https://mirrorspeed.com/login" onClick={() => setOpen(false)} className="block py-2 text-app-secondary" data-testid="nav-mobile-login">{t("nav_signin")}</a>
                <a href="/download" onClick={() => setOpen(false)} className="inline-flex items-center justify-center gap-1.5 rounded-full px-4 py-2.5 text-sm font-semibold" style={{ background: "var(--text-primary)", color: "var(--bg-primary)" }} data-testid="nav-mobile-cta">
                  {t("nav_get_started")}
                  <ArrowRight className="h-3.5 w-3.5" />
                </a>
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </header>
  );
};

const StatPill = ({ label, value }) => (
  <div className="flex items-center gap-2">
    <div className="h-1.5 w-1.5 rounded-full bg-[var(--accent-success)] pulse-dot" />
    <span className="font-mono text-xs text-app-muted uppercase tracking-widest">{label}</span>
    <span className="font-heading text-sm text-app-primary font-semibold">{value}</span>
  </div>
);

// ============ Hero ============
const Hero = () => {
  const t = useT();
  const { lang } = useApp();
  const heroPrice = formatPrice(LOWEST_USD, lang);
  const heroPriceSuffix = ` — ${heroPrice.symbol}${heroPrice.value}${heroPrice.perSuffix || t("pr_monthly_short")}`;
  return (
    <section id="top" className="relative pt-36 sm:pt-44 pb-20 overflow-hidden" data-testid="hero-section">
      <div className="absolute inset-0 grid-bg opacity-40 pointer-events-none" />
      <div className="absolute top-20 left-1/4 h-[400px] w-[400px] rounded-full" style={{ background: "var(--accent-cyan-glow)", filter: "blur(120px)", opacity: 0.5 }} />
      <div className="absolute top-40 right-1/4 h-[300px] w-[300px] rounded-full" style={{ background: "rgba(255,0,85,0.18)", filter: "blur(100px)" }} />

      <OrbitGraphic className="absolute top-10 right-[-100px] h-[500px] w-[500px] opacity-30 pointer-events-none hidden lg:block" />

      <div className="relative max-w-6xl mx-auto px-6 sm:px-8">
        <motion.div initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.6 }} className="flex justify-center mb-8">
          <div className="inline-flex items-center gap-2 rounded-full glass px-4 py-1.5 text-xs">
            <Sparkles className="h-3.5 w-3.5 text-accent-cyan" />
            <span className="font-mono text-app-secondary tracking-widest uppercase">{t("hero_badge")}</span>
          </div>
        </motion.div>

        <motion.h1 initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.8, delay: 0.1 }} className="font-heading text-5xl sm:text-7xl lg:text-8xl font-black text-center leading-[0.95] tracking-tighter">
          <span className="text-gradient-hero">{t("hero_h1_1")}</span>
          <br />
          <span className="text-gradient-cyan">{t("hero_h1_2")}</span>
        </motion.h1>

        <motion.p initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.7, delay: 0.3 }} className="mt-8 text-center text-lg sm:text-xl text-app-secondary max-w-2xl mx-auto leading-relaxed">
          {t("hero_subtitle")}
        </motion.p>

        <motion.div initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.7, delay: 0.5 }} className="mt-10 flex flex-col sm:flex-row items-center justify-center gap-4">
          <a href="/download" className="group relative inline-flex items-center gap-2 rounded-full px-7 py-4 font-semibold text-base glow-cyan hover:scale-[1.02] transition-transform" style={{ background: "linear-gradient(135deg, var(--accent-cyan) 0%, #0080ff 100%)", color: "#000" }} data-testid="hero-cta-primary">
            <Download className="h-4 w-4" />
            {t("hero_cta_primary")}{heroPriceSuffix}
            <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-1" />
          </a>
          <a href="#network" className="inline-flex items-center gap-2 rounded-full glass glass-hover px-7 py-4 font-medium text-base text-app-primary" data-testid="hero-cta-secondary">
            <Sparkles className="h-4 w-4" />
            {t("hero_cta_secondary")}
          </a>
        </motion.div>

        <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ duration: 0.7, delay: 0.7 }} className="mt-16 flex flex-wrap items-center justify-center gap-x-8 gap-y-4">
          <StatPill label={t("stat_users")} value="100K+" />
          <span className="text-app-muted">·</span>
          <StatPill label={t("stat_edges")} value="20+" />
          <span className="text-app-muted">·</span>
          <StatPill label={t("stat_uptime")} value="99.9%" />
          <span className="text-app-muted">·</span>
          <StatPill label={t("stat_bandwidth")} value="1000 Mbps" />
        </motion.div>

        <motion.div initial={{ opacity: 0, y: 30 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 1, delay: 0.8 }} className="mt-20 relative mx-auto max-w-4xl">
          <div className="relative glass rounded-3xl p-8 sm:p-10 overflow-hidden noise-overlay">
            <div className="absolute inset-0 opacity-40 pointer-events-none" style={{ background: "radial-gradient(circle at 50% 50%, var(--accent-cyan-glow), transparent 60%)" }} />
            <div className="relative flex items-center justify-between mb-6">
              <div className="flex items-center gap-2">
                <div className="h-1.5 w-1.5 rounded-full bg-[var(--accent-success)] pulse-dot" />
                <span className="font-mono text-[10px] uppercase tracking-widest text-app-secondary">{t("canvas_global_edge")}</span>
              </div>
              <span className="font-mono text-[10px] uppercase tracking-widest text-app-muted">{t("canvas_throughput")}</span>
            </div>
            <div className="relative h-32 sm:h-40 flex items-end gap-[3px] sm:gap-1">
              {Array.from({ length: 64 }).map((_, i) => (
                <div key={i} className="flex-1 rounded-sm spectrum-bar" style={{ background: `linear-gradient(180deg, ${i % 7 === 0 ? "var(--accent-magenta)" : i % 3 === 0 ? "var(--accent-cyan)" : "#0080ff"} 0%, var(--accent-cyan-glow) 100%)`, animationDelay: `${i * 0.05}s`, animationDuration: `${1.2 + (i % 5) * 0.3}s` }} />
              ))}
            </div>
            <div className="relative mt-6 grid grid-cols-3 gap-6 pt-6 border-t border-app-subtle">
              <div>
                <div className="font-mono text-[10px] uppercase tracking-widest text-app-muted mb-1">{t("canvas_latency")}</div>
                <div className="font-heading text-xl sm:text-2xl font-bold" style={{ color: "var(--accent-success)" }}>{t("canvas_ultralow")}</div>
              </div>
              <div>
                <div className="font-mono text-[10px] uppercase tracking-widest text-app-muted mb-1">{t("canvas_edges")}</div>
                <div className="font-heading text-xl sm:text-2xl font-bold text-app-primary">{t("canvas_worldwide")}</div>
              </div>
              <div>
                <div className="font-mono text-[10px] uppercase tracking-widest text-app-muted mb-1">{t("canvas_peak")}</div>
                <div className="font-heading text-xl sm:text-2xl font-bold text-accent-cyan">1000 Mbps</div>
              </div>
            </div>
          </div>
        </motion.div>
      </div>
    </section>
  );
};

// ============ Onboarding ============
const Onboarding = () => {
  const t = useT();
  const steps = [
    { n: "01", t: "ob_s1_t", d: "ob_s1_d", icon: Download },
    { n: "02", t: "ob_s2_t", d: "ob_s2_d", icon: Mail },
    { n: "03", t: "ob_s3_t", d: "ob_s3_d", icon: Power },
  ];
  return (
    <section className="relative py-24 sm:py-32" data-testid="onboarding-section">
      <div className="max-w-6xl mx-auto px-6 sm:px-8">
        <div className="text-center mb-16">
          <span className="font-mono text-xs text-accent-cyan tracking-widest uppercase">{t("ob_kicker")}</span>
          <h2 className="font-heading text-4xl sm:text-5xl font-bold mt-3 tracking-tighter text-app-primary">
            {t("ob_title_a")} <span className="text-gradient-cyan">{t("ob_title_b")}</span>
          </h2>
          <p className="mt-4 text-app-secondary max-w-xl mx-auto">{t("ob_sub")}</p>
        </div>
        <div className="grid md:grid-cols-3 gap-6">
          {steps.map((s, i) => (
            <motion.div key={s.n} initial={{ opacity: 0, y: 20 }} whileInView={{ opacity: 1, y: 0 }} viewport={{ once: true }} transition={{ duration: 0.6, delay: i * 0.1 }} className="relative glass glass-hover rounded-2xl p-7 group">
              <div className="flex items-start justify-between mb-6">
                <span className="font-heading text-6xl font-black text-transparent" style={{ WebkitTextStroke: "1px var(--border-strong)" }}>{s.n}</span>
                <div className="h-10 w-10 rounded-full glass flex items-center justify-center group-hover:bg-[var(--accent-cyan-glow)] transition-colors">
                  <s.icon className="h-4 w-4 text-accent-cyan" />
                </div>
              </div>
              <h3 className="font-heading text-2xl font-semibold mb-2 text-app-primary">{t(s.t)}</h3>
              <p className="text-app-secondary text-sm leading-relaxed">{t(s.d)}</p>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  );
};

// ============ Features ============
const Features = () => {
  const t = useT();
  const items = [
    { titleK: "feat_proprietary", descK: "feat_proprietary_d", icon: Lock, span: "md:col-span-2 md:row-span-2", featured: true, tag: "AES-256 + ChaCha20 · QUIC-mirror" },
    { titleK: "feat_engine", descK: "feat_engine_d", icon: Cpu },
    { titleK: "feat_zerologs", descK: "feat_zerologs_d", icon: Shield },
    { titleK: "feat_multi", descK: "feat_multi_d", icon: Smartphone },
    { titleK: "feat_unlimited", descK: "feat_unlimited_d", icon: InfinityIcon },
    { titleK: "feat_switch", descK: "feat_switch_d", icon: Shuffle },
    { titleK: "feat_global", descK: "feat_global_d", icon: Globe },
    { titleK: "feat_support", descK: "feat_support_d", icon: Headphones, span: "md:col-span-2" },
  ];
  return (
    <section id="features" className="relative py-24 sm:py-32" data-testid="features-section">
      <div className="max-w-6xl mx-auto px-6 sm:px-8">
        <div className="flex flex-col md:flex-row md:items-end md:justify-between mb-12 gap-4">
          <div>
            <span className="font-mono text-xs text-accent-cyan tracking-widest uppercase">{t("feat_kicker")}</span>
            <h2 className="font-heading text-4xl sm:text-5xl font-bold mt-3 tracking-tighter text-app-primary">
              {t("feat_h1")}<br />
              <span className="text-gradient-cyan">{t("feat_h2")}</span>
            </h2>
          </div>
          <p className="text-app-secondary max-w-md">{t("feat_sub")}</p>
        </div>
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4 auto-rows-[200px]">
          {items.map((it, i) => (
            <motion.div key={it.titleK} initial={{ opacity: 0, y: 20 }} whileInView={{ opacity: 1, y: 0 }} viewport={{ once: true }} transition={{ duration: 0.5, delay: i * 0.05 }} className={`relative glass glass-hover rounded-2xl p-6 overflow-hidden group ${it.span || ""} ${it.featured ? "border-gradient" : ""}`} data-testid={`feature-card-${it.titleK}`}>
              {it.featured && <div className="absolute -top-20 -right-20 h-60 w-60 rounded-full" style={{ background: "var(--accent-cyan-glow)", filter: "blur(60px)", opacity: 0.5 }} />}
              {it.featured && (
                <svg viewBox="0 0 200 200" className="absolute right-4 top-1/2 -translate-y-1/2 h-44 w-44 opacity-90 pointer-events-none" fill="none" aria-hidden="true">
                  <defs>
                    <radialGradient id="pc-core" cx="50%" cy="50%" r="50%">
                      <stop offset="0%" stopColor="var(--accent-cyan)" stopOpacity="0.9" />
                      <stop offset="100%" stopColor="var(--accent-cyan)" stopOpacity="0" />
                    </radialGradient>
                    <linearGradient id="pc-ring" x1="0" y1="0" x2="1" y2="1">
                      <stop offset="0%" stopColor="var(--accent-cyan)" stopOpacity="0.9" />
                      <stop offset="100%" stopColor="var(--accent-magenta)" stopOpacity="0.6" />
                    </linearGradient>
                  </defs>
                  <circle cx="100" cy="100" r="28" fill="url(#pc-core)" />
                  <g className="orbit-spin" style={{ transformOrigin: "100px 100px" }}>
                    <circle cx="100" cy="100" r="55" stroke="url(#pc-ring)" strokeWidth="1" strokeDasharray="4 6" />
                    <circle cx="155" cy="100" r="3" fill="var(--accent-cyan)" />
                    <circle cx="45" cy="100" r="2" fill="var(--accent-magenta)" />
                  </g>
                  <g className="orbit-spin-rev" style={{ transformOrigin: "100px 100px" }}>
                    <circle cx="100" cy="100" r="78" stroke="var(--border-strong)" strokeWidth="0.5" strokeDasharray="2 8" />
                    <circle cx="100" cy="22" r="2.5" fill="var(--accent-success)" />
                    <circle cx="100" cy="178" r="2" fill="var(--accent-cyan)" />
                  </g>
                  <g className="orbit-spin" style={{ transformOrigin: "100px 100px", animationDuration: "16s" }}>
                    <text x="40" y="50" fontFamily="JetBrains Mono, monospace" fontSize="6" fill="var(--accent-cyan)" opacity="0.7">01101001</text>
                    <text x="120" y="160" fontFamily="JetBrains Mono, monospace" fontSize="6" fill="var(--accent-magenta)" opacity="0.7">11010010</text>
                  </g>
                  <path d="M100 78 L100 70 M100 130 L100 122 M78 100 L70 100 M130 100 L122 100" stroke="var(--accent-cyan)" strokeWidth="1.5" strokeLinecap="round" className="circuit-pulse" />
                </svg>
              )}
              <div className="relative flex flex-col h-full justify-between">
                <div className="h-11 w-11 rounded-xl glass flex items-center justify-center">
                  <it.icon className="h-5 w-5 text-accent-cyan" />
                </div>
                <div>
                  <h3 className="font-heading text-xl font-semibold mb-1.5 text-app-primary">{t(it.titleK)}</h3>
                  <p className="text-app-secondary text-sm leading-relaxed">{t(it.descK)}</p>
                  {it.tag && <div className="mt-4 inline-flex items-center gap-2 font-mono text-xs text-accent-cyan tracking-widest">{it.tag}</div>}
                </div>
              </div>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  );
};

// ============ Global Network ============
const GlobalNetwork = () => {
  const t = useT();
  const cols = 22, rows = 8;
  const dots = [];
  for (let r = 0; r < rows; r++) for (let c = 0; c < cols; c++) {
    const dx = c / cols, dy = r / rows;
    const asia = dx > 0.6 && dx < 0.95 && dy > 0.25 && dy < 0.75;
    const europe = dx > 0.45 && dx < 0.62 && dy > 0.2 && dy < 0.55;
    const americas = dx > 0.05 && dx < 0.32 && dy > 0.25 && dy < 0.7;
    dots.push({ id: `${r}-${c}`, live: asia || europe || americas });
  }
  const [tick, setTick] = useState(0);
  useEffect(() => { const tm = setInterval(() => setTick((x) => x + 1), 1400); return () => clearInterval(tm); }, []);
  const liveDots = dots.filter((d) => d.live);
  const hot = new Set();
  for (let i = 0; i < 8; i++) hot.add((tick * 7 + i * 13) % liveDots.length);

  return (
    <section id="network" className="relative py-24 sm:py-32" data-testid="server-matrix-section">
      <div className="max-w-6xl mx-auto px-6 sm:px-8">
        <div className="text-center mb-12">
          <span className="font-mono text-xs text-accent-cyan tracking-widest uppercase">{t("net_kicker")}</span>
          <h2 className="font-heading text-4xl sm:text-5xl font-bold mt-3 tracking-tighter text-app-primary">
            {t("net_h1")} <span className="text-gradient-cyan">{t("net_h2")}</span>
          </h2>
          <p className="mt-4 text-app-secondary max-w-xl mx-auto">{t("net_sub")}</p>
        </div>

        <div className="relative glass rounded-3xl overflow-hidden p-6 sm:p-10" data-testid="global-network-canvas">
          <div className="absolute inset-0 grid-bg opacity-30 pointer-events-none" />
          <div className="absolute -top-20 left-1/4 h-72 w-72 rounded-full float-orb pointer-events-none" style={{ background: "var(--accent-cyan-glow)", filter: "blur(100px)", opacity: 0.4 }} />
          <CircuitGraphic className="absolute inset-x-0 top-1/2 -translate-y-1/2 w-full opacity-30 pointer-events-none" />

          <div className="relative flex items-center justify-between mb-6 sm:mb-8">
            <div className="flex items-center gap-2">
              <div className="h-1.5 w-1.5 rounded-full bg-[var(--accent-success)] pulse-dot" />
              <span className="font-mono text-[10px] uppercase tracking-widest text-app-secondary">{t("net_live")}</span>
            </div>
            <span className="font-mono text-[10px] uppercase tracking-widest text-app-muted">{t("net_pulse")}</span>
          </div>

          <div className="relative grid gap-1.5 sm:gap-2 mx-auto" style={{ gridTemplateColumns: `repeat(${cols}, minmax(0, 1fr))`, maxWidth: "880px" }} aria-hidden="true">
            {dots.map((d) => {
              const isHot = d.live && hot.has(liveDots.indexOf(d));
              return (
                <div key={d.id} className="aspect-square rounded-full transition-all duration-700" style={{
                  background: d.live ? (isHot ? "var(--accent-cyan)" : "var(--accent-cyan-glow)") : "var(--border-subtle)",
                  boxShadow: isHot ? "0 0 12px var(--accent-cyan), 0 0 24px var(--accent-cyan-glow)" : "none",
                  transform: isHot ? "scale(1.4)" : "scale(1)",
                }} />
              );
            })}
          </div>

          <div className="relative mt-8 grid grid-cols-3 gap-4 sm:gap-6 pt-6 border-t border-app-subtle text-center">
            {[{ k: "net_americas", c: "var(--accent-cyan)" }, { k: "net_europe", c: "var(--accent-magenta)" }, { k: "net_asia", c: "var(--accent-success)" }].map((r) => (
              <div key={r.k} className="flex items-center justify-center gap-2">
                <div className="h-1.5 w-1.5 rounded-full pulse-dot" style={{ background: r.c }} />
                <span className="font-mono text-xs uppercase tracking-widest text-app-secondary">{t(r.k)} · {t("net_online")}</span>
              </div>
            ))}
          </div>
        </div>

        <div className="mt-8 grid grid-cols-1 sm:grid-cols-3 gap-4">
          <div className="glass glass-hover rounded-2xl p-6">
            <div className="font-heading text-4xl sm:text-5xl font-black tracking-tighter text-gradient-cyan">20+</div>
            <div className="mt-2 text-sm text-app-primary font-medium">{t("net_kpi1")}</div>
            <div className="font-mono text-[10px] uppercase tracking-widest text-app-muted mt-1">{t("net_kpi1s")}</div>
          </div>
          <div className="glass glass-hover rounded-2xl p-6">
            <div className="font-heading text-4xl sm:text-5xl font-black tracking-tighter text-gradient-cyan">{t("net_kpi2v")}</div>
            <div className="mt-2 text-sm text-app-primary font-medium">{t("net_kpi2")}</div>
            <div className="font-mono text-[10px] uppercase tracking-widest text-app-muted mt-1">{t("net_kpi2s")}</div>
          </div>
          <div className="glass glass-hover rounded-2xl p-6">
            <div className="font-heading text-4xl sm:text-5xl font-black tracking-tighter text-gradient-cyan">99.9%</div>
            <div className="mt-2 text-sm text-app-primary font-medium">{t("net_kpi3")}</div>
            <div className="font-mono text-[10px] uppercase tracking-widest text-app-muted mt-1">{t("net_kpi3s")}</div>
          </div>
        </div>
      </div>
    </section>
  );
};

// ============ Testimonials ============
const Testimonials = () => {
  const t = useT();
  const items = [
    { q: { en: "Stupid fast. The nearest edge always picks me up — feels like the VPN isn't even there.", zh: "快得离谱。最近的节点总能接住我——感觉 VPN 根本不存在。", fr: "Incroyablement rapide.", es: "Rapidísimo.", de: "Wahnsinnig schnell.", it: "Velocissimo.", ja: "ばか速い。", ko: "미친 듯이 빠릅니다.", tr: "Aptal kadar hızlı.", ar: "سريع لدرجة الجنون.", ru: "Бешено быстро." }, a: "Alex T.", role: { en: "Developer", zh: "开发者", fr: "Développeur", es: "Desarrollador", de: "Entwickler", it: "Sviluppatore", ja: "開発者", ko: "개발자", tr: "Geliştirici", ar: "مطوّر", ru: "Разработчик" }, avatar: "A", color: "var(--accent-cyan)" },
    { q: { en: "Set it once, forget it. Auto-routing just works.", zh: "设置一次就忘记，自动路由完美。", fr: "Configurez, oubliez.", es: "Configúralo y olvídalo.", de: "Einmal einrichten, vergessen.", it: "Imposta e dimentica.", ja: "一度設定すれば忘れていい。", ko: "한 번 설정하면 끝.", tr: "Bir kez ayarla, unut.", ar: "اضبطه مرة وانساه.", ru: "Настроил и забыл." }, a: "Sarah M.", role: { en: "Freelancer", zh: "自由职业者", fr: "Indépendante", es: "Freelance", de: "Freelancerin", it: "Freelance", ja: "フリーランス", ko: "프리랜서", tr: "Serbest çalışan", ar: "مستقلّة", ru: "Фрилансер" }, avatar: "S", color: "var(--accent-magenta)" },
    { q: { en: "3 devices on one account at this price is unbeatable.", zh: "一个账号 3 台设备，这个价格无敌。", fr: "3 appareils, imbattable.", es: "3 dispositivos, imbatible.", de: "3 Geräte, unschlagbar.", it: "3 dispositivi, imbattibile.", ja: "1 アカウント 3 台でこの価格は最強。", ko: "이 가격에 3대 동시 사용, 무적.", tr: "Bu fiyata 3 cihaz, rakipsiz.", ar: "3 أجهزة بهذا السعر، لا يُهزَم.", ru: "3 устройства за такую цену — вне конкуренции." }, a: "Ken W.", role: { en: "Founder", zh: "创始人", fr: "Fondateur", es: "Fundador", de: "Gründer", it: "Fondatore", ja: "創業者", ko: "창업자", tr: "Kurucu", ar: "مؤسّس", ru: "Основатель" }, avatar: "K", color: "var(--accent-success)" },
    { q: { en: "Latency is so low I forget I'm tunneling.", zh: "延迟低到我都忘了在用 VPN。游戏、流媒体、开发——都顺。", fr: "Latence si basse que j'oublie le VPN.", es: "Latencia tan baja que olvido el VPN.", de: "So niedrige Latenz, dass ich das VPN vergesse.", it: "Latenza così bassa che dimentico la VPN.", ja: "遅延が低すぎて VPN を使っていることを忘れる。", ko: "지연이 너무 낮아 VPN 쓰는 줄 잊습니다.", tr: "Gecikme o kadar düşük ki VPN'i unutuyorum.", ar: "زمن الاستجابة منخفض جدًا حتى أنسى أنني على VPN.", ru: "Задержка так низкая, что забываешь о VPN." }, a: "Mika R.", role: { en: "Streamer", zh: "主播", fr: "Streameuse", es: "Streamer", de: "Streamer", it: "Streamer", ja: "配信者", ko: "스트리머", tr: "Yayıncı", ar: "بثّ مباشر", ru: "Стример" }, avatar: "M", color: "var(--accent-warning)" },
  ];
  const { lang } = useApp();
  return (
    <section className="relative py-24 sm:py-32" data-testid="testimonials-section">
      <div className="max-w-6xl mx-auto px-6 sm:px-8">
        <div className="text-center mb-14">
          <span className="font-mono text-xs text-accent-cyan tracking-widest uppercase">{t("test_kicker")}</span>
          <h2 className="font-heading text-4xl sm:text-5xl font-bold mt-3 tracking-tighter text-app-primary">
            {t("test_h1")} <span className="text-gradient-cyan">{t("test_h2")}</span>
          </h2>
          <p className="mt-4 text-app-secondary">{t("test_sub")}</p>
        </div>
        <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-5">
          {items.map((it, i) => (
            <motion.div key={it.a} initial={{ opacity: 0, y: 16 }} whileInView={{ opacity: 1, y: 0 }} viewport={{ once: true }} transition={{ duration: 0.5, delay: i * 0.08 }} className="glass glass-hover rounded-2xl p-6 flex flex-col gap-5">
              <p className="text-app-primary text-sm leading-relaxed">&ldquo;{it.q[lang] || it.q.en}&rdquo;</p>
              <div className="flex items-center gap-3 mt-auto pt-4 border-t border-app-subtle">
                <div className="h-9 w-9 rounded-full flex items-center justify-center font-heading text-sm font-bold" style={{ background: `${it.color}22`, color: it.color, border: `1px solid ${it.color}` }}>{it.avatar}</div>
                <div>
                  <div className="text-sm text-app-primary font-medium">{it.a}</div>
                  <div className="text-xs text-app-muted">{it.role[lang] || it.role.en}</div>
                </div>
              </div>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  );
};

// ============ Pricing ============
// CNY exchange rate (USD → CNY), rounded UP to nearest integer for Chinese display
const USD_TO_CNY = 7.2;
const formatPrice = (usd, lang) => {
  if (lang === "zh") {
    const cny = Math.ceil(usd * USD_TO_CNY);
    return { symbol: "¥", value: String(cny), perSuffix: "/月" };
  }
  return { symbol: "$", value: usd.toFixed(2), perSuffix: null }; // null = use translation
};

const Pricing = () => {
  const t = useT();
  const { lang } = useApp();
  const plans = [
    { nameK: "pr_monthly", usd: 3.00, noteK: "pr_billed_m", savePct: null, testId: "monthly" },
    { nameK: "pr_quarterly", usd: 1.80, noteK: "pr_billed_q", savePct: 40, testId: "quarterly" },
    { nameK: "pr_halfyear", usd: 1.50, noteK: "pr_billed_h", savePct: 50, testId: "halfyear" },
    { nameK: "pr_yearly", usd: 1.20, noteK: "pr_billed_y", savePct: 60, testId: "yearly" },
    { nameK: "pr_2yr", usd: 1.00, noteK: "pr_billed_2y", featured: true, badgeK: "pr_popular", savePct: 67, testId: "2yr" },
  ];
  const perks = ["perk_locations", "perk_encryption", "perk_devices", "perk_bw", "perk_support", "perk_cancel"];
  return (
    <section id="pricing" className="relative py-24 sm:py-32" data-testid="pricing-section">
      <div className="absolute inset-x-0 top-1/2 -translate-y-1/2 h-[500px] pointer-events-none" style={{ background: "var(--accent-cyan-glow)", filter: "blur(120px)", opacity: 0.15 }} />
      <div className="relative max-w-7xl mx-auto px-6 sm:px-8">
        <div className="text-center mb-14">
          <span className="font-mono text-xs text-accent-cyan tracking-widest uppercase">{t("pr_kicker")}</span>
          <h2 className="font-heading text-4xl sm:text-5xl font-bold mt-3 tracking-tighter text-app-primary">
            {t("pr_h1")} <span className="text-gradient-cyan">{t("pr_h2")}</span>
          </h2>
          <p className="mt-4 text-app-secondary">{t("pr_sub")}</p>
        </div>
        <div className="grid sm:grid-cols-2 lg:grid-cols-5 gap-4">
          {plans.map((p) => {
            const price = formatPrice(p.usd, lang);
            const perSuffix = price.perSuffix || t("pr_monthly_short");
            return (
              <motion.div key={p.nameK} initial={{ opacity: 0, y: 20 }} whileInView={{ opacity: 1, y: 0 }} viewport={{ once: true }} transition={{ duration: 0.5 }} className={`relative rounded-3xl p-6 flex flex-col ${p.featured ? "lg:scale-[1.04] lg:-translate-y-2 border glow-cyan" : "glass glass-hover"}`} style={p.featured ? { background: "linear-gradient(180deg, var(--accent-cyan-glow) 0%, transparent 80%)", borderColor: "var(--accent-cyan)" } : {}} data-testid={`pricing-card-${p.testId}`}>
                {p.featured && (
                  <div className="absolute -top-3 left-1/2 -translate-x-1/2">
                    <div className="inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-[10px] font-bold tracking-widest font-mono whitespace-nowrap" style={{ background: "linear-gradient(135deg, var(--accent-cyan) 0%, #0080ff 100%)", color: "#000" }}>
                      <TrendingUp className="h-3 w-3" />
                      {t(p.badgeK)}
                    </div>
                  </div>
                )}
                <div className="mb-4">
                  <div className="text-sm text-app-secondary font-medium">{t(p.nameK)}</div>
                  {p.savePct !== null && (
                    <div className="font-mono text-xs mt-1 tracking-wider" style={{ color: "var(--accent-success)" }}>
                      {t("pr_save_word")} {p.savePct}%
                    </div>
                  )}
                  {p.savePct === null && <div className="font-mono text-xs mt-1 tracking-wider opacity-0">_</div>}
                </div>
                <div className="mb-1 flex items-baseline gap-1">
                  <span className="text-app-muted text-xl">{price.symbol}</span>
                  <span className="font-heading text-4xl font-black tracking-tighter text-app-primary">{price.value}</span>
                  <span className="text-app-muted text-sm">{perSuffix}</span>
                </div>
                <div className="text-xs text-app-muted mb-5">{t(p.noteK)}</div>
                <ul className="space-y-2.5 mb-6 flex-1">
                  {perks.map((perk) => (
                    <li key={perk} className="flex items-start gap-2 text-xs text-app-primary">
                      <Check className="h-3.5 w-3.5 mt-0.5 flex-shrink-0" style={{ color: p.featured ? "var(--accent-cyan)" : "var(--text-muted)" }} />
                      <span>{t(perk)}</span>
                    </li>
                  ))}
                </ul>
                <a href="https://mirrorspeed.com/login" className={`group inline-flex items-center justify-center gap-2 rounded-full px-4 py-2.5 font-semibold text-sm transition-all ${p.featured ? "hover:scale-[1.02]" : "glass text-app-primary hover:bg-app-tertiary"}`} style={p.featured ? { background: "linear-gradient(135deg, var(--accent-cyan) 0%, #0080ff 100%)", color: "#000" } : {}} data-testid={`pricing-cta-${p.testId}`}>
                  {p.featured ? t("nav_get_started") : t("pr_select")}
                  <ArrowRight className="h-3.5 w-3.5 transition-transform group-hover:translate-x-0.5" />
                </a>
              </motion.div>
            );
          })}
        </div>
        <div className="mt-10 flex flex-wrap items-center justify-center gap-x-6 gap-y-2 text-xs text-app-muted font-mono uppercase tracking-widest">
          <span className="flex items-center gap-1.5"><Shield className="h-3.5 w-3.5" style={{ color: "var(--accent-success)" }} /> {t("trust_refund")}</span>
          <span>·</span>
          <span className="flex items-center gap-1.5"><Lock className="h-3.5 w-3.5 text-accent-cyan" /> {t("trust_checkout")}</span>
          <span>·</span>
          <span className="flex items-center gap-1.5"><Zap className="h-3.5 w-3.5" style={{ color: "var(--accent-magenta)" }} /> {t("trust_instant")}</span>
        </div>
      </div>
    </section>
  );
};

// Lowest price helper for hero/final CTAs (2-year plan)
const LOWEST_USD = 1.00;

// ============ FAQ ============
const FAQ = () => {
  const t = useT();
  const items = [
    { q: "faq_q1", a: "faq_a1" }, { q: "faq_q2", a: "faq_a2" }, { q: "faq_q3", a: "faq_a3" },
    { q: "faq_q4", a: "faq_a4" }, { q: "faq_q5", a: "faq_a5" }, { q: "faq_q6", a: "faq_a6" },
  ];
  const [open, setOpen] = useState(0);
  return (
    <section id="faq" className="relative py-24 sm:py-32" data-testid="faq-section">
      <div className="max-w-3xl mx-auto px-6 sm:px-8">
        <div className="text-center mb-14">
          <span className="font-mono text-xs text-accent-cyan tracking-widest uppercase">{t("faq_kicker")}</span>
          <h2 className="font-heading text-4xl sm:text-5xl font-bold mt-3 tracking-tighter text-app-primary">
            {t("faq_h1")} <span className="text-gradient-cyan">{t("faq_h2")}</span>
          </h2>
        </div>
        <div className="space-y-1">
          {items.map((it, i) => (
            <div key={it.q} className="border-b border-app-subtle" data-testid={`faq-item-${i}`}>
              <button onClick={() => setOpen(open === i ? -1 : i)} className="w-full flex items-center justify-between py-5 text-left group" data-testid={`faq-toggle-${i}`}>
                <span className="font-heading text-lg font-medium text-app-primary group-hover:text-accent-cyan transition-colors">{t(it.q)}</span>
                <ChevronDown className={`h-5 w-5 text-app-muted transition-transform ${open === i ? "rotate-180 text-accent-cyan" : ""}`} />
              </button>
              <AnimatePresence>
                {open === i && (
                  <motion.div initial={{ height: 0, opacity: 0 }} animate={{ height: "auto", opacity: 1 }} exit={{ height: 0, opacity: 0 }} transition={{ duration: 0.3 }} className="overflow-hidden">
                    <p className="pb-5 text-app-secondary leading-relaxed">{t(it.a)}</p>
                  </motion.div>
                )}
              </AnimatePresence>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
};

// ============ Final CTA ============
const FinalCTA = () => {
  const t = useT();
  const { lang } = useApp();
  const ctaPrice = formatPrice(LOWEST_USD, lang);
  const ctaPriceSuffix = ` — ${ctaPrice.symbol}${ctaPrice.value}${ctaPrice.perSuffix || t("pr_monthly_short")}`;
  return (
    <section className="relative py-24 sm:py-32" data-testid="final-cta-section">
      <div className="max-w-5xl mx-auto px-6 sm:px-8">
        <div className="relative overflow-hidden rounded-[2.5rem] border border-app-subtle bg-app-secondary p-10 sm:p-16 noise-overlay">
          <div className="absolute -top-40 -right-40 h-[400px] w-[400px] rounded-full float-orb" style={{ background: "var(--accent-cyan-glow)", filter: "blur(120px)", opacity: 0.4 }} />
          <div className="absolute -bottom-40 -left-40 h-[400px] w-[400px] rounded-full float-orb" style={{ background: "rgba(255,0,85,0.18)", filter: "blur(120px)", animationDelay: "8s" }} />
          <div className="relative text-center">
            <motion.h2 initial={{ opacity: 0, y: 20 }} whileInView={{ opacity: 1, y: 0 }} viewport={{ once: true }} transition={{ duration: 0.7 }} className="font-heading text-4xl sm:text-6xl lg:text-7xl font-black tracking-tighter text-gradient-hero">
              {t("cta_h1")}<br />
              <span className="text-gradient-cyan">{t("cta_h2")}</span>
            </motion.h2>
            <p className="mt-6 text-app-secondary max-w-xl mx-auto">{t("cta_sub")}</p>
            <div className="mt-10 flex flex-col sm:flex-row items-center justify-center gap-4">
              <a href="/download" className="group inline-flex items-center gap-2 rounded-full px-8 py-4 font-semibold text-base glow-cyan hover:scale-[1.02] transition-transform" style={{ background: "linear-gradient(135deg, var(--accent-cyan) 0%, #0080ff 100%)", color: "#000" }} data-testid="final-cta-primary">
                {t("cta_btn")}{ctaPriceSuffix}
                <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-1" />
              </a>
              <a href="#pricing" className="inline-flex items-center gap-2 text-sm text-app-secondary hover:text-app-primary">{t("cta_compare")}</a>
            </div>
            <div className="mt-8 flex items-center justify-center gap-2 font-mono text-[11px] uppercase tracking-widest text-app-muted">
              <Shield className="h-3.5 w-3.5" style={{ color: "var(--accent-success)" }} />
              {t("cta_trust")}
            </div>
          </div>
        </div>
      </div>
    </section>
  );
};

// ============ Footer ============
const Footer = () => {
  const t = useT();
  const { lang } = useApp();
  // 部分页面（下载/条款/Cookie/免责/帮助/博客）暂无对应 i18n key，用 zh/en 兜底文案。
  const L = (zh, en) => (lang === "zh" ? zh : en);
  return (
    <footer className="relative pt-20 pb-10 border-t border-app-subtle overflow-hidden" data-testid="main-footer">
      <div className="absolute inset-x-0 bottom-0 flex justify-center pointer-events-none overflow-hidden">
        <span className="font-heading font-black text-[16vw] leading-none tracking-tighter text-transparent select-none" style={{ WebkitTextStroke: "1px var(--border-subtle)" }}>MIRRORSPEED</span>
      </div>
      <div className="relative max-w-6xl mx-auto px-6 sm:px-8">
        <div className="grid grid-cols-2 md:grid-cols-4 gap-8 mb-12">
          <div className="col-span-2 md:col-span-1">
            <div className="flex items-center gap-2 mb-4">
              <img src="/icon-192.png" alt="MirrorSpeed" className="h-8 w-8 rounded-lg" />
              <span className="font-heading font-bold text-lg text-app-primary">MirrorSpeed</span>
            </div>
            <p className="text-sm text-app-secondary max-w-xs">{t("ft_tagline")}</p>
          </div>
          <div>
            <h4 className="font-mono text-[10px] uppercase tracking-widest text-app-muted mb-4">{t("ft_product")}</h4>
            <ul className="space-y-2.5 text-sm text-app-secondary">
              <li><a href="/#features" className="hover:text-app-primary">{t("nav_features")}</a></li>
              <li><a href="/#network" className="hover:text-app-primary">{t("nav_network")}</a></li>
              <li><a href="/#pricing" className="hover:text-app-primary">{t("nav_pricing")}</a></li>
              <li><a href="/download" className="hover:text-app-primary">{L("下载", "Download")}</a></li>
              <li><a href="/#faq" className="hover:text-app-primary">{t("nav_faq")}</a></li>
            </ul>
          </div>
          <div>
            <h4 className="font-mono text-[10px] uppercase tracking-widest text-app-muted mb-4">{t("ft_company")}</h4>
            <ul className="space-y-2.5 text-sm text-app-secondary">
              <li><a href="/servers" className="hover:text-app-primary">{t("ft_servers")}</a></li>
              <li><a href="/blog" className="hover:text-app-primary">{L("博客", "Blog")}</a></li>
              <li><a href="/help" className="hover:text-app-primary">{L("帮助中心", "Help")}</a></li>
              <li><a href="/support" className="hover:text-app-primary">{t("ft_support")}</a></li>
              <li><a href="/login" className="hover:text-app-primary">{t("nav_signin")}</a></li>
            </ul>
          </div>
          <div>
            <h4 className="font-mono text-[10px] uppercase tracking-widest text-app-muted mb-4">{L("法律", "Legal")}</h4>
            <ul className="space-y-2.5 text-sm text-app-secondary">
              <li><a href="/privacy" className="hover:text-app-primary">{t("ft_privacy")}</a></li>
              <li><a href="/terms" className="hover:text-app-primary">{L("服务条款", "Terms")}</a></li>
              <li><a href="/cookies" className="hover:text-app-primary">{L("Cookie 政策", "Cookies")}</a></li>
              <li><a href="/disclaimer" className="hover:text-app-primary">{L("免责声明", "Disclaimer")}</a></li>
            </ul>
          </div>
        </div>
        <div className="pt-8 border-t border-app-subtle flex flex-col sm:flex-row items-center justify-between gap-4">
          <span className="font-mono text-xs text-app-muted">© {new Date().getFullYear()} MirrorSpeed. {t("ft_rights")}</span>
          <div className="flex items-center gap-2 font-mono text-xs text-app-muted">
            <div className="h-1.5 w-1.5 rounded-full pulse-dot" style={{ background: "var(--accent-success)" }} />
            {t("ft_ops")}
          </div>
        </div>
      </div>
    </footer>
  );
};

// ============ Root ============
// `forcedLang` (optional) locks the language at render time and disables auto-detect.
// Used by /cn and /en routes to guarantee the right language regardless of localStorage.
const LandingPage = ({ forcedLang }) => {
  const [lang, setLangState] = useState(forcedLang || "en");
  const [theme, setThemeState] = useState("dark");

  useEffect(() => {
    if (forcedLang) {
      setLangState(forcedLang);
      try { localStorage.setItem("ms_lang", forcedLang); } catch (_) {}
    } else {
      setLangState(detectLang());
    }
    try {
      const savedTheme = localStorage.getItem("ms_theme");
      if (savedTheme === "light" || savedTheme === "dark") setThemeState(savedTheme);
      else if (window.matchMedia && window.matchMedia("(prefers-color-scheme: light)").matches) setThemeState("light");
    } catch (_) {}
  }, [forcedLang]);

  const skipFirstWrite = useRef(true);
  useEffect(() => {
    document.documentElement.setAttribute("data-theme", theme);
    document.documentElement.setAttribute("lang", lang);
    document.documentElement.setAttribute("dir", RTL_LANGS.includes(lang) ? "rtl" : "ltr");
    // 跳过挂载首跑：此时 theme/lang 还是初始默认值（读取 localStorage 的 effect 尚未生效），
    // 若此刻写入会用默认值覆盖掉已保存的偏好（典型表现：把 light 覆盖成 dark）。
    if (skipFirstWrite.current) { skipFirstWrite.current = false; return; }
    try { localStorage.setItem("ms_theme", theme); localStorage.setItem("ms_lang", lang); } catch (_) {}
  }, [theme, lang]);

  return (
    <LandingChromeInner lang={lang} setLang={setLangState} theme={theme} setTheme={setThemeState}>
      <Hero />
      <Onboarding />
      <Features />
      <GlobalNetwork />
      <Testimonials />
      <Pricing />
      <FAQ />
      <FinalCTA />
    </LandingChromeInner>
  );
};

// 内部：仅渲染外壳（导航 + 内容 + 页脚），由 LandingPage / LandingChrome 复用。
const LandingChromeInner = ({ lang, setLang, theme, setTheme, children }) => (
  <AppCtx.Provider value={{ lang, setLang, theme, setTheme }}>
    <div className="ms-landing min-h-screen bg-app text-app-primary overflow-x-hidden">
      <Nav />
      <main>{children}</main>
      <Footer />
    </div>
  </AppCtx.Provider>
);

// 对外：给「下载/隐私/服务条款」等内容页复用同一套导航+页脚+深色玻璃主题，
// 让全站风格统一。children 即页面正文（已自带顶部留白以避开 fixed 导航）。
export const LandingChrome = ({ forcedLang, children }) => {
  const [lang, setLangState] = useState(forcedLang || "en");
  const [theme, setThemeState] = useState("dark");

  useEffect(() => {
    if (forcedLang) setLangState(forcedLang);
    else setLangState(detectLang());
    try {
      const savedTheme = localStorage.getItem("ms_theme");
      if (savedTheme === "light" || savedTheme === "dark") setThemeState(savedTheme);
    } catch (_) {}
  }, [forcedLang]);

  const skipFirstWrite = useRef(true);
  useEffect(() => {
    document.documentElement.setAttribute("data-theme", theme);
    document.documentElement.setAttribute("dir", RTL_LANGS.includes(lang) ? "rtl" : "ltr");
    // 跳过挂载首跑，避免用初始默认 theme 覆盖已保存偏好（详见 LandingPage 同名注释）。
    if (skipFirstWrite.current) { skipFirstWrite.current = false; return; }
    try { localStorage.setItem("ms_theme", theme); } catch (_) {}
  }, [theme, lang]);

  return (
    <LandingChromeInner lang={lang} setLang={setLangState} theme={theme} setTheme={setThemeState}>
      <div className="pt-28 sm:pt-32">{children}</div>
    </LandingChromeInner>
  );
};

export default LandingPage;
