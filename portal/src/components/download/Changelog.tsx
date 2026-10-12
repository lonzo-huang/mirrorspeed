'use client'

import { useEffect, useState } from 'react'
import { useI18n } from '@/lib/i18n'
import type { ChangelogEntry } from '@/app/api/releases/route'

// Release 正文支持双语分段：正文里用 <!--LANG:zh--> / <!--LANG:en--> 标记分隔，
// 本函数按站点语言挑出对应段落。release 正文只维护中/英两种，其它站点语言回退英文。
// 无标记（历史 Release）时整段返回。
function pickLangSection(body: string, lang: string): string {
  if (!body) return ''
  const want = lang === 'zh' ? 'zh' : 'en'   // 正文仅中/英，其余语言用英文
  const re = /<!--\s*LANG:([a-z-]+)\s*-->/gi
  if (!re.test(body)) return body.trim()
  // 切分成 [{lang, text}]
  const sections: Record<string, string> = {}
  let m: RegExpExecArray | null
  const marks: { lang: string; start: number }[] = []
  re.lastIndex = 0
  while ((m = re.exec(body)) !== null) {
    marks.push({ lang: m[1].toLowerCase(), start: m.index + m[0].length })
  }
  for (let i = 0; i < marks.length; i++) {
    const end = i + 1 < marks.length ? body.indexOf('<!--', marks[i].start) : body.length
    sections[marks[i].lang] = body.slice(marks[i].start, end === -1 ? body.length : end).trim()
  }
  return sections[want] ?? sections['en'] ?? Object.values(sections)[0] ?? body.trim()
}

// 行内 **粗体** → <strong>；其余原样。只处理我们自己写的发布说明语法。
function renderInline(text: string, keyBase: string): React.ReactNode[] {
  const out: React.ReactNode[] = []
  const parts = text.split(/(\*\*[^*]+\*\*)/g)
  parts.forEach((p, i) => {
    if (/^\*\*[^*]+\*\*$/.test(p)) {
      out.push(<strong key={`${keyBase}-b${i}`} className="font-semibold text-foreground/90">{p.slice(2, -2)}</strong>)
    } else if (p) {
      out.push(<span key={`${keyBase}-s${i}`}>{p}</span>)
    }
  })
  return out
}

// 极简 markdown：仅 ## / ### 标题、- 或 * 列表、空行分段、**粗体**。不引第三方依赖。
function MarkdownNotes({ md }: { md: string }) {
  const lines = md.replace(/\r\n/g, '\n').split('\n')
  const blocks: React.ReactNode[] = []
  let list: string[] = []
  let key = 0

  const flushList = () => {
    if (list.length === 0) return
    const items = [...list]
    const k = key++
    blocks.push(
      <ul key={`ul${k}`} className="list-disc pl-5 space-y-1 my-2 text-sm text-muted-foreground">
        {items.map((it, i) => <li key={i}>{renderInline(it, `ul${k}-${i}`)}</li>)}
      </ul>,
    )
    list = []
  }

  for (const raw of lines) {
    const line = raw.trimEnd()
    if (/^###\s+/.test(line)) {
      flushList()
      blocks.push(<h5 key={`h${key++}`} className="text-xs font-bold uppercase tracking-wide text-mirror mt-3 mb-1">{line.replace(/^###\s+/, '')}</h5>)
    } else if (/^##\s+/.test(line)) {
      flushList()
      blocks.push(<h4 key={`h${key++}`} className="text-sm font-bold text-foreground mt-3 mb-1">{line.replace(/^##\s+/, '')}</h4>)
    } else if (/^[-*]\s+/.test(line)) {
      list.push(line.replace(/^[-*]\s+/, ''))
    } else if (line.trim() === '') {
      flushList()
    } else {
      flushList()
      blocks.push(<p key={`p${key++}`} className="text-sm text-muted-foreground my-1">{renderInline(line, `p${key}`)}</p>)
    }
  }
  flushList()
  return <div>{blocks}</div>
}

export function Changelog() {
  const { t, lang } = useI18n()
  const dl = t.download
  const [entries, setEntries] = useState<ChangelogEntry[] | null>(null)
  const [expanded, setExpanded] = useState(false)

  useEffect(() => {
    fetch('/api/releases?limit=20', { cache: 'no-store' })
      .then(r => r.json())
      .then(d => setEntries(Array.isArray(d.releases) ? d.releases : []))
      .catch(() => setEntries([]))
  }, [])

  if (entries === null) {
    return <div className="glass-panel rounded-2xl p-6 animate-pulse h-28" />
  }
  if (entries.length === 0) return null

  const shown = expanded ? entries : entries.slice(0, 3)
  const locale = lang === 'zh' ? 'zh-CN' : lang

  return (
    <div>
      <h2 className="text-xl font-bold mb-5">{dl.changelogTitle}</h2>
      <div className="space-y-4">
        {shown.map(r => {
          const notes = pickLangSection(r.body, lang)
          return (
            <div key={r.tag} className="glass-panel rounded-2xl p-6">
              <div className="flex items-center gap-3 mb-2 flex-wrap">
                <span className="text-sm font-mono bg-mirror/10 border border-mirror/20 text-mirror px-3 py-0.5 rounded-full">
                  v{r.version}
                </span>
                {r.prerelease && (
                  <span className="text-[9px] font-bold uppercase tracking-widest text-yellow-500 bg-yellow-500/10 border border-yellow-500/20 px-2 py-0.5 rounded-full">
                    beta
                  </span>
                )}
                {r.published && (
                  <span className="text-[10px] text-muted-foreground font-mono">
                    {(() => { try { return new Date(r.published).toLocaleDateString(locale) } catch { return '' } })()}
                  </span>
                )}
              </div>
              {notes
                ? <MarkdownNotes md={notes} />
                : <p className="text-sm text-muted-foreground">{dl.changelogEmpty}</p>}
            </div>
          )
        })}
      </div>
      {entries.length > 3 && (
        <button
          onClick={() => setExpanded(v => !v)}
          className="mt-5 text-xs font-bold text-mirror hover:underline"
        >
          {expanded ? dl.changelogLess : `${dl.changelogMore} (${entries.length})`}
        </button>
      )}
    </div>
  )
}
