'use client'

import { useI18n } from "@/lib/i18n";

export interface ServerNode {
  code: string;
  city: string;
  cityZh: string;
  flag: string;
  latency: number;
  load: number;
  uptime: number;
  bandwidth: string;
}

export const SERVERS: ServerNode[] = [
  { code: "HK01", city: "Hong Kong",   cityZh: "香港",  flag: "🇭🇰", latency: 14,  load: 24, uptime: 99.98, bandwidth: "10Gbps" },
  { code: "HK02", city: "Hong Kong",   cityZh: "香港",  flag: "🇭🇰", latency: 16,  load: 41, uptime: 99.97, bandwidth: "10Gbps" },
  { code: "SG01", city: "Singapore",   cityZh: "新加坡", flag: "🇸🇬", latency: 28,  load: 48, uptime: 99.99, bandwidth: "10Gbps" },
  { code: "JP01", city: "Tokyo",       cityZh: "东京",  flag: "🇯🇵", latency: 32,  load: 12, uptime: 99.99, bandwidth: "5Gbps"  },
  { code: "JP02", city: "Osaka",       cityZh: "大阪",  flag: "🇯🇵", latency: 38,  load: 22, uptime: 99.95, bandwidth: "5Gbps"  },
  { code: "KR01", city: "Seoul",       cityZh: "首尔",  flag: "🇰🇷", latency: 42,  load: 31, uptime: 99.96, bandwidth: "5Gbps"  },
  { code: "TW01", city: "Taipei",      cityZh: "台北",  flag: "🇹🇼", latency: 24,  load: 55, uptime: 99.94, bandwidth: "5Gbps"  },
  { code: "US01", city: "Los Angeles", cityZh: "洛杉矶", flag: "🇺🇸", latency: 118, load: 89, uptime: 99.92, bandwidth: "10Gbps" },
  { code: "US02", city: "San Jose",    cityZh: "圣何塞", flag: "🇺🇸", latency: 124, load: 67, uptime: 99.93, bandwidth: "10Gbps" },
  { code: "UK01", city: "London",      cityZh: "伦敦",  flag: "🇬🇧", latency: 178, load: 34, uptime: 99.91, bandwidth: "5Gbps"  },
  { code: "DE01", city: "Frankfurt",   cityZh: "法兰克福", flag: "🇩🇪", latency: 192, load: 28, uptime: 99.90, bandwidth: "5Gbps" },
  { code: "AU01", city: "Sydney",      cityZh: "悉尼",  flag: "🇦🇺", latency: 142, load: 19, uptime: 99.94, bandwidth: "5Gbps"  },
];

export function ServerCard({ node }: { node: ServerNode }) {
  const { lang, t } = useI18n();
  const loadColor = node.load > 80 ? "bg-warn" : "bg-mirror";
  const latColor  = node.latency > 100 ? "text-warn" : "text-mirror";

  return (
    <div className="glass-panel p-5 rounded-2xl hover:border-mirror/40 transition-colors">
      <div className="flex justify-between items-start mb-4">
        <div className="flex items-center gap-2">
          <span className="text-lg">{node.flag}</span>
          <div>
            <p className="text-sm font-bold leading-tight">{node.code}</p>
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
