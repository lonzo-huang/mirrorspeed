'use client'

import { useI18n } from "@/lib/i18n";

export interface ServerLocation {
  region: string;
  city: string;
  cityZh: string;
  flag: string;
  latency: number;
  load: number;
  uptime: number;
}

export const SERVERS: ServerLocation[] = [
  { region: "US", city: "United States", cityZh: "美国",   flag: "🇺🇸", latency: 118, load: 67, uptime: 99.92 },
  { region: "SG", city: "Singapore",     cityZh: "新加坡", flag: "🇸🇬", latency: 28,  load: 48, uptime: 99.99 },
  { region: "HK", city: "Hong Kong",     cityZh: "香港",   flag: "🇭🇰", latency: 14,  load: 32, uptime: 99.98 },
  { region: "JP", city: "Japan",         cityZh: "日本",   flag: "🇯🇵", latency: 32,  load: 17, uptime: 99.99 },
  { region: "ES", city: "Spain",         cityZh: "西班牙", flag: "🇪🇸", latency: 188, load: 22, uptime: 99.91 },
  { region: "DE", city: "Germany",       cityZh: "德国",   flag: "🇩🇪", latency: 192, load: 28, uptime: 99.90 },
  { region: "UK", city: "United Kingdom",cityZh: "英国",   flag: "🇬🇧", latency: 178, load: 34, uptime: 99.91 },
  { region: "CH", city: "Switzerland",   cityZh: "瑞士",   flag: "🇨🇭", latency: 196, load: 18, uptime: 99.93 },
];

export function ServerCard({ node }: { node: ServerLocation }) {
  const { lang, t } = useI18n();
  const loadColor = node.load > 80 ? "bg-warn" : "bg-mirror";
  const latColor  = node.latency > 100 ? "text-warn" : "text-mirror";

  return (
    <div className="glass-panel p-5 rounded-2xl hover:border-mirror/40 transition-colors">
      <div className="flex justify-between items-start mb-4">
        <div className="flex items-center gap-2">
          <span className="text-2xl">{node.flag}</span>
          <div>
            <p className="text-sm font-bold leading-tight">{node.region}</p>
            <p className="text-[10px] text-muted-foreground uppercase">{lang === "zh" ? node.cityZh : node.city}</p>
          </div>
        </div>
        <span className="h-2 w-2 bg-mirror rounded-full mt-1.5" />
      </div>
      <div className="space-y-3">
        <div>
          <div className="flex justify-between text-[10px] font-mono text-muted-foreground uppercase mb-1">
            <span>{t.servers.load}</span><span>{node.load}%</span>
          </div>
          <div className="h-1 w-full bg-white/10 rounded-full overflow-hidden">
            <div className={`h-full ${loadColor}`} style={{ width: `${node.load}%` }} />
          </div>
        </div>
        <div className="flex justify-between items-center text-xs">
          <span className="text-muted-foreground">{t.servers.latency}</span>
          <span className={`font-mono font-bold ${latColor}`}>{node.latency}ms</span>
        </div>
        <div className="flex justify-between items-center text-xs">
          <span className="text-muted-foreground">{t.servers.uptime}</span>
          <span className="font-mono">{node.uptime}%</span>
        </div>
      </div>
    </div>
  );
}
